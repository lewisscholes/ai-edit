#!/bin/bash
# Fixes the previous push: the Xcode project went in as a submodule pointer
# instead of real files, so a clone gets an empty folder.
#
# Safe: only touches the COPY inside the repo. Your project at
# ~/Desktop/ChopNativeVideoPOC and its history are left alone.
#
# Run:  bash ~/Downloads/ai-edit/fix-xcode-push.sh
set -e

REPO="$HOME/Downloads/ai-edit"
DEST="$REPO/ios/ChopNativeVideoPOC"
cd "$REPO"

[ -d "$DEST" ] || { echo "Not found: $DEST — run push-xcode-project.sh first"; exit 1; }

echo "→ removing the submodule pointer"
git rm --cached ios/ChopNativeVideoPOC -q 2>/dev/null || true
rm -f .gitmodules
git config --remove-section submodule.ios/ChopNativeVideoPOC 2>/dev/null || true

echo "→ deleting the nested .git inside the copy (not your Desktop project)"
rm -rf "$DEST/.git"

echo "→ re-adding as real files"
git add ios

N=$(git diff --cached --name-only | wc -l | tr -d ' ')
echo "→ $N files staged"
if [ "$N" -lt 5 ]; then
  echo "  STOP — that is too few. Something is still wrong. Paste this output back."
  exit 1
fi

echo "→ largest staged files:"
git diff --cached --name-only | while read -r f; do
  [ -f "$f" ] && echo "$(du -k "$f" | cut -f1) $f"
done | sort -rn | head -5 | awk '{printf "    %s KB  %s\n", $1, $2}'

git commit -q -m "Commit the Xcode project as files, not a submodule pointer"
echo
echo "→ verifying the project file is really in the tree:"
git ls-files ios/ | grep -c "project.pbxproj" | xargs -I{} echo "    project.pbxproj entries: {}"
echo
echo "→ now push:"
echo "     cd ~/Downloads/ai-edit && git push"
