; IdlePulse installer
; Built with Inno Setup 6.x. See https://jrsoftware.org/isinfo.php
;
; Build via:
;   ISCC installer\IdlePulse.iss
; Or use tools\build-installer.ps1 which publishes the app first.

#define MyAppName        "IdlePulse"
#define MyAppDescription "Idle-triggered shutdown, sleep, hibernate, or lock for Windows."
#define MyAppPublisher   "IdlePulse"
#define MyAppURL         "https://github.com/TheCSir/IdlePulse"
#define MyAppExeName     "IdlePulse.exe"
#define MyAppId          "{{E8A2C7B0-4F1D-4E72-B8E9-2D9F3A1C7B05}"
#define MyAppMutexName   "Global\IdlePulse_SingleInstance_8F3C2A"
#define AutostartValue   "IdlePulse"
#define AutostartRunKey  "Software\Microsoft\Windows\CurrentVersion\Run"

; Read version from the published exe (set by .csproj <Version>)
#define MyAppVersion GetVersionNumbersString("..\publish\IdlePulse.exe")

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableWelcomePage=no
ShowLanguageDialog=no
WizardStyle=modern
Compression=lzma2/ultra
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist
OutputBaseFilename=IdlePulse-Setup-{#MyAppVersion}
SetupIconFile=..\Assets\IdlePulse.ico
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoDescription={#MyAppDescription}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startupentry"; Description: "Run {#MyAppName} when Windows starts"; GroupDescription: "Additional options:"

[Files]
Source: "..\publish\IdlePulse.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Registry]
; Per-user autostart (user-scope; works for both per-user and per-machine installs).
; Removed cleanly on uninstall.
Root: HKCU; Subkey: "{#AutostartRunKey}"; ValueType: string; ValueName: "{#AutostartValue}"; \
    ValueData: """{app}\{#MyAppExeName}"""; Tasks: startupentry; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop a running instance before file deletion.
Filename: "{cmd}"; Parameters: "/c taskkill /im ""{#MyAppExeName}"" /f"; Flags: runhidden; RunOnceId: "KillIdlePulse"

[UninstallDelete]
; Remove the per-user autostart entry even if the user disabled the task at install time
; (in case they enabled it later from inside the app).
Type: dirifempty; Name: "{localappdata}\{#MyAppName}"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // If the app is running, ask Windows to close it before we proceed.
  // CloseApplications=yes above handles this gracefully via the app-shutdown wizard step,
  // but we also force-kill if a stray instance survives (e.g. tray-only with no main window).
  Exec('taskkill.exe', '/im IdlePulse.exe /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
