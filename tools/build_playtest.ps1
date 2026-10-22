$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$godotPath = 'D:\Godot_v4.7.2-stable_win64.exe'
$templatePath = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $templatePath)) { throw 'Install matching verified Godot export templates first.' }
$buildFolder = Join-Path $projectRoot 'builds\playtest-windows'
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null
$exportLog = Join-Path $projectRoot 'artifacts\playtest-export.log'
$taskProcess = Start-Process -FilePath $godotPath -ArgumentList '--headless','--path',$projectRoot,'--export-release','"Windows Playtest"',(Join-Path $buildFolder 'Zombied.exe'),'--log-file',$exportLog -WindowStyle Hidden -Wait -PassThru
if ($taskProcess.ExitCode -ne 0) { throw "Export failed with exit code $($taskProcess.ExitCode); inspect $exportLog" }
foreach ($name in @('Zombied.exe','Zombied.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $buildFolder $name))) { throw "Missing package file: $name" }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PLAYTEST_README.txt') -Destination (Join-Path $buildFolder 'README.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PLAYTEST_FEEDBACK.txt') -Destination (Join-Path $buildFolder 'FEEDBACK.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\EXTERNAL_PLAYTEST.md') -Destination $buildFolder
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\Performance Test.cmd') -Destination $buildFolder
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\Weapon Lab.cmd') -Destination $buildFolder
foreach ($licenseFile in @('GODOT_LICENSE.txt','GODOT_COPYRIGHT.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "tools\godot-export-templates\$licenseFile") -Destination $buildFolder
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $buildFolder 'FONT_OFL.txt')
}
& 'C:\Users\13476\AppData\Local\Programs\Python\Python311\python.exe' (Join-Path $PSScriptRoot 'write_build_manifest.py') (Join-Path $buildFolder 'source-manifest.json')
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $buildFolder 'Zombied.exe'),(Join-Path $buildFolder 'Zombied.pck') | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildFolder 'package-hashes.json') -Encoding utf8
Write-Output "PLAYTEST_EXPORTED $buildFolder"
