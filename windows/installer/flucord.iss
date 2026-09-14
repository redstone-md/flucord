; The Windows installer, compiled by Inno Setup 6 (ISCC.exe).
;
; Wraps the complete runtime directory a Flutter build produces, which is what
; the app needs to run: the runner, the engine, every plugin DLL, the native
; media modules and the noise model. Per-user by default (no elevation, into
; %LOCALAPPDATA%\Programs), with a switch to all-users on the first page.
;
; Compile:
;   ISCC.exe /DAppVersion=0.0.8 /DOutputName=flucord-windows-x64-setup-v0.0.8 windows\installer\flucord.iss
; Silent install, which is what an updater runs:
;   flucord-windows-x64-setup-v0.0.8.exe /VERYSILENT /NORESTART

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\distribution"
#endif
#ifndef OutputName
  #define OutputName "flucord-windows-x64-setup"
#endif

[Setup]
; Fixed for the life of the product: an install with the same id is upgraded
; in place, and Add/Remove Programs lists one Flucord.
AppId={{7D0E5B1C-3A64-4F2B-9C8E-5F1A2B3C4D5E}
AppName=Flucord
AppVersion={#AppVersion}
AppVerName=Flucord {#AppVersion}
AppPublisher=Redstone
AppPublisherURL=https://github.com/redstone-md/flucord
AppSupportURL=https://github.com/redstone-md/flucord/issues
AppUpdatesURL=https://github.com/redstone-md/flucord/releases
DefaultDirName={autopf}\Flucord
DefaultGroupName=Flucord
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\flucord.exe
UninstallDisplayName=Flucord
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running client holds its DLLs; the installer asks it to close rather
; than failing on a locked file.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Flucord"; Filename: "{app}\flucord.exe"
Name: "{group}\Uninstall Flucord"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Flucord"; Filename: "{app}\flucord.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\flucord.exe"; Description: "{cm:LaunchProgram,Flucord}"; Flags: nowait postinstall skipifsilent
