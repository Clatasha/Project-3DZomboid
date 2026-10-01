# Project 3DZomboid

Windows setup helper for Project Viewpoint and ZombieBuddy, targeting Project Zomboid Build 42.21.

Supports Steam and standalone game folders. Launches the selected game executable directly. Includes file backups and restore protection for later changes.

## Running

Use the complete test ZIP supplied in ChatGPT, extract it, and run `Start-Setup.cmd`. This repository contains installer source only. Third-party runtime mod files are not redistributed here.

Automatic build detection is best-effort. If inconclusive, check the version in the game main menu and confirm Build 42.21 in the installer. First launch still requires enabling the mods and approving Viewpoint through ZombieBuddy.

## Tests

`powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File Setup.ps1 -SelfTest`

The Windows workflow checks PowerShell syntax and launcher-edit and build-confirmation behavior. Gameplay testing is separate.

## Runtime files

The portable package needs `payload-hashes.json` and a `payload` directory containing the user-provided patched `ZombieBuddy.jar`, `zbNative.dll`, and complete `ZombieBuddy` and `Viewpoint` mod folders. The optional 6244-model pack is not bundled.

Credits: ZombieBuddy by Andrey Zed Zaikin; temporary 42.21 compatibility fix by Antikristianos; Viewpoint by ellu/norkus.
