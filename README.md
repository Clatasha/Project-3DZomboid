<p align="center">
  <img src="https://raw.githubusercontent.com/Clatasha/Project-3DZomboid/refs/heads/main/project-zomboid.png" width="100%" alt="Project Zomboid 3D">
</p>

# Project 3DZomboid

A Windows setup helper for playing Project Zomboid in first or third person using Project Viewpoint and ZombieBuddy.

**Targets Build 42.21.** Supports Steam installations and standalone game folders.

[Download v0.1.1](https://github.com/Clatasha/Project-3DZomboid/releases/tag/v0.1.1)

## Install

1. Download `PZ-3D-Setup-v0.1.1.zip` from Releases and extract the whole ZIP.
1.b Download optional Working verified Cracked that works with it https://www.mediafire.com/file/ymx8jkn26pip2ah/Project.Zomboid.v42.21.Early.Access.rar/file 
2. Run `Start-Setup.cmd`.
3. Check the detected game folder, or choose it with **Browse**.
4. Remove any old ZombieBuddy agent launch arguments and confirm the checkbox.
5. Click **Install 3D Setup**. If version detection is inconclusive, check the version in the game main menu and tick the Build 42.21 confirmation.
6. Click **Launch Game**. Enable **ZombieBuddy** and **Viewpoint** and approve Viewpoint in the Java mod approval window.
7. Start a new test save with those mods enabled. Press **O** for 3D; **Shift+O** switches first/third person.

Existing saves can have their own mod selection. The optional [6244-model pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3810302175) is not bundled.

## What the helper handles

- Finds Steam installations, with a folder picker for other installations.
- Installs the loader and temporary 42.21 compatibility patch.
- Configures Normal and Alternate Launch.
- Reuses Workshop copies in the game's library or installs the bundled local mods.
- Backs up changed files and offers **Restore Previous Files**.
- Starts the executable directly from the selected game folder.

Restore stops if a tracked file changed later, preserving updates. Saves and Java approvals are preserved. Local mod copies do not update through Steam automatically; restore them before switching to Workshop copies.

This is a portable PowerShell GUI launched by a CMD file. It uses Windows PowerShell 5.1, with no Python required. The game itself is not included.

## Testing and feedback

Initial Windows gameplay testing passed. This is a public testing release for more people to try.

[Report a problem](https://github.com/Clatasha/Project-3DZomboid/issues). Include the game version, Windows version, error text, and whether you used a Steam or standalone folder.

Windows CI checks syntax, launcher edits, and the build confirmation fallback. Release publishing also verifies the archive, runtime hashes, and source/package consistency.

## Credits

This is an unofficial setup helper. Original mod authors retain ownership of their mods.

- [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy) by Andrey “Zed” Zaikin, MIT license included.
- [Temporary Build 42.21 fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3807686870) by Antikristianos.
- [Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528) by ellu/norkus.
