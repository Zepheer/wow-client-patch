#!/usr/bin/env bash
# Cut a new client patch release.
#
#   ./publish.sh            # use the live client's files
#   ./publish.sh "notes"    # ...and set the notes line players see
#
# Publishes TWO assets and regenerates version.txt to describe both:
#   patch-4.MPQ   the client patch (DBCs only - see below)
#   addons.zip    the server addons, unpacked into Interface\AddOns
#
# Only version.txt is committed. The binaries go to Releases so git history
# never grows.
#
# WHY ADDONS ARE A SEPARATE ZIP AND NOT INSIDE THE MPQ:
# the 3.3.5 client signature-checks Interface\FrameXML and refuses to start
# with "Your game interface files are corrupt" if anything under Interface\
# is modified inside an MPQ. DBCs are not checked; Interface files are.
# Proven the hard way 2026-08-26. Custom Lua MUST ship as an addon.
set -euo pipefail

# ---- WHICH ADDONS GO OUT TO PLAYERS -------------------------------------
# Add a folder name here and it ships on the next publish. Keep GM-only and
# personal tools OUT of this list (GMPanel).
ADDONS=(
    DungeonObjective
    BotPanel
	Talented
	ConversionTherapy
)
# -------------------------------------------------------------------------

SRC="${PATCH_SRC:-/home/tim/WoW/Data/patch-4.MPQ}"
ADDON_SRC="${ADDON_SRC:-/home/tim/WoW/Interface/AddOns}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

[[ -f "$SRC" ]] || { echo "ERROR: no patch at $SRC" >&2; exit 1; }

git config user.email >/dev/null 2>&1 || {
    echo "ERROR: no git identity in this repo. Run:" >&2
    echo "  git config user.name  \"Zepheer\"" >&2
    echo "  git config user.email \"72371470+Zepheer@users.noreply.github.com\"" >&2
    exit 1
}

NOTES="${1:-}"
SHA=$(sha256sum "$SRC" | cut -d' ' -f1)
SIZE=$(stat -c%s "$SRC")

# ---- build a DETERMINISTIC addons.zip ------------------------------------
# Timestamps and file ordering must not vary, or the zip's hash changes on
# every run and the "nothing to publish" guard below becomes useless - every
# player would re-download an identical archive on every launch.
ADDON_ZIP="$HERE/addons.zip"
ADDON_SHA=""
ADDON_SIZE=""
ADDON_LIST=""

if [[ ${#ADDONS[@]} -gt 0 ]]; then
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE" 2>/dev/null || true' EXIT
    for a in "${ADDONS[@]}"; do
        if [[ ! -d "$ADDON_SRC/$a" ]]; then
            echo "ERROR: addon '$a' not found at $ADDON_SRC/$a" >&2
            exit 1
        fi
        cp -r "$ADDON_SRC/$a" "$STAGE/$a"
    done
    # Strip development files players do not need. BotPanel's tools/ alone is
    # 236K of test harness - nearly half the payload - and ships nothing useful.
    for junk in tools .git .github __pycache__; do
        find "$STAGE" -type d -name "$junk" -exec rm -rf {} + 2>/dev/null || true
    done
    find "$STAGE" -type f \( -name '*.bak' -o -name '*.orig' -o -name '*.py' -o -name '*.pyc' \) \
        -delete 2>/dev/null || true
    # fixed mtime + sorted input = byte-identical zip for identical content
    find "$STAGE" -exec touch -t 200001010000 {} +
    rm -f "$ADDON_ZIP"
    ( cd "$STAGE" && find . -type f | LC_ALL=C sort | zip -q -X -@ "$ADDON_ZIP" >/dev/null )
    unzip -tqq "$ADDON_ZIP" >/dev/null || { echo "ERROR: addons.zip failed its own integrity check" >&2; exit 1; }
    ADDON_SHA=$(sha256sum "$ADDON_ZIP" | cut -d' ' -f1)
    ADDON_SIZE=$(stat -c%s "$ADDON_ZIP")
    ADDON_LIST=$(IFS=', '; echo "${ADDONS[*]}")
fi

# Compare against the last COMMITTED manifest, not the working copy. If a previous
# run died after rewriting version.txt but before committing, the working copy already
# holds the new hash - comparing against it would report "nothing to publish" and exit 0
# on a patch that was never actually released. (Hit for real 2026-08-25.)
OLDSHA=$(git show HEAD:version.txt 2>/dev/null | sed -n 's/^sha256=//p' | head -1 || true)
OLDADDSHA=$(git show HEAD:version.txt 2>/dev/null | sed -n 's/^addons_sha256=//p' | head -1 || true)
OLD=$(git show HEAD:version.txt 2>/dev/null | sed -n 's/^version=//p' | head -1 || echo 0)
[[ -z "$OLD" ]] && OLD=0

if [[ "$OLDSHA" == "$SHA" && "$OLDADDSHA" == "$ADDON_SHA" ]]; then
    echo "Patch and addons are both byte-identical to published version $OLD - nothing to publish."
    exit 0
fi

[[ "$OLDSHA"    == "$SHA"       ]] && echo "  patch:  unchanged" || echo "  patch:  CHANGED"
[[ "$OLDADDSHA" == "$ADDON_SHA" ]] && echo "  addons: unchanged" || echo "  addons: CHANGED"

NEW=$((OLD + 1))
[[ -z "$NOTES" ]] && NOTES="Client patch v$NEW"

{
    echo "# Read by WoWPatcher.bat. One key=value per line. Lines starting with # are ignored."
    echo "version=$NEW"
    echo "file=patch-4.MPQ"
    echo "sha256=$SHA"
    echo "size=$SIZE"
    if [[ -n "$ADDON_SHA" ]]; then
        echo "addons_file=addons.zip"
        echo "addons_sha256=$ADDON_SHA"
        echo "addons_size=$ADDON_SIZE"
        echo "addons_list=$ADDON_LIST"
    fi
    echo "notes=$NOTES"
} > version.txt

echo "version.txt updated: v$OLD -> v$NEW"
echo "  patch  sha256 $SHA  ($SIZE bytes)"
[[ -n "$ADDON_SHA" ]] && echo "  addons sha256 $ADDON_SHA  ($ADDON_SIZE bytes) - $ADDON_LIST"

if command -v gh >/dev/null 2>&1; then
    git add version.txt
    git commit -m "Patch v$NEW: $NOTES" >/dev/null
    git push
    if [[ -n "$ADDON_SHA" ]]; then
        gh release create "v$NEW" "$SRC" "$ADDON_ZIP" --title "Client patch v$NEW" --notes "$NOTES"
    else
        gh release create "v$NEW" "$SRC" --title "Client patch v$NEW" --notes "$NOTES"
    fi
    echo "Published. Players get it on next launch."
else
    echo
    echo "gh is not installed - finish manually:"
    echo "  1. git add version.txt && git commit -m 'Patch v$NEW' && git push"
    echo "  2. On GitHub: Releases -> Draft a new release"
    echo "     tag v$NEW, attach:  $SRC"
    [[ -n "$ADDON_SHA" ]] && echo "                        and:  $ADDON_ZIP"
    echo "  3. Publish. The patcher uses /releases/latest/download/ so the URL never changes."
fi
