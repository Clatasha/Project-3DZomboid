param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = $PSScriptRoot
$stateRoot = Join-Path $env:LOCALAPPDATA 'Clatasha/PZ3DSetup'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Hash($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Patch-Json($text) {
    $cfg = $text | ConvertFrom-Json
    if (!$cfg.PSObject.Properties['vmArgs']) { throw 'Launcher JSON has no vmArgs; refusing to change it.' }
    $agents = @($cfg.vmArgs | Where-Object { $_ -match '^-agentlib:zbNative|^-javaagent:.*ZombieBuddy' })
    if ($agents.Count -gt 0 -and ($agents.Count -ne 1 -or $agents[0] -ne '-agentlib:zbNative')) {
        throw 'Custom ZombieBuddy launch configuration detected. Restore or remove it before installing.'
    }
    if ($agents.Count -eq 0) { $cfg.vmArgs = @('-agentlib:zbNative') + @($cfg.vmArgs) }
    $cfg | ConvertTo-Json -Depth 100
}
function Patch-Bat($text) {
    if ($text -match '(?im)^\s*(?:set\s+)?_JAVA_OPTIONS=.*(?:zbNative|ZombieBuddy)') {
        if ($text -match 'ZombieBuddy|zbNative=' -or $text -notmatch '(?im)^\s*SET _JAVA_OPTIONS=.*-agentlib:zbNative(?:\s|$)') { throw 'Custom alternate-launch agent detected; refusing to overwrite it.' }
        return $text
    }
    $matches = [regex]::Matches($text, '(?im)^\s*SET _JAVA_OPTIONS=([^\r\n]*)')
    if ($matches.Count -ne 1) { throw 'Unexpected alternate launcher format; no changes made.' }
    $m = $matches[0]
    $replacement = 'SET _JAVA_OPTIONS=-agentlib:zbNative ' + $m.Groups[1].Value
    $text.Substring(0,$m.Index) + $replacement + $text.Substring($m.Index+$m.Length)
}
function Find-Game {
    $steamRoots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $v = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($v.SteamPath) { $steamRoots += $v.SteamPath }
        if ($v.InstallPath) { $steamRoots += $v.InstallPath }
    }
    if (${env:ProgramFiles(x86)}) { $steamRoots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    foreach ($s in @($steamRoots | Select-Object -Unique)) {
        $libraries = @($s)
        $vdf = Join-Path $s 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s+"([^"]+)"')) { $libraries += $m.Groups[1].Value.Replace('\\','\') }
        }
        foreach ($lib in $libraries) {
            $game = Join-Path $lib 'steamapps/common/ProjectZomboid'
            if (Test-Path -LiteralPath (Join-Path $game 'ProjectZomboid64.json')) { return $game }
        }
    }
    return ''
}
function Check-Closed {
    if (Get-Process -Name ProjectZomboid64,ProjectZomboid32 -ErrorAction SilentlyContinue) { throw 'Close Project Zomboid before installing or restoring.' }
}
function Check-Version($game) {
    $jarPath = Join-Path $game 'projectzomboid.jar'
    if (!(Test-Path -LiteralPath $jarPath)) { throw 'projectzomboid.jar was not found in this folder.' }
    $zip = [IO.Compression.ZipFile]::OpenRead($jarPath)
    $versions = @()
    try {
        foreach ($className in @('zombie/core/Core.class','zombie/GameVersion.class')) {
            $entry = $zip.GetEntry($className)
            if (!$entry) { continue }
            $stream = $entry.Open(); $mem = New-Object IO.MemoryStream
            try { $stream.CopyTo($mem); $data = [Text.Encoding]::ASCII.GetString($mem.ToArray()) } finally { $stream.Dispose(); $mem.Dispose() }
            foreach ($m in [regex]::Matches($data,'(?<![0-9])42\.[0-9]+(?:\.[0-9]+)?(?![0-9])')) { $versions += $m.Value }
        }
    } finally { $zip.Dispose() }
    $versions = @($versions | Select-Object -Unique)
    if ($versions.Count -eq 1 -and $versions[0] -match '^42\.21(?:\.|$)') { return 'Detected 42.21' }
    # Bytecode may build the version from integer fields instead of storing it as text.
    # Strings may also refer to older compatibility versions; they are not definitive.
    if (!$versionCheck.Checked) {
        throw 'Could not detect the build automatically. Check the version shown in the game main menu, then tick the Build 42.21 confirmation and install again.'
    }
    return 'Build 42.21 confirmed by user; automatic detection inconclusive'
}
function Install-Setup($game) {
    Check-Closed
    if (!(Test-Path -LiteralPath (Join-Path $game 'ProjectZomboid64.exe'))) { throw 'Select the actual ProjectZomboid game folder.' }
    $versionStatus = Check-Version $game
    $stateFile = Join-Path $stateRoot 'installation.json'
    if (Test-Path -LiteralPath $stateFile) { throw 'An installation is already tracked. Use Restore first before reinstalling.' }
    $jsonPath = Join-Path $game 'ProjectZomboid64.json'
    $newJson = Patch-Json ([IO.File]::ReadAllText($jsonPath))
    $batPath = Join-Path $game 'ProjectZomboid64.bat'
    $newBat = $null
    if (Test-Path -LiteralPath $batPath) { $newBat = Patch-Bat ([IO.File]::ReadAllText($batPath)) }
    $payloadIndex = Get-Content -LiteralPath (Join-Path $root 'payload-hashes.json') -Raw | ConvertFrom-Json
    foreach ($item in $payloadIndex) {
        $src = Join-Path $root $item.path
        if (!(Test-Path -LiteralPath $src) -or (Hash $src) -ne $item.hash) { throw "Package file failed verification: $($item.path)" }
    }
    $mods = Join-Path $env:USERPROFILE 'Zomboid/mods'
    $workshop = Join-Path (Split-Path (Split-Path $game)) 'workshop/content/108600'
    $modCopies = @()
    foreach ($pair in @(@('3619862853','ZombieBuddy'),@('3809306528','Viewpoint'))) {
        $workshopMod = Join-Path $workshop ($pair[0] + '/mods/' + $pair[1])
        if (Test-Path -LiteralPath $workshopMod) { continue }
        $dest = Join-Path $mods $pair[1]
        if (Test-Path -LiteralPath $dest) { throw "Existing local mod found: $dest. Move it aside before installation." }
        $modCopies += $pair[1]
    }
    New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
    $backupRoot = Join-Path $stateRoot ('backup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
    $records = New-Object Collections.Generic.List[object]
    function Track($target) {
        $exists = Test-Path -LiteralPath $target
        $backup = Join-Path $backupRoot ($records.Count.ToString() + '.bak')
        if ($exists) { Copy-Item -LiteralPath $target -Destination $backup }
        $records.Add([pscustomobject]@{target=$target; existed=$exists; backup=$backup; installedHash=$null})
    }
    try {
        foreach ($name in @('ZombieBuddy.jar','zbNative.dll')) {
            $target = Join-Path $game $name; Track $target
            Copy-Item -LiteralPath (Join-Path $root "payload/$name") -Destination $target -Force
            $records[$records.Count-1].installedHash = Hash $target
        }
        Track $jsonPath; Write-Text $jsonPath $newJson
        $records[$records.Count-1].installedHash = Hash $jsonPath
        if ($null -ne $newBat) { Track $batPath; Write-Text $batPath $newBat; $records[$records.Count-1].installedHash = Hash $batPath }
        foreach ($name in $modCopies) {
            $srcRoot = Join-Path $root "payload/$name"
            foreach ($file in Get-ChildItem -LiteralPath $srcRoot -File -Recurse) {
                $relative = $file.FullName.Substring($srcRoot.Length).TrimStart('\','/')
                $target = Join-Path (Join-Path $mods $name) $relative
                Track $target
                New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
                Copy-Item -LiteralPath $file.FullName -Destination $target
                $records[$records.Count-1].installedHash = Hash $target
            }
        }
        $state = [pscustomobject]@{game=$game; versionStatus=$versionStatus; records=@($records.ToArray()); createdMods=$modCopies; backupRoot=$backupRoot}
        Write-Text $stateFile ($state | ConvertTo-Json -Depth 10)
    } catch {
        $original = $_
        $rollbackErrors = @()
        foreach ($r in @($records.ToArray()) | Sort-Object target -Descending) {
            try { if ($r.existed) { Copy-Item -LiteralPath $r.backup -Destination $r.target -Force } elseif (Test-Path -LiteralPath $r.target) { Remove-Item -LiteralPath $r.target -Force } } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) {
            Write-Text $stateFile ([pscustomobject]@{game=$game;records=@($records.ToArray());createdMods=$modCopies;backupRoot=$backupRoot} | ConvertTo-Json -Depth 10)
            throw "Installation failed; rollback needs attention. Backups: $backupRoot. $($rollbackErrors -join '; ')"
        }
        throw $original
    }
}
function Restore-Setup {
    Check-Closed
    $stateFile = Join-Path $stateRoot 'installation.json'
    if (!(Test-Path -LiteralPath $stateFile)) { throw 'No installation by this tool is tracked.' }
    $s = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    foreach ($r in $s.records) {
        if ((Test-Path -LiteralPath $r.target) -and $r.installedHash -and (Hash $r.target) -ne $r.installedHash) {
            throw "File changed since installation: $($r.target). Restore stopped to preserve that change. Backups: $($s.backupRoot)"
        }
        if ($r.existed -and !(Test-Path -LiteralPath $r.backup)) { throw "Missing backup: $($r.backup)" }
    }
    foreach ($r in $s.records) {
        if ($r.existed) { Copy-Item -LiteralPath $r.backup -Destination $r.target -Force }
        elseif (Test-Path -LiteralPath $r.target) { Remove-Item -LiteralPath $r.target -Force }
    }
    Remove-Item -LiteralPath $stateFile
}
if ($SelfTest) {
    $sample = '{"vmArgs":["-Xmx4096m"],"custom":{"keep":true}}'
    $first = Patch-Json $sample
    $second = Patch-Json $first
    $cfg = $second | ConvertFrom-Json
    if (@($cfg.vmArgs | Where-Object { $_ -eq '-agentlib:zbNative' }).Count -ne 1 -or !$cfg.custom.keep) { throw 'JSON test failed' }
    $bat = "@echo off`r`nSET _JAVA_OPTIONS=-Xmx4096m`r`njava.exe`r`n"
    $patched = Patch-Bat $bat
    if ((Patch-Bat $patched) -ne $patched -or $patched -notmatch '-Xmx4096m') { throw 'BAT test failed' }
    $blocked=$false
    try { Patch-Json '{"vmArgs":["-agentlib:zbNative=policy=allow-all"]}' | Out-Null } catch { $blocked=$true }
    if (!$blocked) { throw 'Custom-agent preservation test failed' }
    $blocked=$false
    try { Patch-Bat 'no known launcher format' | Out-Null } catch { $blocked=$true }
    if (!$blocked) { throw 'Unknown-BAT preservation test failed' }
    $testDir=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $testDir | Out-Null
    try {
        $z=[IO.Compression.ZipFile]::Open((Join-Path $testDir 'projectzomboid.jar'),[IO.Compression.ZipArchiveMode]::Create)
        try { $e=$z.CreateEntry('zombie/core/Core.class'); $w=New-Object IO.StreamWriter($e.Open()); $w.Write('numeric fields, no version string'); $w.Dispose() } finally { $z.Dispose() }
        $versionCheck=[pscustomobject]@{Checked=$false}
        $blocked=$false
        try { Check-Version $testDir | Out-Null } catch { $blocked=$true }
        if (!$blocked) { throw 'Unconfirmed build should stop' }
        $versionCheck.Checked=$true
        if ((Check-Version $testDir) -notmatch 'confirmed by user') { throw 'Version fallback test failed' }
    } finally { Remove-Item -LiteralPath $testDir -Recurse -Force }
    'Self-tests passed'; exit
}
$form = New-Object Windows.Forms.Form
$form.Text = 'Clatasha | Project Zomboid 3D Setup v0.1.1'
$form.Size = New-Object Drawing.Size(730,540)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(22,27,35)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
function Label($text,$x,$y,$w,$h) { $l=New-Object Windows.Forms.Label; $l.Text=$text; $l.SetBounds($x,$y,$w,$h); $form.Controls.Add($l); return $l }
$null = Label 'PROJECT ZOMBOID IN 3D' 25 20 650 35
$null = Label 'Project Viewpoint + ZombieBuddy | Windows | Build 42.21 only' 25 60 650 30
$null = Label 'Game folder' 25 105 650 25
$pathBox=New-Object Windows.Forms.TextBox; $pathBox.SetBounds(25,135,550,28); $pathBox.Text=Find-Game; $form.Controls.Add($pathBox)
function Button($text,$x,$y,$w,$action) {
    $b=New-Object Windows.Forms.Button; $b.Text=$text; $b.SetBounds($x,$y,$w,38)
    $b.BackColor=[Drawing.Color]::FromArgb(45,72,100); $b.FlatStyle='Flat'
    $b.Add_Click($action); $form.Controls.Add($b); return $b
}
$null = Button 'Browse' 585 130 100 {
    $d=New-Object Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq 'OK') { $pathBox.Text=$d.SelectedPath }; $d.Dispose()
}
$null = Label 'Installs the loader and patch, and configures Normal and Alternate Launch. Existing files are backed up. Your saves and Java approvals are preserved.' 25 180 660 55
$launchCheck=New-Object Windows.Forms.CheckBox; $launchCheck.Text='I removed existing ZombieBuddy launch arguments, if any'; $launchCheck.SetBounds(25,230,660,22); $form.Controls.Add($launchCheck)
$versionCheck=New-Object Windows.Forms.CheckBox; $versionCheck.Text='I checked the game main menu: the version is Build 42.21'; $versionCheck.SetBounds(25,250,660,22); $form.Controls.Add($versionCheck)
$status=Label 'Ready. Close the game before installing. Select your game folder; Steam is optional.' 25 365 660 120
$install = Button 'Install 3D Setup' 25 283 205 {
    $install.Enabled=$false; $form.UseWaitCursor=$true
    try {
        $status.Text='Checking files and installing...'; $form.Refresh()
        if (!$launchCheck.Checked) { throw 'Confirm that any previous ZombieBuddy launch arguments were removed before installing.' }; Install-Setup ($pathBox.Text.Trim())
        $status.Text="Installed. Launch the game, enable ZombieBuddy and Viewpoint in Mods, and approve Viewpoint in the Java approval window. Start a new test save, then press O. Existing saves may need their own mod selection."
    } catch { $status.Text=$_.Exception.Message; [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Setup stopped') | Out-Null }
    finally { $install.Enabled=$true; $form.UseWaitCursor=$false }
}
$null = Button 'Restore Previous Files' 245 283 220 {
    try { Restore-Setup; $status.Text='Previous files restored. Saves and approvals were preserved. Empty mod folders can remain.' }
    catch { $status.Text=$_.Exception.Message; [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Restore stopped') | Out-Null }
}
$null = Button 'Launch Game' 480 283 205 { try { $g=$pathBox.Text.Trim(); $exe=Join-Path $g 'ProjectZomboid64.exe'; if (!(Test-Path -LiteralPath $exe)) { throw 'Select the game folder first.' }; Start-Process -FilePath $exe -WorkingDirectory $g } catch { $status.Text=$_.Exception.Message } }
$null = Label 'Optional model pack is not bundled. Subscribe to Workshop item 3810302175 to add it.' 25 328 660 25
[Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
