; Gnosis one-download Windows installer (ONLINE bootstrap).
; Builds Gnosis-Setup.exe with Inno Setup 6.
; No preinstalled Python, Vim, Git, Node.js or developer tools required.
; Uses Windows' built-in PowerShell 5.1, downloads the pinned Gnosis
; installer, then delegates to the tested WSL2/Ubuntu/WezTerm setup.
;
; Important: the installation needs internet access and may need UAC,
; a Windows restart and one initial Ubuntu username/password setup.
; The EXE is NOT an offline bundle of all runtimes.

#define GnosisVersion "1.0"
[Setup]
AppId={{B289B97C-066E-4CB4-875D-9D98CA6C831D}
AppName=Gnosis Windows Setup
AppVersion={#GnosisVersion}
AppPublisher=Gnosis
AppPublisherURL=https://github.com/Yurii7812/gnosis
DefaultDirName={localappdata}\Gnosis\Bootstrap
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename=Gnosis-Setup
SetupLogging=yes
AllowNoIcons=yes
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "bootstrap.ps1"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\bootstrap.ps1"""; WorkingDir: "{tmp}"; StatusMsg: "Downloading and setting up Gnosis. Follow the instructions in the terminal window."; Flags: waituntilterminated
