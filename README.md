## Disclaimer

**Installify is a fan-made tool and is not affiliated with Stress Level Zero or mod.io. Use it at your own risk and keep a backup of mods you care about.**

# Installify

**One-click installer for BONELAB mods.**

**DOES NOT SUPPORT STANDALONE INSTALLATION YET.**

tired of unzipping every mod by hand?, guessing where it belongs and fixing the folder structure afterwards because Mod.Io is Janky alot of times, I have the cure so I built Installify. Drop it into the folder that contains your downloaded mods (It doesen't need to be in the Drive where the game is at), double-click it, pick your options and let it do the work.

## Features

- **Scans a whole folder**, including subfolders, for mods that are still zipped *and* mods that are already unpacked
- **Finds BONELAB on its own** (Steam registry, all Steam library folders and the usual install locations on every drive)
- **Puts every mod in the right place** (see [Where things go](#where-things-go))
- **Small options window** on start: folder to scan, game folder, dry run (For Testing if everything is Configured right), force reinstall (Reinstalls every Mod that is zipped or unzipped in you're Folder)
- **Updates mods in place**: an existing mod folder with the same name gets replaced by the new version
- **Remembers what is already installed** and skips it next time :]
- **Saves progress after every single mod**, so closing the window or a crash never loses your progress
- **Low disk space protection**: checks free space before each mod and stops cleanly when the drive is full, without leaving half-copied mods behind. Free up space (or enlarge the drive), run it again and it continues where it stopped
- **Never deletes your downloads**: **YOUR ZIPS AND FOLDERS ARE ONLY READ AND COPIED!!!!NOTHING IS DELETED. ANY EXISTING MODS STAY WHERE THEY BELONG!!!!**

## Requirements

- Windows 10 / 11 (uses the Windows PowerShell that is already included, if not Installed visit: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6)
- BONELAB (Steam/Meta, **DOES NOT SUPPORT STANDALONE INSTALLATION YET.**)
- [MelonLoader](https://melonwiki.xyz) installed in the game, only if you want to install code mods (DLL mods)

## Usage
 **RECOMMENDED TO TRY DRY RUN FIRST**
1. Put `Installify.bat` into the folder that contains your mods (ZIP files or unpacked mod folders).
2. Double-click `Installify.bat`.
3. In the options window check the folder to scan and the game folder (both are filled in automatically) and press **Start**.
4. Wait until it says `Done`. Start BONELAB and your mods are there.

You can also drag any folder onto `Installify.bat` to scan that folder instead.

### Options

| Option | What it does |
| 
| Folder to scan | The folder (including subfolders) that is searched for mods. 
| Defaults to the folder `Installify.bat` is in. |
| BONELAB game folder Auto-detected. Change it only if it is wrong. If left empty, only Marrow mods are installed. |
| **Dry run** | Shows what would happen and changes nothing. **RECOMMENDED TRY FIRST**. |
| **Force** | Reinstalls everything, even mods that are already marked as installed. |

### Command line (optional)

```
Installify.bat -DryRun      pre-ticks "Dry run" in the window
Installify.bat -Force       pre-ticks "Force"
Installify.bat -NoGui       skips the window and uses the command line options only
```

## Where things go

| What Installify finds | Where it is installed |
| --- | --- |
| Marrow mods (anything with a `pallet.json` or `<Name>.pallet.json`, e.g. most mods from mod.io) | `%USERPROFILE%\AppData\LocalLow\Stress Level Zero\BONELAB\Mods\<ModName>` |
| MelonLoader mods in a ZIP (contains `.dll` files) | `<BONELAB folder>\Mods`, or `Plugins` / `UserLibs` / `UserData` if the ZIP contains those folders |
| Loose `.dll` files | `<BONELAB folder>\Mods` |

DLLs that belong to a Marrow mod stay inside that mod and are not copied separately.

## Good to know

- **Progress file:** Installify writes `installify_state.json` next to itself. Delete it (or use Force) if you want everything installed again.
- **Disk space:** Each ZIP is unpacked to your Temp folder first, then copied. Make sure the drive that holds `AppData` has enough free space. Leftover temp folders from an aborted run (`bl_scan_*`) are cleaned up on the next start.
- **Quest mods:** Installify does not tell Windows and Quest builds apart. Make sure you downloaded the PC version of a mod.
- **Mod dependencies:** Some mods need other mods. Check the mod page if something does not show up in game.
- **Windows SmartScreen / antivirus:** `.bat` files from the internet can trigger a warning. The whole script is plain text inside the file, so you can open it in any editor and read exactly what it does.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| `Game (Steam) not found` | Pick the BONELAB folder manually in the options window. |
| `nothing installed (neither pallet.json nor a usable DLL)` | The ZIP has a layout Installify does not know. Install that one by hand. |
| `DISK FULL - installation is being stopped` | Free up space on the drive named in the message and run Installify again. |
| Mod does not appear in game | Check the mod page for dependencies and make sure it is the PC version. |

## Feedback

Found a ZIP layout that does not work or have an idea? Open an issue and attach the file list of the ZIP, that makes it easy to fix for me.

## Disclaimer

**Installify is a fan-made tool and is not affiliated with Stress Level Zero or mod.io. Use it at your own risk and keep a backup of mods you care about.**
