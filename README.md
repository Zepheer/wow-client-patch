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

## It updates itself

You only ever install these two files by hand. After that the patcher keeps
**itself** up to date too — when a new version is published it downloads it,
checks it, replaces itself and re-runs, all before the game starts.

If that ever fails it says so and carries on with the version you already have,
so it cannot leave you unable to play.

## What it installs

`Data\patch-4.MPQ` — custom items, spells and tooltip data for this server.

`Interface\AddOns\...` — the server's addons. Currently **DungeonObjective**, which
tells you which boss actually completes a random dungeon when you zone in
(`/objective` to see it again).

Your own addons are never touched. The patcher only replaces the folders that came
out of its own archive, and if anything goes wrong with an addon update it says so
and starts the game anyway.
