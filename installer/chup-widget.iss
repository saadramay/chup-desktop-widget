; Chup Widget installer. Built by .github/workflows/release.yml:
;   iscc /DAppVersion=1.2.0 /DSourceDir=<Release folder> installer\chup-widget.iss
;
; Per-user and without admin rights, into a fixed folder. The in-app updater
; overwrites that folder in place, so it must stay user-writable, and the
; startup entry (written by the app) keeps pointing at the same exe.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: it is how Windows matches upgrades to this install.
AppId={{8F3C2A9E-6B1D-4E7A-9C55-2D7E1B0A4F61}
AppName=Chup Widget
AppVersion={#AppVersion}
AppVerName=Chup Widget {#AppVersion}
AppPublisher=Chup
DefaultDirName={localappdata}\Programs\Chup Widget
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=chup-widget-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\chup_widget.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Close a running widget before replacing its files.
CloseApplications=force
RestartApplications=no

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Chup Widget"; Filename: "{app}\chup_widget.exe"

[Registry]
; The app registers itself to start with Windows at sign-in; uninstall removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "ChupWidget"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\chup_widget.exe"; Description: "Start Chup Widget"; Flags: nowait postinstall
