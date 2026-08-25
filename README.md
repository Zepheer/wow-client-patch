# WoW Client Patch

Custom client patch and auto-updater.

## For players

1. Download **WoWPatcher.bat** and **patcher.ps1**
2. Put them in your WoW folder, next to `Wow.exe`
3. Double-click **WoWPatcher.bat**

It checks for a newer patch, downloads it if needed, clears the client cache so
tooltips are current, and starts the game. Run it every time and you will never
be out of date.

If the update server is unreachable it starts the game anyway with your current
files, so it can never stop you playing.

## What it installs

`Data\patch-4.MPQ` — custom items, spells and interface data for this server.

## For the admin

`./publish.sh "what changed"` regenerates `version.txt` from the live patch,
commits it, and uploads the MPQ as a release asset.

**The MPQ is never committed to git** — only `version.txt` is. The binary lives
in Releases, so repository history does not grow with every update.

The patcher reads `/releases/latest/download/patch-4.MPQ`, which GitHub always
points at the newest release, so publishing needs no change to the patcher.
