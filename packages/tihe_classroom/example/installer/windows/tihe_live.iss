; TIHE Live — Windows setup wizard (Inno Setup 6.5+).
;
; Built by .github/workflows/windows-installer.yml after `flutter build windows`. To build it by
; hand on Windows (see ../../../README.md):
;   iscc /DAppVersion=0.1.0 /DDefaultServer=https://… installer\windows\tihe_live.iss
; Silent install for IT staff: TIHE-Live-Setup.exe /VERYSILENT /server=https://…
; Self-update: the installed app downloads a newer Setup.exe from GitHub releases and runs it
; with /SILENT /update=1 (example/lib/updater.dart); the wizard keeps the last server address
; and starts the app again when done.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef DefaultServer
  #define DefaultServer "http://localhost:3100/v1/live"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif
#define AppName "TIHE Live"
#define AppExe "tihe_live.exe"
; The Persian wizard text is a community translation CI downloads next to this file; without
; it the wizard falls back to English.
#define HaveFarsi FileExists(AddBackslash(SourcePath) + "Farsi.isl")

[Setup]
; Never change AppId: it is how Windows recognises an update of the same app.
AppId={{3C2BFCA6-742B-4854-979B-D13F4AAE5A12}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=TIHE
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
; Per-user install needs no administrator; the wizard offers both.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Windows 10 2004+: the first version that can hide a window from screen capture (ADR-0011).
MinVersion=10.0.19041
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir=Output
OutputBaseFilename=TIHE-Live-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
LanguageDetectionMethod=none
ShowLanguageDialog=no

[Languages]
#if HaveFarsi
Name: "fa"; MessagesFile: "Farsi.isl"
#endif
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
#if HaveFarsi
fa.ServerTitle=آدرس سرور کلاس
fa.ServerDescription=برنامه به کدام سرور وصل شود؟
fa.ServerNote=این آدرس را مؤسسه به شما داده است. اگر نمی‌دانید، همین پیش‌فرض را نگه دارید؛ بعداً در صفحهٔ ورود برنامه هم قابل تغییر است.
fa.ServerLabel=آدرس سرور:
fa.ServerInvalid=آدرس سرور باید با http:// یا https:// شروع شود و فاصله یا نقل‌قول نداشته باشد.
fa.DesktopIcon=میان‌بر روی دسکتاپ
fa.LaunchApp=اجرای {#AppName}
#endif
en.ServerTitle=Class server
en.ServerDescription=Which server should the app connect to?
en.ServerNote=Your institute gives you this address. If unsure, keep the default; you can change it later on the app's sign-in screen.
en.ServerLabel=Server address:
en.ServerInvalid=The server address must start with http:// or https:// and contain no spaces or quotes.
en.DesktopIcon=Desktop shortcut
en.LaunchApp=Start {#AppName}

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"

[Files]
; The whole Flutter bundle, plus the MSVC runtime DLLs CI copies into it, so no separate
; Visual C++ Redistributable install is needed.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent
; After a self-update the app comes back on its own. As the signed-in user, not as the
; administrator an all-users update may have run as.
Filename: "{app}\{#AppExe}"; Flags: nowait runasoriginaluser; Check: IsSelfUpdate

[UninstallDelete]
Type: files; Name: "{app}\tihe_live.json"

[Code]
var
  ServerPage: TInputQueryWizardPage;

function IsSelfUpdate: Boolean;
begin
  Result := ExpandConstant('{param:update|0}') = '1';
end;

function IsValidServer(const Url: String): Boolean;
var
  Lower: String;
begin
  Lower := Lowercase(Url);
  Result := ((Pos('http://', Lower) = 1) or (Pos('https://', Lower) = 1))
    and (Length(Url) > 8)
    and (Pos(' ', Url) = 0) and (Pos('"', Url) = 0) and (Pos('\', Url) = 0);
end;

procedure InitializeWizard;
var
  Server: String;
begin
  ServerPage := CreateInputQueryPage(wpSelectDir,
    CustomMessage('ServerTitle'), CustomMessage('ServerDescription'),
    CustomMessage('ServerNote'));
  ServerPage.Add(CustomMessage('ServerLabel'), False);
  // A command-line /server= wins, then the address from the last install, then the default.
  Server := ExpandConstant('{param:server|}');
  if Server = '' then
    Server := GetPreviousData('ServerUrl', '{#DefaultServer}');
  ServerPage.Values[0] := Server;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'ServerUrl', Trim(ServerPage.Values[0]));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = ServerPage.ID) and not IsValidServer(Trim(ServerPage.Values[0])) then
  begin
    MsgBox(CustomMessage('ServerInvalid'), mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Server: String;
begin
  if CurStep = ssPostInstall then
  begin
    Server := Trim(ServerPage.Values[0]);
    // A silent install skips the page, so check the address here too.
    if not IsValidServer(Server) then
      Server := '{#DefaultServer}';
    // Read by the app at start-up to pre-fill its server field.
    SaveStringToFile(ExpandConstant('{app}\tihe_live.json'),
      '{"liveApiBaseUrl": "' + Server + '"}', False);
  end;
end;
