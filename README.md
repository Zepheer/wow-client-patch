# WoW Client Patch

Custom client patch and auto-updater.

## For players

1. Download **WoWPatcher.bat** and **patcher.ps1**
2. Put them in your WoW folder, next to `Wow.exe`
3. Double-click **WoWPatcher.bat**

It checks for a newer patch, downloads it if needed, clears the client cache so
tooltips are current, and starts the game. Run it every time and you will never
be out of date.

When you are already up to date it launches straight away, so the window only
flashes. When it actually installs a patch it holds the message on screen for a
few seconds first.

To read the output whichever happens, run `WoWPatcher.bat keep` — it waits for a
key press before launching.

If the update server is unreachable it starts the game anyway with your current
files, so it can never stop you playing.

## What it installs

`Data\patch-4.MPQ` — custom items, spells and interface data for this server.
