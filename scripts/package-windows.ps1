param([string]$Flutter='flutter',[switch]$SkipBuild)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
 if(-not $SkipBuild){
  & $Flutter build windows --release --no-pub
  if($LASTEXITCODE -ne 0){throw 'Windows build failed'}
 }
 $release=Join-Path $projectRoot 'build\windows\x64\runner\Release'
 if(-not (Test-Path (Join-Path $release 'dreamlight_companion.exe'))){throw 'Windows executable not found'}
 $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
 $vsPath=& $vswhere -latest -products '*' -property installationPath
 $crt=Get-ChildItem (Join-Path $vsPath 'VC\Redist\MSVC') -Directory | Where-Object Name -Match '^\d' | Sort-Object Name -Descending | Select-Object -First 1
 $runtime=Join-Path $crt.FullName 'x64\Microsoft.VC143.CRT'
 Copy-Item (Join-Path $runtime '*.dll') -Destination $release -Force
 New-Item -ItemType Directory -Force dist | Out-Null
 Compress-Archive -Path "$release\*" -DestinationPath dist\DreamlightCompanion-Windows.zip -Force
 $isccCandidates=@("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe","$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")
 $iscc=$isccCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
 if(-not $iscc){throw 'Inno Setup 6 not found'}
 $versionLine=Get-Content pubspec.yaml | Where-Object {$_ -match '^version:'} | Select-Object -First 1
 $appVersion=($versionLine -replace '^version:\s*','').Split('+')[0].Trim()
 & $iscc "/DMyAppVersion=$appVersion" packaging\windows.iss
 if($LASTEXITCODE -ne 0){throw 'Installer failed'}
 Copy-Item build\installer\DreamlightCompanion-Setup.exe dist\ -Force
 Get-ChildItem dist -File | Where-Object Extension -in @('.exe','.zip','.apk') | Get-FileHash -Algorithm SHA256 | Select-Object Hash,@{n='File';e={Split-Path $_.Path -Leaf}} | ConvertTo-Json | Set-Content dist\SHA256.json
} finally {Pop-Location}

