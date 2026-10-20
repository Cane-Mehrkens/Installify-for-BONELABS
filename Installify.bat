@echo off
rem ==========================================================================
rem  Installify.bat  -  ONE file, just double-click it.
rem  Put it in the folder that contains your (not yet installed) mods. It scans
rem  that folder and all subfolders (ZIPs and unpacked mods), finds the game
rem  by itself and installs everything to the right place.
rem  - Progress is saved after EVERY mod.
rem  - If disk space runs out, it stops cleanly. After freeing space or upgrading
rem    the drive, just run it again: finished mods are skipped.
rem  Optional: drag & drop another folder onto this file to scan that instead.
rem  A small options window appears on start (folder, game folder, dry run, force).
rem  Command line: -DryRun, -Force prefill the window; -NoGui skips the window.
rem ==========================================================================
set "BL_DIR=%~dp0"
set "BL_SRC=%~1"
set "BL_ARGS=%*"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0'); $i=$t.LastIndexOf(([string][char]10)+'#PS_BEGIN'); Invoke-Expression $t.Substring($i)"
exit /b
#PS_BEGIN
$ErrorActionPreference = 'Stop'
$scriptDir = $env:BL_DIR.TrimEnd('\')
$SourceDir = $scriptDir
if ($env:BL_SRC -and (Test-Path -LiteralPath $env:BL_SRC -PathType Container)) { $SourceDir = (Resolve-Path -LiteralPath $env:BL_SRC).Path.TrimEnd('\') }
$DryRun = [bool]($env:BL_ARGS -match '(?i)-DryRun')
$Force  = [bool]($env:BL_ARGS -match '(?i)-Force')
$ModsTarget = Join-Path $env:USERPROFILE "AppData\LocalLow\Stress Level Zero\BONELAB\Mods"
$stateFile = Join-Path $scriptDir "installify_state.json"
$margin = 300MB
$script:abort = $false
$script:abortMsg = ""
$script:lastDest = $null

# ---------- Find the game automatically ----------
function Find-BonelabDir {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($k in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = Get-ItemProperty $k -ErrorAction Stop
            foreach ($n in 'SteamPath','InstallPath') {
                if ($p.$n) {
                    $root = ($p.$n -replace '/','\').TrimEnd('\')
                    $libs.Add($root)
                    $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
                    if (Test-Path $vdf) {
                        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs.Add(($m.Groups[1].Value -replace '\\\\','\').TrimEnd('\')) }
                    }
                }
            }
        } catch {}
    }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
        $r = $d.Root.TrimEnd('\')
        foreach ($s in @('SteamLibrary','Steam','Games\Steam','Games\SteamLibrary','Program Files (x86)\Steam','Program Files\Steam')) { $libs.Add("$r\$s") }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $common = Join-Path $lib "steamapps\common"
        $acf = Join-Path $lib "steamapps\appmanifest_1592190.acf"
        if (Test-Path $acf) {
            $m = [regex]::Match((Get-Content $acf -Raw), '"installdir"\s+"([^"]+)"')
            if ($m.Success -and (Test-Path (Join-Path $common $m.Groups[1].Value))) { return (Join-Path $common $m.Groups[1].Value) }
        }
        if (Test-Path (Join-Path $common "BONELAB")) { return (Join-Path $common "BONELAB") }
    }
    return $null
}

# ---------- Disk space helpers ----------
function Get-FreeBytes($path) {
    try { return [long](New-Object IO.DriveInfo([IO.Path]::GetPathRoot($path))).AvailableFreeSpace } catch { return [long]::MaxValue }
}
function Get-ZipSize($zipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $sum = 0L; foreach ($e in $z.Entries) { $sum += $e.Length }; return $sum } finally { $z.Dispose() }
}
function Get-DirSize($path) {
    $s = (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($s) { return [long]$s } else { return 0L }
}
# Checks that all target drives have enough free space. Returns $null (ok) or a message.
function Test-Space([long]$bytes, [string[]]$targets) {
    $need = @{}
    foreach ($t in $targets) { $r = [IO.Path]::GetPathRoot($t); if ($need.ContainsKey($r)) { $need[$r] += $bytes } else { $need[$r] = $bytes } }
    foreach ($r in $need.Keys) {
        $free = Get-FreeBytes $r
        if ($free -lt ($need[$r] + $margin)) {
            return ("Drive {0} has only {1:N0} MB free, about {2:N0} MB (plus reserve) needed." -f $r, ($free / 1MB), ($need[$r] / 1MB))
        }
    }
    return $null
}
function Test-DiskFullError($err, [string[]]$targets) {
    if ($err.Exception.Message -match '(?i)nicht genug Speicherplatz|not enough space|disk is full|Datentr.ger ist voll|0x80070070|Fehler 112|Code 112|error 112') { return $true }
    foreach ($t in $targets) { if ((Get-FreeBytes $t) -lt 50MB) { return $true } }
    return $false
}
function Save-State {
    try {
        $tmp = $stateFile + ".tmp"
        $state | ConvertTo-Json | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $stateFile -Force
    } catch { Write-Host "    (Could not save progress: $($_.Exception.Message))" -ForegroundColor Yellow }
}
function Remove-Partial {
    if ($script:lastDest -and (Test-Path -LiteralPath $script:lastDest) -and !$DryRun) {
        Remove-Item -LiteralPath $script:lastDest -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    Removed incompletely copied mod folder: $script:lastDest" -ForegroundColor DarkGray
    }
    $script:lastDest = $null
}
function Stop-NoSpace($msg) {
    $script:abort = $true
    $script:abortMsg = $msg
    Write-Host ""
    Write-Host "!!! DISK FULL - installation is being stopped !!!" -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
}

# ---------- Options window (shown on double-click) ----------
function Show-OptionsDialog($src, $game, [bool]$dry, [bool]$force) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $font = New-Object System.Drawing.Font("Segoe UI", 9)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Installify"
    $f.ClientSize = New-Object System.Drawing.Size(580, 330)
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.Font = $font

    function New-Ctl($type, $x, $y, $w, $h, $text) {
        $c = New-Object $type
        $c.Location = New-Object System.Drawing.Point($x, $y)
        $c.Size = New-Object System.Drawing.Size($w, $h)
        if ($text) { $c.Text = $text }
        $f.Controls.Add($c)
        return $c
    }

    $title = New-Ctl System.Windows.Forms.Label 20 14 540 30 "Installify"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $null = New-Ctl System.Windows.Forms.Label 22 48 540 20 "Installs BONELAB mods (ZIPs and unpacked folders) to the right place."

    $null = New-Ctl System.Windows.Forms.Label 22 82 300 18 "Folder to scan for mods:"
    $tbSrc = New-Ctl System.Windows.Forms.TextBox 22 102 440 24 $src
    $bSrc = New-Ctl System.Windows.Forms.Button 472 100 86 27 "Browse..."

    $null = New-Ctl System.Windows.Forms.Label 22 140 300 18 "BONELAB game folder:"
    $tbGame = New-Ctl System.Windows.Forms.TextBox 22 160 440 24 $game
    $bGame = New-Ctl System.Windows.Forms.Button 472 158 86 27 "Browse..."
    if ($game) { $hint = "Auto-detected. Only change this if it is wrong." }
    else { $hint = "Not found. Choose it, or leave empty to install only Marrow mods (no DLL mods)." }
    $hl = New-Ctl System.Windows.Forms.Label 22 188 540 18 $hint
    $hl.ForeColor = [System.Drawing.Color]::Gray

    $chkDry = New-Ctl System.Windows.Forms.CheckBox 22 218 540 22 "Dry run - only show what would happen, change nothing"
    $chkDry.Checked = $dry
    $chkForce = New-Ctl System.Windows.Forms.CheckBox 22 244 540 22 "Force - reinstall everything, even mods that are already installed"
    $chkForce.Checked = $force

    $bStart = New-Ctl System.Windows.Forms.Button 372 286 90 30 "Start"
    $bCancel = New-Ctl System.Windows.Forms.Button 472 286 86 30 "Cancel"
    $f.AcceptButton = $bStart
    $f.CancelButton = $bCancel
    $bCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $browse = {
        param($tb)
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($tb.Text -and (Test-Path -LiteralPath $tb.Text -PathType Container)) { $d.SelectedPath = $tb.Text }
        if ($d.ShowDialog($f) -eq 'OK') { $tb.Text = $d.SelectedPath }
    }
    $bSrc.Add_Click({ & $browse $tbSrc })
    $bGame.Add_Click({ & $browse $tbGame })
    $bStart.Add_Click({
        if (!$tbSrc.Text -or !(Test-Path -LiteralPath $tbSrc.Text -PathType Container)) {
            [System.Windows.Forms.MessageBox]::Show($f, "The folder to scan does not exist.", "Installify") | Out-Null
            return
        }
        $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $f.Close()
    })

    $res = $f.ShowDialog()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return @{ Source = $tbSrc.Text.Trim(); Game = $tbGame.Text.Trim(); DryRun = $chkDry.Checked; Force = $chkForce.Checked }
}

$GameDir = Find-BonelabDir
if ($env:BL_ARGS -match '(?i)-NoGui') {
    # no window: use command line options as before
} else {
    $opt = Show-OptionsDialog $SourceDir $GameDir $DryRun $Force
    if (!$opt) { Write-Host "Cancelled."; exit }
    $SourceDir = (Resolve-Path -LiteralPath $opt.Source).Path.TrimEnd('\')
    $DryRun = [bool]$opt.DryRun
    $Force = [bool]$opt.Force
    if ($opt.Game -and (Test-Path -LiteralPath $opt.Game -PathType Container)) { $GameDir = $opt.Game.TrimEnd('\') }
    elseif ($opt.Game) { Write-Host "Game folder not found: $($opt.Game)" -ForegroundColor Yellow; $GameDir = $null }
    else { $GameDir = $null }
}
Write-Host "Source (being scanned): $SourceDir"
Write-Host "Marrow mods go to:     $ModsTarget"
if ($GameDir) { Write-Host "Game found:           $GameDir" -ForegroundColor Green }
else { Write-Host "Game (Steam) not found - only Marrow mods (pallet.json) will be installed, not DLL mods." -ForegroundColor Yellow }
if ($DryRun) { Write-Host "*** DRY RUN: nothing will be changed ***" -ForegroundColor Yellow }
Write-Host ""

$excludes = @($ModsTarget)
if ($GameDir) { $excludes += @((Join-Path $GameDir "MelonLoader"), (Join-Path $GameDir "Mods"), (Join-Path $GameDir "Plugins"), (Join-Path $GameDir "UserLibs")) }
$excludes = $excludes | ForEach-Object { $_.TrimEnd('\') + '\' }
function Test-Excluded($path) {
    foreach ($e in $excludes) { if (($path + '\').StartsWith($e, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}
function Merge-Folder($src, $dst) {
    if ($DryRun) { Write-Host "    [DryRun] $src -> $dst" -ForegroundColor DarkGray; return }
    if (!(Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy error (code $LASTEXITCODE) at $src" }
}

# Installs mods from unpacked ZIP contents. Returns the number of installed mods.
function Install-FromRoot($root, $fallbackName) {
    $root = $root.TrimEnd('\')
    $count = 0
    $pallets = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *pallet.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(^|\.)pallet\.json$' })
    if ($pallets.Count -gt 0) {
        $seen = @{}
        foreach ($p in $pallets) {
            $dir = $p.Directory
            if ($seen.ContainsKey($dir.FullName)) { continue }
            $seen[$dir.FullName] = $true
            $name = $p.Name -replace '\.?pallet\.json$',''
            if ($dir.FullName.TrimEnd('\') -ne $root) { $name = $dir.Name }
            if (!$name) { $name = $fallbackName }
            $dest = Join-Path $ModsTarget $name
            Write-Host "    Marrow mod: $name"
            if ((Test-Path $dest) -and !$DryRun) { Remove-Item -LiteralPath $dest -Recurse -Force }
            $script:lastDest = $dest
            Merge-Folder $dir.FullName $dest
            $script:lastDest = $null
            $count++
        }
        return $count
    }
    $dlls = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.dll -File -ErrorAction SilentlyContinue)
    if ($dlls.Count -gt 0) {
        if (!$GameDir) { Write-Host "    DLL mod skipped: game folder not found." -ForegroundColor Yellow; return 0 }
        if (!(Test-Path (Join-Path $GameDir "MelonLoader"))) { Write-Host "    WARNING: MelonLoader is not installed in the game folder." -ForegroundColor Yellow }
        $special = @('Mods','Plugins','UserLibs','UserData')
        $topDirs = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $special -contains $_.Name })
        if ($topDirs.Count -gt 0) {
            foreach ($d in $topDirs) { Write-Host "    MelonLoader: $($d.Name)"; Merge-Folder $d.FullName (Join-Path $GameDir $d.Name); $count++ }
        } else {
            $dst = Join-Path $GameDir "Mods"
            Write-Host "    MelonLoader: $($dlls.Count) DLL(s) -> Mods"
            if (!$DryRun) { if (!(Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }; $dlls | Copy-Item -Destination $dst -Force }
            $count++
        }
    }
    return $count
}

if (!$DryRun) {
    Get-ChildItem -Path $env:TEMP -Directory -Filter "bl_scan_*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    if (!(Test-Path $ModsTarget)) { New-Item -ItemType Directory -Path $ModsTarget -Force | Out-Null }
}

$state = @{}
if (Test-Path $stateFile) {
    try { (Get-Content $stateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } } catch { $state = @{} }
}

$ok = 0; $skipped = 0; $failed = 0; $notDone = 0

# ---------- 1) ZIPs ----------
$zips = @(Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue | Where-Object { !(Test-Excluded $_.DirectoryName) } | Sort-Object LastWriteTime)
Write-Host "== $($zips.Count) ZIP file(s) ==" -ForegroundColor Cyan
for ($zi = 0; $zi -lt $zips.Count; $zi++) {
    $zip = $zips[$zi]
    if ($script:abort) { $notDone++; continue }
    $key = "$($zip.Length)|$($zip.LastWriteTimeUtc.Ticks)"
    $skey = "zip:" + $zip.FullName
    if (!$Force -and $state[$skey] -eq $key) { Write-Host "[SKIP] $($zip.Name) (already installed)" -ForegroundColor DarkGray; $skipped++; continue }

    $targets = @($env:TEMP, $ModsTarget)
    $need = 0L
    try { $need = Get-ZipSize $zip.FullName } catch { $need = $zip.Length * 2 }
    $spaceMsg = Test-Space $need $targets
    if ($spaceMsg) { Stop-NoSpace "Before $($zip.Name): $spaceMsg"; $notDone++; continue }

    Write-Host "[....] $($zip.Name)" -ForegroundColor Cyan
    $tmp = Join-Path $env:TEMP ("bl_scan_" + [guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -LiteralPath $zip.FullName -DestinationPath $tmp -Force
        $n = Install-FromRoot $tmp $zip.BaseName
        if ($n -gt 0) {
            Write-Host "[ OK ] $($zip.Name)" -ForegroundColor Green
            if (!$DryRun) { $state[$skey] = $key; Save-State }
            $ok++
        } else {
            Write-Host "[FAIL] $($zip.Name): nothing installed (neither pallet.json nor a usable DLL)." -ForegroundColor Yellow
            $failed++
        }
    }
    catch {
        $err = $_
        Remove-Partial
        if (Test-DiskFullError $err $targets) { Stop-NoSpace "The disk ran full while processing $($zip.Name)."; $notDone++ }
        else { Write-Host "[FAIL] $($zip.Name): $($err.Exception.Message)" -ForegroundColor Red; $failed++ }
    }
    finally { if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
}

# ---------- 2) Already unpacked mods ----------
Write-Host "`n== Unpacked mods ==" -ForegroundColor Cyan
$palletDirs = @(Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Filter *pallet.json -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(^|\.)pallet\.json$' -and !(Test-Excluded $_.DirectoryName) } | ForEach-Object { $_.Directory } | Sort-Object FullName -Unique)
foreach ($d in $palletDirs) {
    if ($script:abort) { $notDone++; continue }
    $files = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
    $sum = ($files | Measure-Object Length -Sum).Sum
    $max = ($files | Measure-Object LastWriteTimeUtc -Maximum).Maximum.Ticks
    $key = "$sum|$max"
    $skey = "dir:" + $d.FullName
    if (!$Force -and $state[$skey] -eq $key) { Write-Host "[SKIP] $($d.Name) (already installed)" -ForegroundColor DarkGray; $skipped++; continue }

    $targets = @($ModsTarget)
    $spaceMsg = Test-Space ([long]$sum) $targets
    if ($spaceMsg) { Stop-NoSpace "Before $($d.Name): $spaceMsg"; $notDone++; continue }

    Write-Host "[....] $($d.FullName)" -ForegroundColor Cyan
    try {
        $p = Get-ChildItem -LiteralPath $d.FullName -Filter *pallet.json -File | Where-Object { $_.Name -match '(^|\.)pallet\.json$' } | Select-Object -First 1
        $name = $d.Name
        if ($d.FullName.TrimEnd('\') -eq $SourceDir) { $name = $p.Name -replace '\.?pallet\.json$',''; if (!$name) { $name = Split-Path $SourceDir -Leaf } }
        $dest = Join-Path $ModsTarget $name
        Write-Host "    Marrow mod: $name"
        if ((Test-Path $dest) -and !$DryRun) { Remove-Item -LiteralPath $dest -Recurse -Force }
        $script:lastDest = $dest
        Merge-Folder $d.FullName $dest
        $script:lastDest = $null
        if (!$DryRun) { $state[$skey] = $key; Save-State }
        Write-Host "[ OK ] $name" -ForegroundColor Green
        $ok++
    }
    catch {
        $err = $_
        Remove-Partial
        if (Test-DiskFullError $err $targets) { Stop-NoSpace "The disk ran full while processing $($d.Name)."; $notDone++ }
        else { Write-Host "[FAIL] $($d.FullName): $($err.Exception.Message)" -ForegroundColor Red; $failed++ }
    }
}
if ($palletDirs.Count -eq 0) { Write-Host "No unpacked Marrow mods found." -ForegroundColor DarkGray }

# ---------- 3) Loose DLLs (MelonLoader mods) ----------
Write-Host "`n== Loose DLL files (MelonLoader) ==" -ForegroundColor Cyan
$palletRoots = @($palletDirs | ForEach-Object { $_.FullName.TrimEnd('\') + '\' })
$looseDlls = @(Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Filter *.dll -ErrorAction SilentlyContinue | Where-Object {
    $dn = $_.DirectoryName + '\'
    !(Test-Excluded $_.DirectoryName) -and -not ($palletRoots | Where-Object { $dn.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })
})
if ($looseDlls.Count -eq 0) { Write-Host "No loose DLLs found." -ForegroundColor DarkGray }
elseif (!$GameDir) { Write-Host "$($looseDlls.Count) DLL(s) found, but game folder not found - skipped." -ForegroundColor Yellow }
else {
    if (!(Test-Path (Join-Path $GameDir "MelonLoader"))) { Write-Host "WARNING: MelonLoader is not installed in the game folder." -ForegroundColor Yellow }
    $dstMods = Join-Path $GameDir "Mods"
    foreach ($f in $looseDlls) {
        if ($script:abort) { $notDone++; continue }
        $key = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        $skey = "dll:" + $f.FullName
        if (!$Force -and $state[$skey] -eq $key) { Write-Host "[SKIP] $($f.Name) (already installed)" -ForegroundColor DarkGray; $skipped++; continue }
        $spaceMsg = Test-Space ([long]$f.Length) @($dstMods)
        if ($spaceMsg) { Stop-NoSpace "Before $($f.Name): $spaceMsg"; $notDone++; continue }
        try {
            Write-Host "[....] $($f.Name) -> $dstMods"
            if (!$DryRun) {
                if (!(Test-Path $dstMods)) { New-Item -ItemType Directory -Path $dstMods -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination $dstMods -Force
                $state[$skey] = $key; Save-State
            }
            Write-Host "[ OK ] $($f.Name)" -ForegroundColor Green
            $ok++
        }
        catch {
            $err = $_
            if (Test-DiskFullError $err @($dstMods)) { Stop-NoSpace "The disk ran full while copying $($f.Name)."; $notDone++ }
            else { Write-Host "[FAIL] $($f.Name): $($err.Exception.Message)" -ForegroundColor Red; $failed++ }
        }
    }
}

if (!$DryRun) { Save-State }
Write-Host ""
if ($script:abort) {
    Write-Host "STOPPED due to low disk space: $ok installed, $skipped skipped, $failed failed, $notDone still pending." -ForegroundColor Red
    Write-Host $script:abortMsg -ForegroundColor Red
    Write-Host "Progress has been saved ($stateFile)." -ForegroundColor Yellow
    Write-Host "Free up space or enlarge the drive, then simply run this file again -" -ForegroundColor Yellow
    Write-Host "already installed mods are skipped and it continues with the next pending mod." -ForegroundColor Yellow
} else {
    Write-Host "Done: $ok installed, $skipped skipped, $failed failed." -ForegroundColor Cyan
}
Read-Host "Press Enter to exit"
