#ifndef MyAppVersion
#define MyAppVersion "0.2.1"
#endif
[Setup]
AppId={{3D86EA2B-9D17-47B9-B1C9-084A7A3D2387}
AppName=Dreamlight Companion
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Dreamlight Companion
DefaultGroupName=Dreamlight Companion
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=DreamlightCompanion-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Dreamlight Companion"; Filename: "{app}\dreamlight_companion.exe"
[Run]
Filename: "{app}\dreamlight_companion.exe"; Description: "Open Dreamlight Companion"; Flags: nowait postinstall skipifsilent

