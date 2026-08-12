# Chop render worker — native FFmpeg on Modal
import json
import subprocess
import tempfile
import time
import urllib.request

import modal

app = modal.App("chop-render")
image = modal.Image.debian_slim().apt_install("ffmpeg").pip_install("fastapi[standard]", "requests")

RENDER_SECRET = "chop-render-x7k2m9"



def _probe(path: str) -> dict:
    """ffprobe -> duration/size/codec/fps for the first video + audio stream."""
    cmd = ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path]
    pr = subprocess.run(cmd, capture_output=True, text=True)
    if pr.returncode != 0:
        return {}
    info = json.loads(pr.stdout or "{}")
    fmt = info.get("format", {})
    v = next((x for x in info.get("streams", []) if x.get("codec_type") == "video"), {})
    a = next((x for x in info.get("streams", []) if x.get("codec_type") == "audio"), None)
    fps = 0.0
    rate = v.get("avg_frame_rate") or v.get("r_frame_rate") or "0/1"
    try:
        num, den = rate.split("/")
        fps = round(float(num) / float(den), 3) if float(den) else 0.0
    except Exception:
        fps = 0.0
    rot = None
    for sd in v.get("side_data_list", []) or []:
        if "rotation" in sd:
            rot = sd.get("rotation")
    dur = fmt.get("duration") or v.get("duration") or 0
    return {
        "duration": round(float(dur), 3),
        "bytes": int(fmt.get("size") or 0),
        "codec": v.get("codec_name"),
        "width": int(v.get("width") or 0),
        "height": int(v.get("height") or 0),
        "fps": fps,
        "rotation": rot,
        "has_audio": a is not None,
        "profile": v.get("profile"),
        "pix_fmt": v.get("pix_fmt"),
    }


@app.function(image=image, timeout=1800, memory=4096, cpu=4.0)
def proxy_worker(src_url: str, put_url: str) -> dict:
    """The heavy half, run as its OWN Modal execution.

    Spawned by the web endpoint, so nothing upstream has to stay alive while a
    200MB+ 4K HEVC source is downloaded, transcoded and pushed back to R2.
    Phase timings are broken out because download dominates on real phone files.
    ffmpeg auto-applies the display matrix, so iPhone footage stored landscape
    with a -90 rotation arrives at the filter chain already upright."""
    import requests

    t_all = time.time()
    with tempfile.TemporaryDirectory() as td:
        src, out = f"{td}/src", f"{td}/proxy.mp4"

        t0 = time.time()
        try:
            urllib.request.urlretrieve(src_url, src)
        except Exception as e:
            return {"ok": False, "error": f"download failed: {e}", "phase": "download"}
        dl_ms = int((time.time() - t0) * 1000)

        sp = _probe(src)
        if not sp or not sp.get("duration"):
            return {"ok": False, "error": "could not probe source", "phase": "probe"}

        vf = ("scale=540:960:force_original_aspect_ratio=decrease,"
              "pad=540:960:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1")
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", src, "-map", "0:v:0"]
        if sp.get("has_audio"):
            cmd += ["-map", "0:a:0"]
        cmd += [
            "-vf", vf,
            "-r", "30", "-vsync", "cfr",
            "-c:v", "libx264", "-profile:v", "main", "-level", "3.1",
            "-pix_fmt", "yuv420p", "-preset", "veryfast",
            "-crf", "26", "-maxrate", "900k", "-bufsize", "1800k",
            "-g", "15", "-keyint_min", "15", "-sc_threshold", "0",
        ]
        if sp.get("has_audio"):
            cmd += ["-c:a", "aac", "-b:a", "96k", "-ar", "48000",
                    "-af", "aresample=async=1:first_pts=0"]
        cmd += ["-movflags", "+faststart", out]

        t0 = time.time()
        pr = subprocess.run(cmd, capture_output=True, text=True)
        enc_ms = int((time.time() - t0) * 1000)
        if pr.returncode != 0:
            return {"ok": False, "error": f"ffmpeg failed: {pr.stderr[-400:]}", "phase": "encode", "src": sp}

        pp = _probe(out)
        if not pp or not pp.get("duration"):
            return {"ok": False, "error": "could not probe proxy", "phase": "probe2", "src": sp}

        t0 = time.time()
        try:
            with open(out, "rb") as f:
                r = requests.put(put_url, data=f, headers={"Content-Type": "video/mp4"}, timeout=900)
            if r.status_code not in (200, 201, 204):
                return {"ok": False, "error": f"r2 put {r.status_code}: {r.text[:200]}", "phase": "upload", "src": sp}
        except Exception as e:
            return {"ok": False, "error": f"upload failed: {e}", "phase": "upload", "src": sp}
        up_ms = int((time.time() - t0) * 1000)

    return {
        "ok": True,
        "duration": pp["duration"], "src_duration": sp["duration"],
        "width": pp["width"], "height": pp["height"], "fps": pp["fps"],
        "bytes": pp["bytes"], "codec": pp["codec"],
        "profile": pp.get("profile"), "pix_fmt": pp.get("pix_fmt"),
        "src_bytes": sp["bytes"], "src_codec": sp["codec"],
        "src_width": sp["width"], "src_height": sp["height"],
        "src_fps": sp["fps"], "src_rotation": sp.get("rotation"),
        "dl_ms": dl_ms, "enc_ms": enc_ms, "up_ms": up_ms,
        "ms": int((time.time() - t_all) * 1000),
    }


@app.function(image=image, timeout=900, memory=4096, cpu=4.0)
@modal.asgi_app()
def api():
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import Response

    web = FastAPI()
    web.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @web.post("/proxy-start")
    def proxy_start(payload: dict):
        """Returns in milliseconds. Modal owns the execution from here."""
        if payload.get("secret") != RENDER_SECRET:
            return Response(content="forbidden", status_code=403)
        if not payload.get("url") or not payload.get("put"):
            return {"ok": False, "error": "url and put are required"}
        call = proxy_worker.spawn(payload["url"], payload["put"])
        return {"ok": True, "call_id": call.object_id}

    @web.post("/proxy-poll")
    def proxy_poll(payload: dict):
        """Non-blocking status for a spawned call."""
        if payload.get("secret") != RENDER_SECRET:
            return Response(content="forbidden", status_code=403)
        cid = payload.get("call_id")
        if not cid:
            return {"ok": False, "error": "call_id required"}
        try:
            fc = modal.FunctionCall.from_id(cid)
        except Exception as e:
            return {"ok": True, "state": "missing", "error": str(e)[:200]}
        try:
            res = fc.get(timeout=0)
            return {"ok": True, "state": "done", "result": res}
        except TimeoutError:
            return {"ok": True, "state": "running"}
        except modal.exception.OutputExpiredError as e:
            return {"ok": True, "state": "missing", "error": f"output expired: {e}"}
        except Exception as e:
            msg = str(e)
            # a genuinely unknown id is terminal; anything else may be transient
            if "No Function Call" in msg or "not found" in msg.lower():
                return {"ok": True, "state": "missing", "error": msg[:300]}
            return {"ok": True, "state": "failed", "error": msg[:300]}

    @web.post("/render")
    def render(payload: dict):
        if payload.get("secret") != RENDER_SECRET:
            return Response(content="forbidden", status_code=403)
        url = payload["url"]
        cuts = payload.get("kept", [])
        fade = float(payload.get("fade", 0.125))
        if not cuts:
            return Response(content="no clips", status_code=400)

        with tempfile.TemporaryDirectory() as td:
            src, out = f"{td}/in.mp4", f"{td}/out.mp4"
            urllib.request.urlretrieve(url, src)

            parts, chain = [], []
            for i, c in enumerate(cuts):
                s, e = float(c["s"]), float(c["e"])
                d = max(0.05, e - s)
                fd = min(fade, d / 2)
                parts.append(
                    f"[0:v]trim=start={s:.3f}:end={e:.3f},setpts=PTS-STARTPTS[v{i}];"
                    f"[0:a]atrim=start={s:.3f}:end={e:.3f},asetpts=PTS-STARTPTS,"
                    f"afade=t=in:d={fd:.3f},afade=t=out:st={max(0, d - fd):.3f}:d={fd:.3f}[a{i}];"
                )
                chain.append(f"[v{i}][a{i}]")
            # every output lands at exactly 1080 wide: 4K compresses down
            # (TikTok-style), small sources upscale, 1080 passes through
            fc = (
                "".join(parts) + "".join(chain)
                + f"concat=n={len(cuts)}:v=1:a=1[vc][a];"
                + "[vc]scale=w=1080:h=-2:flags=lanczos[v]"
            )
            cmd = [
                "ffmpeg", "-y", "-v", "error", "-i", src,
                "-filter_complex", fc, "-map", "[v]", "-map", "[a]",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out,
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0:
                return Response(content=f"ffmpeg failed: {proc.stderr[-500:]}", status_code=500)
            with open(out, "rb") as f:
                data = f.read()
        return Response(content=data, media_type="video/mp4")

    return web
