; Inno Setup 6 script for the Windows app: a per-user installer, no admin
; rights and no UAC prompt. Built by .github/workflows/release.yml and
; build.yml:
;
;   ISCC.exe /DAppVersion=0.2.0 /DSourceDir=C:\path\to\Release /Odist installer\windows\setup.iss
;
; SourceDir is the Flutter release folder (exe, dlls, data\) after
; tool/bundle_browser.py added the browser helper and the extension. The
; output is dist\windows-x64-setup.exe; the file name is generic on purpose,
; like the other release files.
;
; The app runs this setup itself for in-app updates (WindowsSetupInstaller in
; lib/services/update/windows_setup_installer.dart), silently and with two
; options of our own:
;
;   /relaunch=1       start the app again when setup ends, whether the update
;                     worked (new version) or not (Inno Setup puts the old
;                     files back, so the old version starts)
;   /result=<file>    write "started" into <file> as soon as setup runs (the
;                     app waits for it before it exits), then "success" or
;                     "aborted" at the end; the app reads that at its next
;                     start (WindowsUpdateInstaller.readHelperResult)
;
; Uninstalling removes the program files, the shortcuts and the browser
; helper's registration. It never deletes the vault: that lives in the user's
; app data folder, not in the install folder.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "Khazna"
#define AppExe "hisn.exe"

[Setup]
; Never change AppId: Windows and Inno Setup use it to find the installed
; copy, so a new id would install a second copy next to the first.
AppId={{41550A45-C370-474B-9CFB-D10618916CEA}
AppName={#AppName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
; Per user: %LOCALAPPDATA%\Programs\Khazna. The app can update itself there
; without asking for admin rights.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The app and the browser helper (started by the browser) may still hold their
; files when an update starts: close them, and do not start them again here
; (the [Code] section below starts the app after a silent update).
CloseApplications=force
RestartApplications=no
SetupMutex=KhaznaSetup-41550A45-C370-474B-9CFB-D10618916CEA
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir=..\..\dist
OutputBaseFilename=windows-x64-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Arabic is not part of every Inno Setup install; use it when it is there.
#if FileExists(CompilerPath + "Languages\Arabic.isl")
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; No [InstallDelete]: files an update no longer ships stay behind until
; uninstall. Deleting folders up front would not be undone when the update
; fails, and the old version that starts again would miss them.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
; The app registers the browser helper under these keys when the user turns the
; browser extension on (kNativeHostKeys in windows/runner/platform_channel.cpp).
; Setup never creates them; uninstalling deletes them.
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\app.khazna.bridge"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\app.khazna.bridge"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\app.khazna.bridge"; Flags: uninsdeletekey dontcreatekey

[UninstallDelete]
; Only the browser helper's endpoint file and manifest (bridgeDirectory in
; browser/bridge/lib/bridge_protocol.dart). The vault is elsewhere and stays.
Type: filesandordirs; Name: "{localappdata}\Hisn\Browser"

[Code]
var
  // True once every file is in place. Inno Setup puts the replaced files
  // back when setup fails or is cancelled before this point.
  Succeeded: Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    Succeeded := True;
end;

// Runs first. Tells the app that setup runs: from here on DeinitializeSetup
// always writes the outcome and (for the app's updates) starts the app.
function InitializeSetup(): Boolean;
var
  ResultFile: String;
begin
  ResultFile := ExpandConstant('{param:result|}');
  if ResultFile <> '' then
  begin
    try
      if not SaveStringToFile(ResultFile, 'started', False) then
        Log('Could not write the result file.');
    except
      Log('Could not write the result file.');
    end;
  end;
  Result := True;
end;

// Runs last, after success, failure or cancel. Never raises: an error here
// would only hide the real outcome.
procedure DeinitializeSetup();
var
  ResultFile: String;
  Outcome: String;
  AppPath: String;
  ResultCode: Integer;
begin
  ResultFile := ExpandConstant('{param:result|}');
  if ResultFile <> '' then
  begin
    if Succeeded then
      Outcome := 'success'
    else
      Outcome := 'aborted';
    try
      if not SaveStringToFile(ResultFile, Outcome, False) then
        Log('Could not write the result file.');
    except
      Log('Could not write the result file.');
    end;
  end;

  // Only for the app's own silent updates: start the app again, the new
  // version or, after a failure, the old one.
  if (ExpandConstant('{param:relaunch|0}') = '1') and WizardSilent then
  begin
    try
      // The app folder is not known yet when setup failed early, and then
      // ExpandConstant raises.
      AppPath := ExpandConstant('{app}');
      if FileExists(AppPath + '\{#AppExe}') then
      begin
        if not Exec(AppPath + '\{#AppExe}', '', AppPath, SW_SHOWNORMAL,
          ewNoWait, ResultCode) then
          Log('Could not start the app.');
      end;
    except
      Log('Could not start the app.');
    end;
  end;
end;
