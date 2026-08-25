#!/usr/bin/env bash
# Cut a new client patch release.
#
#   ./publish.sh            # use the live client's patch-4.MPQ
#   ./publish.sh "notes"    # ...and set the notes line players see
#
# Regenerates version.txt from the real file, commits it, and uploads the MPQ
# as a GitHub release asset. version.txt is the ONLY thing committed - the 4.8MB
# binary goes to Releases so git history never grows.
set -euo pipefail

SRC="${PATCH_SRC:-/home/tim/WoW/Data/patch-4.MPQ}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

[[ -f "$SRC" ]] || { echo "ERROR: no patch at $SRC" >&2; exit 1; }

NOTES="${1:-}"
SHA=$(sha256sum "$SRC" | cut -d' ' -f1)
SIZE=$(stat -c%s "$SRC")

OLD=0
[[ -f version.txt ]] && OLD=$(sed -n 's/^version=//p' version.txt | head -1)
[[ -z "$OLD" ]] && OLD=0

OLDSHA=$(sed -n 's/^sha256=//p' version.txt 2>/dev/null | head -1 || true)
if [[ "$OLDSHA" == "$SHA" ]]; then
    echo "The patch is byte-identical to version $OLD - nothing to publish."
    exit 0
fi

NEW=$((OLD + 1))
[[ -z "$NOTES" ]] && NOTES="Client patch v$NEW"

cat > version.txt <<EOF
# Read by WoWPatcher.bat. One key=value per line. Lines starting with # are ignored.
version=$NEW
file=patch-4.MPQ
sha256=$SHA
size=$SIZE
notes=$NOTES
EOF

echo "version.txt updated: v$OLD -> v$NEW"
echo "  sha256 $SHA"
echo "  size   $SIZE bytes"

if command -v gh >/dev/null 2>&1; then
    git add version.txt
    git commit -m "Patch v$NEW: $NOTES" >/dev/null
    git push
    gh release create "v$NEW" "$SRC" --title "Client patch v$NEW" --notes "$NOTES"
    echo "Published. Players get it on next launch."
else
    echo
    echo "gh is not installed - finish manually:"
    echo "  1. git add version.txt && git commit -m 'Patch v$NEW' && git push"
    echo "  2. On GitHub: Releases -> Draft a new release"
    echo "     tag v$NEW, attach:  $SRC"
    echo "  3. Publish. The patcher uses /releases/latest/download/ so the URL never changes."
fi
