; Instalador do Horus (Inno Setup 6). Gerado por build_windows.ps1:
;   ISCC.exe /DAppVersion=0.1.0 packaging\horus.iss

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{6E1C7B0A-3F7E-4E0B-9C1D-48A2F6B7D501}
AppName=Horus
AppVersion={#AppVersion}
AppPublisher=Horus
DefaultDirName={autopf}\Horus
DefaultGroupName=Horus
UninstallDisplayIcon={app}\Horus.exe
OutputDir=..\dist
OutputBaseFilename=Horus-{#AppVersion}-setup
SetupIconFile=build\horus.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Instalação por usuário, sem pedir administrador: a gravação de CD/DVD
; pelo IMAPI2 e a cópia para pendrive não exigem elevação.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\dist\Horus\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Horus"; Filename: "{app}\Horus.exe"
Name: "{group}\Desinstalar o Horus"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Horus"; Filename: "{app}\Horus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Horus.exe"; Description: "{cm:LaunchProgram,Horus}"; Flags: nowait postinstall skipifsilent
