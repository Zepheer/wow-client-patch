#!/usr/bin/env bash
# Cut a new client patch release.
#
#   ./publish.sh            # use the live client's files
#   ./publish.sh "notes"    # ...and set the notes line players see
#
# Publishes THREE assets and regenerates version.txt to describe all of them:
#   patch-4.MPQ   the client patch (DBCs only - see below)
#   addons.zip    the server addons, unpacked into Interface\AddOns
#   patcher.ps1   the patcher itself, so it can update in place
#
# Only version.txt is committed. The binaries go to Releases so git history
# never grows. patcher.ps1 is BOTH committed (it is source) and released (so
# phase 0 of the patcher can fetch and verify it).
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
	AggroList
)
# -------------------------------------------------------------------------

# Source the MPQ from the MASTER build, not from a game client. /home/tim/WoW is
# NOT the client Tim plays (that lives on the Windows PC), so its Data folder is
# incidental - it was empty when this was first tried, and publishing from a
# stale or half-restored client copy is how you ship the wrong bytes.
SRC="${PATCH_SRC:-/home/tim/Documents/WoW Client Patch/patch-4.MPQ}"

# Addons come from the LIVE client on the Windows PC, over SMB. That machine is
# the only place the addons Tim actually runs exist - /home/tim/WoW was never the
# live client and has since been deleted. Pulling them at publish time means a
# stale local copy can never be shipped by accident.
# Set ADDON_SRC to a local directory to override (e.g. for testing offline).
ADDON_SHARE="${ADDON_SHARE:-//192.168.0.200/WoW}"
ADDON_CREDS="${ADDON_CREDS:-$HOME/.smbcreds-wow}"
ADDON_SRC="${ADDON_SRC:-}"
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

# The patcher ships as its own release asset so it can update itself. Its hash
# goes in the manifest; patcher.ps1 phase 0 compares against it.
# NOTE: publish.sh commits ONLY version.txt. Changes to patcher.ps1 itself still
# need their own git add/commit/push - shipping the asset is not the same as
# committing the source. (Missed once on 2026-08-26.)
[[ -f "$HERE/patcher.ps1" ]] || { echo "ERROR: patcher.ps1 missing" >&2; exit 1; }
PATCHER_SHA=$(sha256sum "$HERE/patcher.ps1" | cut -d' ' -f1)

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
    if [[ -n "$ADDON_SRC" ]]; then
        # local override
        for a in "${ADDONS[@]}"; do
            [[ -d "$ADDON_SRC/$a" ]] || { echo "ERROR: addon '$a' not found at $ADDON_SRC/$a" >&2; exit 1; }
            cp -r "$ADDON_SRC/$a" "$STAGE/$a"
        done
    else
        [[ -r "$ADDON_CREDS" ]] || { echo "ERROR: no SMB credentials at $ADDON_CREDS" >&2; exit 1; }
        command -v smbclient >/dev/null || { echo "ERROR: smbclient not installed" >&2; exit 1; }
        echo "  pulling addons from $ADDON_SHARE ..."
        for a in "${ADDONS[@]}"; do
            # GVFS silently loses large writes, so talk SMB directly. Always.
            smbclient "$ADDON_SHARE" -A "$ADDON_CREDS" \
                -c "prompt off; recurse on; lcd \"$STAGE\"; cd \"Interface\\AddOns\"; mget $a" \
                >/dev/null 2>&1 || true
            if [[ ! -d "$STAGE/$a" ]]; then
                echo "ERROR: could not pull addon '$a' from $ADDON_SHARE" >&2
                echo "       Is the Windows PC on and the share reachable?" >&2
                exit 1
            fi
        done
    fi
    # Strip development files players do not need. BotPanel's tools/ alone is
    # 236K of test harness - nearly half the payload - and ships nothing useful.
    for junk in tools .git .github __pycache__; do
        find "$STAGE" -type d -name "$junk" -exec rm -rf {} + 2>/dev/null || true
    done
    find "$STAGE" -type f \( -name '*.bak' -o -name '*.orig' -o -name '*.py' -o -name '*.pyc' \) \
        -delete 2>/dev/null || true
    # Normalise permissions BEFORE hashing. zip stores the unix mode in each
    # entry, so a file that happens to carry the execute bit changes the archive
    # hash even when every byte of content is identical - which is exactly what
    # happened between v3 (100744, built from a local copy) and v4 (100644,
    # pulled over SMB) and forced a pointless re-download. The zip must depend on
    # names and contents only.
    find "$STAGE" -type d -exec chmod 755 {} +
    find "$STAGE" -type f -exec chmod 644 {} +
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
OLDPATCHERSHA=$(git show HEAD:version.txt 2>/dev/null | sed -n 's/^patcher_sha256=//p' | head -1 || true)
OLD=$(git show HEAD:version.txt 2>/dev/null | sed -n 's/^version=//p' | head -1 || echo 0)
[[ -z "$OLD" ]] && OLD=0

if [[ "$OLDSHA" == "$SHA" && "$OLDADDSHA" == "$ADDON_SHA" && "$OLDPATCHERSHA" == "$PATCHER_SHA" ]]; then
    echo "Patch, addons and patcher are all byte-identical to published version $OLD - nothing to publish."
    exit 0
fi

[[ "$OLDSHA"        == "$SHA"         ]] && echo "  patch:   unchanged" || echo "  patch:   CHANGED"
[[ "$OLDADDSHA"     == "$ADDON_SHA"   ]] && echo "  addons:  unchanged" || echo "  addons:  CHANGED"
[[ "$OLDPATCHERSHA" == "$PATCHER_SHA" ]] && echo "  patcher: unchanged" || echo "  patcher: CHANGED"

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
    echo "patcher_sha256=$PATCHER_SHA"
    echo "notes=$NOTES"
} > version.txt

echo "version.txt updated: v$OLD -> v$NEW"
echo "  patch  sha256 $SHA  ($SIZE bytes)"
[[ -n "$ADDON_SHA" ]] && echo "  addons sha256 $ADDON_SHA  ($ADDON_SIZE bytes) - $ADDON_LIST"
echo "  patcher sha256 $PATCHER_SHA"

if command -v gh >/dev/null 2>&1; then
    git add version.txt
    git commit -m "Patch v$NEW: $NOTES" >/dev/null
    git push
    if [[ -n "$ADDON_SHA" ]]; then
        gh release create "v$NEW" "$SRC" "$ADDON_ZIP" "$HERE/patcher.ps1" --title "Client patch v$NEW" --notes "$NOTES"
    else
        gh release create "v$NEW" "$SRC" "$HERE/patcher.ps1" --title "Client patch v$NEW" --notes "$NOTES"
    fi
    echo "Published. Players get it on next launch."
else
    echo
    echo "gh is not installed - finish manually:"
    echo "  1. git add version.txt && git commit -m 'Patch v$NEW' && git push"
    echo "  2. On GitHub: Releases -> Draft a new release"
    echo "     tag v$NEW, attach:  $SRC"
    [[ -n "$ADDON_SHA" ]] && echo "                        and:  $ADDON_ZIP"
    echo "                        and:  $HERE/patcher.ps1"
    echo "  3. Publish. The patcher uses /releases/latest/download/ so the URL never changes."
fi
