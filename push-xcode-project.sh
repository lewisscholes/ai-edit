#!/bin/bash
# Puts the Xcode project into the repo so Lewis can actually build.
# Run:  bash ~/Downloads/ai-edit/push-xcode-project.sh
set -e

SRC="$HOME/Desktop/ChopNativeVideoPOC"
REPO="$HOME/Downloads/ai-edit"
DEST="$REPO/ios/ChopNativeVideoPOC"

[ -d "$SRC" ] || { echo "Not found: $SRC"; exit 1; }

echo "→ copying project"
mkdir -p "$REPO/ios"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude 'DerivedData/' \
  --exclude '*.xcuserstate' \
  --exclude 'xcuserdata/' \
  --exclude '.DS_Store' \
  --exclude '*.MOV' \
  --exclude '*.mov' \
  --exclude '*.mp4' \
  "$SRC/" "$DEST/"

echo "→ writing ios/.gitignore"
cat > "$REPO/ios/.gitignore" <<'EOF'
build/
DerivedData/
xcuserdata/
*.xcuserstate
*.xcworkspace/xcuserdata/
.DS_Store
*.MOV
*.mov
*.mp4
EOF

echo "→ checking nothing huge slipped in"
BIG=$(find "$DEST" -type f -size +5M 2>/dev/null || true)
if [ -n "$BIG" ]; then
  echo "  WARNING — files over 5 MB:"
  echo "$BIG" | sed 's/^/    /'
  echo "  Ctrl-C now if any of those should not be in git."
  sleep 5
fi

cd "$REPO"
git add ios
git commit -m "Add the Xcode project so the native app can be built from a clone"

echo
echo "→ ready to push. Review, then run:"
echo "     cd ~/Downloads/ai-edit && git push"
echo
git log --oneline -3
git diff --stat HEAD~1 HEAD | tail -1
