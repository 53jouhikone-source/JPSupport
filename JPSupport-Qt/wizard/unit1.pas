unit unit1;

// 010: 公開前提のチェックで発覚した、開発者個人のディレクトリ(~/Projects/...)への
//      ハードコード参照を削除。実行ファイルからの相対パス(patches/build_jpsupport_qt.sh)を
//      優先的に探すようにした(一般ユーザーの環境には存在しないパスへの無駄な
//      チェックを無くし、個人の作業環境がコードに残る問題も解消)
//      (009のクリーンビルド廃止、008の格上げ廃止、007・006・005・004・003・002・001の対応を維持)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Process, StrUtils, LazFileUtils, FileUtil, BaseUnix;

type

  TOpMode = (omNone, omInstallAndBuild, omBuildOnly);

  { TForm1 }

  TForm1 = class(TForm)
    ButtonMainAction: TButton;
    ButtonLaunchLazarus: TButton;
    ButtonCheckVersions: TButton;
    Btn_Exit: TButton;
    CheckBoxAdvanced: TCheckBox;
    EditVersion: TEdit;
    GroupBoxAdvanced: TGroupBox;
    LabelHeaderBuild: TLabel;
    LabelVersion: TLabel;
    LabelDefault: TLabel;
    ListBoxVersions: TListBox;
    MemoTop: TMemo;
    MemoBottom: TMemo;
    RadioGroupTarget: TRadioGroup;
    TimerPoll: TTimer;
    procedure Btn_ExitClick(Sender: TObject);
    procedure ButtonCheckVersionsClick(Sender: TObject);
    procedure ButtonLaunchLazarusClick(Sender: TObject);
    procedure ButtonMainActionClick(Sender: TObject);
    procedure CheckBoxAdvancedChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ListBoxVersionsClick(Sender: TObject);
    procedure TimerPollTimer(Sender: TObject);
    procedure RadioGroupTargetSelectionChanged(Sender: TObject);
  private
    FProcess: TProcess;
    FScriptPath: string;
    FDefaultVersion: string;
    FEffectiveVersion: string;
    FPending: string;
    FLastOutputTick: QWord;
    FLastCheckpointTick: QWord;
    FLastStepLine: string;
    FStalled: Boolean;
    FBuildPreparePhase: Boolean;
    FMode: TOpMode;
    procedure AppendBottom(const ALine: string);
    procedure AppendTop(const ALine: string);
    procedure ShowAndLogError(const AMsg: string);
    procedure HandleLine(const ALine: string);
    function DetectDefaultVersion: string;
    function RunSudoCommand(const AParameters: array of string): Boolean;
    function InstallBuiltQtPas(const Target: string): Boolean;
    procedure SetControlsEnabled(AEnabled: Boolean);
    procedure StartInstallAndBuild;
    procedure StartBuildOnly(AContinueAfterInstall: Boolean);
    procedure StopPolling;
    function IsBuiltBinaryExists: Boolean;
    procedure UpdateButtonState;
    procedure UpdateDefaultVersionLabel;
    function GetCurrentTargetName: string;
    function GetTargetBuildDirName: string;
    function GetFreeDiskSpaceBytes(const APath: string): Int64;
  public
  end;

var
  Form1: TForm1;

implementation

const
  cRepoURL = 'https://gitlab.com/freepascal.org/lazarus/lazarus.git';

  { ビルド1つあたり実測約1.7GB。一時ファイル(git・コンパイル中間ファイル等)の
    余裕を見て、この値を下回ったら警告する。 }
  cMinFreeSpaceBytes: Int64 = 3 * Int64(1024) * 1024 * 1024;

  cAptPackages: array[0..15] of string = (
    'build-essential', 'gdb', 'git', 'python3', 'fpc', 'fpc-source',
    'qtbase5-dev', 'qt5-qmake', 'qtchooser', 'libqt5x11extras5-dev',
    'libqt5pas-dev', 'libqt5pas1', 'fcitx5', 'fcitx5-frontend-qt5',
    'fcitx5-frontend-gtk3', 'fonts-noto-cjk'
  );

{$R *.lfm}

{ TForm1 }

function TForm1.GetCurrentTargetName: string;
begin
  if RadioGroupTarget.ItemIndex = 0 then
    Result := 'qt5'
  else
    Result := 'qt6';
end;

function TForm1.GetTargetBuildDirName: string;
var
  EffVersion: string;
begin
  EffVersion := Trim(EditVersion.Text);
  if EffVersion = '' then
    EffVersion := FDefaultVersion;
  Result := 'jpsupport-qt-build-' + GetCurrentTargetName;
  if EffVersion <> FDefaultVersion then
    Result := Result + '-alt';
end;

function TForm1.GetFreeDiskSpaceBytes(const APath: string): Int64;
var
  Output: string;
  Lines: TStringList;
begin
  { dfコマンドを使う。FPC標準のDiskFreeはドライブ番号ベースで、
    Linuxの任意パス指定には向かないため。 }
  Result := -1;
  if not RunCommand('/usr/bin/df', ['--output=avail', '-B1', APath], Output) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    if Lines.Count >= 2 then
      Result := StrToInt64Def(Trim(Lines[1]), -1);
  finally
    Lines.Free;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  { スクリプトは、通常このウィザードの実行ファイルと同じ場所に置かれた
    patches/フォルダの中にある想定(リポジトリのwizard/とpatches/を、
    親フォルダの直下に兄弟フォルダとして置いたまま使う構成)。
    見つからない場合は、PATHの通った場所にあることを期待して
    ファイル名のみで実行を試みる。 }
  FScriptPath := ExtractFilePath(Application.ExeName) + 'patches/build_jpsupport_qt.sh';
  if not FileExists(FScriptPath) then
    FScriptPath := 'build_jpsupport_qt.sh';

  FPending := '';
  FMode := omNone;
  FBuildPreparePhase := False;

  FDefaultVersion := DetectDefaultVersion;
  if FDefaultVersion = '' then
    FDefaultVersion := '(取得失敗)';
  UpdateDefaultVersionLabel;
  EditVersion.Text := FDefaultVersion;

  MemoTop.Lines.Clear;
  MemoBottom.Lines.Clear;
  ListBoxVersions.Items.Clear;
  ListBoxVersions.Sorted := True;

  CheckBoxAdvanced.Checked := False;
  CheckBoxAdvancedChange(nil);

  UpdateButtonState;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  StopPolling;
  if Assigned(FProcess) then
    FProcess.Free;
end;

function TForm1.DetectDefaultVersion: string;
var
  Output: string;
  Lines: TStringList;
  i, p: Integer;
begin
  Result := '';
  if not FileExists(FScriptPath) then
    Exit;
  try
    if RunCommand(FScriptPath, ['--show-version'], Output) then
    begin
      Lines := TStringList.Create;
      try
        Lines.Text := Output;
        for i := 0 to Lines.Count - 1 do
        begin
          p := Pos(':', Lines[i]);
          if (p > 0) and (Pos('動作確認済み', Lines[i]) > 0) then
          begin
            Result := Trim(Copy(Lines[i], p + 1, Length(Lines[i])));
            Break;
          end;
        end;
      finally
        Lines.Free;
      end;
    end;
  except
  end;
end;

function TForm1.IsBuiltBinaryExists: Boolean;
var
  LazarusBin: string;
begin
  LazarusBin := ExtractFilePath(Application.ExeName) +
    GetTargetBuildDirName + '/lazarus-src/lazarus';
  Result := FileExists(LazarusBin);
end;

procedure TForm1.UpdateButtonState;
begin
  if FMode <> omNone then
    Exit;

  if IsBuiltBinaryExists then
  begin
    ButtonMainAction.Caption := 'JPSupport版 Lazarus をインストール・再ビルドする';
    ButtonLaunchLazarus.Enabled := True;
  end
  else
  begin
    ButtonMainAction.Caption := 'JPSupport版 Lazarus をインストール・ビルドする';
    ButtonLaunchLazarus.Enabled := False;
  end;
end;

procedure TForm1.UpdateDefaultVersionLabel;
var
  TargetDisplay: string;
begin
  if GetCurrentTargetName = 'qt6' then
    TargetDisplay := 'Qt6'
  else
    TargetDisplay := 'Qt5';
  LabelDefault.Caption := '動作確認済み(デフォルト): ' + FDefaultVersion + ' (' + TargetDisplay + ')';
end;

procedure TForm1.RadioGroupTargetSelectionChanged(Sender: TObject);
begin
  UpdateButtonState;
  UpdateDefaultVersionLabel;
end;

procedure TForm1.ButtonCheckVersionsClick(Sender: TObject);
var
  Output, S, Major: string;
  Lines: TStringList;
  i, p, us1, us2: Integer;
  MajorNum: Integer;
  ok: Boolean;
begin
  ListBoxVersions.Items.Clear;
  ListBoxVersions.Items.Add('取得中...');
  Application.ProcessMessages;

  if not RunCommand('git', ['ls-remote', '--tags', cRepoURL], Output) then
  begin
    ListBoxVersions.Items.Clear;
    ListBoxVersions.Items.Add('(取得に失敗しました。ネットワークを確認してください)');
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    ListBoxVersions.Items.Clear;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Lines[i];
      p := Pos('refs/tags/', S);
      if p = 0 then
        Continue;
      S := Copy(S, p + Length('refs/tags/'), Length(S));
      if Pos('^{}', S) > 0 then
        Continue;
      if Copy(S, 1, Length('lazarus_')) <> 'lazarus_' then
        Continue;
      Major := Copy(S, Length('lazarus_') + 1, Length(S));

      ok := (Major <> '');
      for us1 := 1 to Length(Major) do
        if not (Major[us1] in ['0'..'9', '_']) then
        begin
          ok := False;
          Break;
        end;
      if not ok then
        Continue;

      us2 := Pos('_', Major);
      if us2 = 0 then
        MajorNum := StrToIntDef(Major, -1)
      else
        MajorNum := StrToIntDef(Copy(Major, 1, us2 - 1), -1);

      if MajorNum >= 4 then
        ListBoxVersions.Items.Add(S);
    end;
    if ListBoxVersions.Items.Count = 0 then
      ListBoxVersions.Items.Add('(該当するバージョンが見つかりませんでした)');
  finally
    Lines.Free;
  end;
end;

procedure TForm1.Btn_ExitClick(Sender: TObject);
begin
  close;
end;

procedure TForm1.CheckBoxAdvancedChange(Sender: TObject);
begin
  GroupBoxAdvanced.Visible := CheckBoxAdvanced.Checked;
  ListBoxVersions.Visible := CheckBoxAdvanced.Checked; // 追加：上級者向け設定の表示状態に連動させる

  if CheckBoxAdvanced.Checked then
  begin
    // 展開時：上級者向け設定を表示し、フォームを広げる
    Form1.Height := 650;
    ButtonMainAction.Top := 430;
    ButtonLaunchLazarus.Top := 430;
    MemoTop.Top := 475;
    MemoBottom.Top := 565;
  end
  else
  begin
    // 折りたたみ時：フォームをコンパクトにし、下部要素を上に詰める
    Form1.Height := 420;
    ButtonMainAction.Top := 165;
    ButtonLaunchLazarus.Top := 165;
    MemoTop.Top := 210;
    MemoBottom.Top := 300;

    EditVersion.Text := FDefaultVersion;
    ListBoxVersions.Visible := False;
  end;
end;

procedure TForm1.ListBoxVersionsClick(Sender: TObject);
begin
  if ListBoxVersions.ItemIndex >= 0 then
    EditVersion.Text := ListBoxVersions.Items[ListBoxVersions.ItemIndex];
end;

procedure TForm1.AppendBottom(const ALine: string);
begin
  MemoBottom.Lines.Add(ALine);
  MemoBottom.SelStart := Length(MemoBottom.Lines.Text);
  MemoBottom.SelLength := 0;
end;

procedure TForm1.AppendTop(const ALine: string);
begin
  MemoTop.Lines.Add(ALine);
end;

procedure TForm1.ShowAndLogError(const AMsg: string);
begin
  { エラーダイアログは閉じると内容が追えなくなるため、必ず下段ログにも残す。 }
  AppendBottom('エラー: ' + AMsg);
  ShowMessage(AMsg);
end;

procedure TForm1.SetControlsEnabled(AEnabled: Boolean);
begin
  ButtonMainAction.Enabled := AEnabled;
  ButtonLaunchLazarus.Enabled := AEnabled and IsBuiltBinaryExists;
  CheckBoxAdvanced.Enabled := AEnabled;
  RadioGroupTarget.Enabled := AEnabled;
end;

procedure TForm1.HandleLine(const ALine: string);
var
  IsCheckpoint, IsStepMarker: Boolean;
  ElapsedMs: QWord;
  ElapsedStr: string;
begin
  AppendBottom(ALine);

  if FMode = omInstallAndBuild then
    Exit;

  IsStepMarker := (Pos('=== [', ALine) = 1);

  IsCheckpoint :=
    IsStepMarker or
    (Pos('ERROR', ALine) = 1) or
    (Pos('警告:', ALine) = 1) or
    (Pos('中止しました。', ALine) = 1) or
    (Pos('パッチ適用(ステップ3)をスキップします', ALine) > 0) or
    (Pos('でのビルドが成功しました。', ALine) > 0);

  if IsStepMarker then
  begin
    ElapsedMs := GetTickCount64 - FLastCheckpointTick;
    if (ElapsedMs div 60000) > 0 then
      ElapsedStr := Format('%d分%d秒', [ElapsedMs div 60000, (ElapsedMs div 1000) mod 60])
    else
      ElapsedStr := Format('%d秒', [ElapsedMs div 1000]);
    if FLastStepLine <> '' then
      AppendTop('  ↳ 直前の工程「' + FLastStepLine + '」の所要時間: ' + ElapsedStr);
    AppendTop(ALine);
    FLastStepLine := ALine;
    FLastCheckpointTick := GetTickCount64;
  end
  else if IsCheckpoint then
    AppendTop(ALine);
end;

function TForm1.RunSudoCommand(const AParameters: array of string): Boolean;
var
  Pwd, InputLine: string;
  P: TProcess;
  I: Integer;
  Buf: array[0..255] of Byte;
begin
  Result := False;

  { まず、現在の sudo 認証キャッシュが使えるか確認する。
    パスワードは保存しない。 }
  if RunCommand('/usr/bin/sudo', ['-n', 'true'], InputLine) then
  begin
    P := TProcess.Create(nil);
    try
      P.Executable := '/usr/bin/sudo';
      for I := Low(AParameters) to High(AParameters) do
        P.Parameters.Add(AParameters[I]);
      P.Options := [poUsePipes, poStderrToOutPut];
      P.Execute;
      while P.Running do
      begin
        if P.Output.NumBytesAvailable > 0 then
          P.Output.Read(Buf, SizeOf(Buf))
        else
          Sleep(20);
      end;
      Result := P.ExitStatus = 0;
    finally
      P.Free;
    end;
    Exit;
  end;

  Pwd := PasswordBox('sudo認証',
    '管理者権限が必要です。' + LineEnding +
    'パスワードを入力してください:');
  if Pwd = '' then
    Exit;

  P := TProcess.Create(nil);
  try
    P.Executable := '/usr/bin/sudo';
    P.Parameters.Add('-S');
    for I := Low(AParameters) to High(AParameters) do
      P.Parameters.Add(AParameters[I]);
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    InputLine := Pwd + LineEnding;
    P.Input.Write(InputLine[1], Length(InputLine));

    while P.Running do
    begin
      if P.Output.NumBytesAvailable > 0 then
        P.Output.Read(Buf, SizeOf(Buf))
      else
        Sleep(20);
    end;
    Result := P.ExitStatus = 0;
    if not Result then
      ShowAndLogError('sudoの実行に失敗しました。');
  finally
    { パスワードを保持し続けない。 }
    Pwd := '';
    InputLine := '';
    P.Free;
  end;
end;

function TForm1.InstallBuiltQtPas(const Target: string): Boolean;
var
  QtVer, Output, Line, LibDir, SourceDir, SourceFile: string;
  Lines: TStringList;
  SR: TSearchRec;
  Files: TStringList;
  I, PosArrow: Integer;
begin
  Result := False;
  QtVer := Copy(Target, 3, 1);
  SourceDir := ExtractFilePath(Application.ExeName) +
    GetTargetBuildDirName + '/lazarus-src/lcl/interfaces/qt' +
    QtVer + '/cbindings/';

  if not DirectoryExistsUTF8(SourceDir) then
  begin
    ShowAndLogError('libQt' + QtVer + 'Pas のビルドディレクトリが見つかりません。');
    Exit;
  end;

  LibDir := '';
  if RunCommand('/sbin/ldconfig', ['-p'], Output) then
  begin
    Lines := TStringList.Create;
    try
      Lines.Text := Output;
      for I := 0 to Lines.Count - 1 do
      begin
        Line := Trim(Lines[I]);
        if Pos('libQt' + QtVer + 'Core.so ', Line) = 1 then
        begin
          PosArrow := Pos('=>', Line);
          if PosArrow > 0 then
          begin
            LibDir := ExtractFilePath(Trim(Copy(Line, PosArrow + 2, Length(Line))));
            Break;
          end;
        end;
      end;
    finally
      Lines.Free;
    end;
  end;

  if LibDir = '' then
  begin
    if DirectoryExistsUTF8('/usr/lib/aarch64-linux-gnu') then
      LibDir := '/usr/lib/aarch64-linux-gnu'
    else if DirectoryExistsUTF8('/usr/lib/x86_64-linux-gnu') then
      LibDir := '/usr/lib/x86_64-linux-gnu';
  end;

  if LibDir = '' then
  begin
    ShowAndLogError('Qtライブラリの配置先を自動判定できませんでした。');
    Exit;
  end;

  Files := TStringList.Create;
  try
    if FindFirst(SourceDir + 'libQt' + QtVer + 'Pas.so*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
          Files.Add(SourceDir + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
    begin
      ShowAndLogError('libQt' + QtVer + 'Pas.so* が見つかりません。');
      Exit;
    end;

    AppendBottom('=== libQt' + QtVer + 'Pas をシステムにインストールします ===');
    AppendBottom('配置先: ' + LibDir);

    { cp はシェルを介さず、sudo の引数として直接渡す。 }
    for I := 0 to Files.Count - 1 do
    begin
      SourceFile := Files[I];
      if not RunSudoCommand(['cp', '-f', '-P', SourceFile, LibDir + '/']) then
      begin
        ShowAndLogError('libQt' + QtVer + 'Pas のインストールに失敗しました。');
        Exit;
      end;
    end;

    if not RunSudoCommand(['/sbin/ldconfig']) then
    begin
      ShowAndLogError('ldconfig に失敗しました。');
      Exit;
    end;

    Result := True;
  finally
    Files.Free;
  end;
end;

procedure TForm1.StartInstallAndBuild;
var
  i: Integer;
  Pwd, InputLine: string;
begin
  FMode := omInstallAndBuild;
  FPending := '';
  FLastOutputTick := GetTickCount64;
  FStalled := False;

  MemoTop.Lines.Clear;
  MemoBottom.Lines.Clear;
  AppendBottom('=== 必要パッケージの導入を開始します ===');

  SetControlsEnabled(False);
  ButtonMainAction.Caption := '導入・ビルド実行中...';
  Caption := 'JPSupport-Qt インストーラー - パッケージ導入中...';

  if Assigned(FProcess) then
    FProcess.Free;
  FProcess := TProcess.Create(nil);

  Pwd := PasswordBox('sudo認証',
    '必要なパッケージを導入するため、管理者パスワードを入力してください:');
  if Pwd = '' then
  begin
    FProcess.Free;
    FProcess := nil;
    FMode := omNone;
    SetControlsEnabled(True);
    UpdateButtonState;
    Exit;
  end;

  FProcess.Executable := '/usr/bin/sudo';
  FProcess.Parameters.Add('-S');
  FProcess.Parameters.Add('apt');
  FProcess.Parameters.Add('install');
  FProcess.Parameters.Add('-y');
  for i := Low(cAptPackages) to High(cAptPackages) do
    FProcess.Parameters.Add(cAptPackages[i]);

  if GetCurrentTargetName = 'qt6' then
    FProcess.Parameters.Add('qt6-base-dev')
  else
    FProcess.Parameters.Add('qtbase5-dev');

  FProcess.Options := [poUsePipes, poStderrToOutPut];
  FProcess.Execute;

  InputLine := Pwd + LineEnding;
  Pwd := '';
  FProcess.Input.Write(InputLine[1], Length(InputLine));
  InputLine := '';

  TimerPoll.Enabled := True;
end;

procedure TForm1.StartBuildOnly(AContinueAfterInstall: Boolean);
var
  Target: string;
begin
  Target := GetCurrentTargetName;

  FEffectiveVersion := Trim(EditVersion.Text);
  if FEffectiveVersion = '' then
    FEffectiveVersion := FDefaultVersion;

  FMode := omBuildOnly;
  FBuildPreparePhase := not AContinueAfterInstall;
  FPending := '';
  FLastOutputTick := GetTickCount64;
  FStalled := False;

  { MemoTop/MemoBottomのクリア、およびチェックポイント基準時刻・直前工程名の
    リセットは、一連の実行の最初のフェーズ(準備フェーズ)でのみ行う。継続フェーズ
    (2回目の呼び出し)でも行ってしまうと、準備フェーズで記録した[1/6]〜[4/6]の
    表示や経過時間の起点が失われ、「[1/6]から[5/6]に飛ぶ」ように見えてしまう。
    MemoTop/MemoBottom自体のクリアは、一連の実行の起点であるStartInstallAndBuild
    で既に一度だけ行われている。 }
  if not AContinueAfterInstall then
  begin
    FLastCheckpointTick := GetTickCount64;
    FLastStepLine := '';
  end;

  SetControlsEnabled(False);
  ButtonMainAction.Caption := 'ビルド実行中...';
  Caption := 'JPSupport-Qt インストーラー - ビルド実行中...';

  if Assigned(FProcess) then
    FProcess.Free;
  FProcess := TProcess.Create(nil);

  FProcess.Executable := 'setsid';
  FProcess.Parameters.Add(FScriptPath);
  FProcess.CurrentDirectory := ExtractFilePath(Application.ExeName);
  FProcess.Parameters.Add(Target);
  if AContinueAfterInstall then
    FProcess.Parameters.Add('--continue-after-lib-install')
  else
    FProcess.Parameters.Add('--prepare-only');
  if FEffectiveVersion <> FDefaultVersion then
  begin
    FProcess.Parameters.Add('--lazarus-version=' + FEffectiveVersion);
    FProcess.Parameters.Add('--yes');
  end;
  FProcess.Options := [poUsePipes, poStderrToOutPut];
  FProcess.Execute;

  TimerPoll.Enabled := True;
end;

procedure TForm1.StopPolling;
begin
  TimerPoll.Enabled := False;
end;

procedure TForm1.ButtonMainActionClick(Sender: TObject);
var
  WaitCount: Integer;
  FreeBytes: Int64;
begin
  if FMode <> omNone then
  begin
    if MessageDlg('中止の確認',
        '実行中の処理を中止しますか?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if Assigned(FProcess) and FProcess.Running then
    begin
      ButtonMainAction.Caption := '中止中...';
      FpKill(-FProcess.ProcessID, SIGTERM);
      WaitCount := 0;
      while FProcess.Running and (WaitCount < 30) do
      begin
        Sleep(100);
        Application.ProcessMessages;
        Inc(WaitCount);
      end;
      if FProcess.Running then
      begin
        FpKill(-FProcess.ProcessID, SIGKILL);
        Sleep(200);
      end;
    end;

    StopPolling;
    FMode := omNone;
    SetControlsEnabled(True);
    UpdateButtonState;
    Caption := 'JPSupport-Qt インストーラー';
      Exit;
  end;

  if not FileExists(FScriptPath) then
  begin
    ShowAndLogError('build_jpsupport_qt.sh が見つかりません: ' + FScriptPath);
    Exit;
  end;

  if MessageDlg('インストールの確認',
        'JPSupport版 Lazarus (' + GetCurrentTargetName + ') のセットアップを開始します。' + LineEnding +
        '最初に必要なパッケージを導入し、続けてビルドを実行します。' + LineEnding +
        'パッケージ導入時とシステムライブラリ導入時に、必要に応じて管理者パスワードを求めます。続行しますか?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  FreeBytes := GetFreeDiskSpaceBytes(ExtractFilePath(Application.ExeName));
  if (FreeBytes >= 0) and (FreeBytes < cMinFreeSpaceBytes) then
  begin
    if MessageDlg('空き容量の警告',
        '空き容量が少なくなっています(残り約 ' +
        FormatFloat('0.0', FreeBytes / (1024 * 1024 * 1024)) + ' GB)。' + LineEnding +
        'ビルドには一時的に数GB程度の空き容量が必要です。' + LineEnding +
        'このまま続行しますか?',
        mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  StartInstallAndBuild;
end;

procedure TForm1.ButtonLaunchLazarusClick(Sender: TObject);
var
  Target, LazarusBin, PcpDir, HomeDir, MarkerPath, MarkerContent, BuiltVersion: string;
  MarkerLines: TStringList;
  ColonPos: Integer;
  LaunchProcess: TProcess;
begin
  if FMode <> omNone then
    Exit;

  Target := GetCurrentTargetName;
  LazarusBin := ExtractFilePath(Application.ExeName) +
    GetTargetBuildDirName + '/lazarus-src/lazarus';

  if not FileExists(LazarusBin) then
  begin
    ShowAndLogError('ビルドされたバイナリが見つかりません。先にインストール・ビルドを実行してください。');
    Exit;
  end;

  BuiltVersion := '';
  MarkerPath := ExtractFilePath(Application.ExeName) +
    GetTargetBuildDirName + '/lazarus-src/.jpsupport-patched';
  if FileExists(MarkerPath) then
  begin
    MarkerLines := TStringList.Create;
    try
      MarkerLines.LoadFromFile(MarkerPath);
      if MarkerLines.Count > 0 then
      begin
        MarkerContent := Trim(MarkerLines[0]);
        ColonPos := Pos(':', MarkerContent);
        if ColonPos > 0 then
          BuiltVersion := Copy(MarkerContent, ColonPos + 1, Length(MarkerContent));
      end;
    finally
      MarkerLines.Free;
    end;
  end;

  HomeDir := GetEnvironmentVariable('HOME');
  if BuiltVersion <> '' then
    PcpDir := HomeDir + '/.lazarus_jpsupport_' + Target + '_' + BuiltVersion
  else
    PcpDir := HomeDir + '/.lazarus_jpsupport_' + Target;

  LaunchProcess := TProcess.Create(nil);
  try
    LaunchProcess.Executable := LazarusBin;
    LaunchProcess.Parameters.Add('--pcp=' + PcpDir);
    LaunchProcess.Options := [];
    LaunchProcess.Execute;
  finally
    LaunchProcess.Free;
  end;

  Application.BringToFront;
end;

procedure TForm1.TimerPollTimer(Sender: TObject);
var
  Buf: array[0..4095] of Byte;
  NRead, NLPos: Integer;
  Chunk, ALine: string;
  CurrentMode: TOpMode;
  Target, ExistingPath: string;
begin
  if not Assigned(FProcess) then
    Exit;

  if FProcess.Output.NumBytesAvailable > 0 then
  begin
    FLastOutputTick := GetTickCount64;
    if FStalled then
    begin
      FStalled := False;
      if FMode = omInstallAndBuild then
        ButtonMainAction.Caption := '導入・ビルド実行中...'
      else
        ButtonMainAction.Caption := 'ビルド実行中...';
      Caption := 'JPSupport-Qt インストーラー - 実行中...';
    end;
    NRead := FProcess.Output.Read(Buf, SizeOf(Buf));
    if NRead > 0 then
    begin
      SetString(Chunk, PAnsiChar(@Buf[0]), NRead);
      FPending := FPending + Chunk;
      repeat
        NLPos := Pos(#10, FPending);
        if NLPos > 0 then
        begin
          ALine := Copy(FPending, 1, NLPos - 1);
          if (Length(ALine) > 0) and (ALine[Length(ALine)] = #13) then
            SetLength(ALine, Length(ALine) - 1);
          FPending := Copy(FPending, NLPos + 1, Length(FPending));
          HandleLine(ALine);
        end;
      until NLPos = 0;
    end;
  end
  else if FProcess.Running and (not FStalled) and
         (GetTickCount64 - FLastOutputTick > 8000) then
  begin
    FStalled := True;
    ButtonMainAction.Caption := '応答待ち...';
    Caption := 'JPSupport-Qt インストーラー - 応答待ち(端末画面をご確認ください)';
  end;

  if (not FProcess.Running) and (FProcess.Output.NumBytesAvailable = 0) then
  begin
    if FPending <> '' then
    begin
      HandleLine(FPending);
      FPending := '';
    end;

    CurrentMode := FMode;
    StopPolling;

    if (CurrentMode = omInstallAndBuild) and (FProcess.ExitStatus = 0) then
    begin
      AppendBottom('=== パッケージの導入が完了しました。libQtPas のビルドを開始します ===');
      if Assigned(FProcess) then
      begin
        FProcess.Free;
        FProcess := nil;
      end;
      StartBuildOnly(False);
      Exit;
    end;

    if (CurrentMode = omBuildOnly) and (FProcess.ExitStatus = 0) and
       FBuildPreparePhase then
    begin
      AppendBottom('=== libQtPas のビルドが完了しました。システムへのインストールを開始します ===');
      Target := GetCurrentTargetName;
      if not InstallBuiltQtPas(Target) then
      begin
        if Assigned(FProcess) then
        begin
          FProcess.Free;
          FProcess := nil;
        end;
        FMode := omNone;
        SetControlsEnabled(True);
        UpdateButtonState;
        Caption := 'JPSupport-Qt インストーラー';
        Exit;
      end;

      AppendBottom('=== libQtPas のインストールが完了しました。Lazarus本体のビルドを開始します ===');
      if Assigned(FProcess) then
      begin
        FProcess.Free;
        FProcess := nil;
      end;
      StartBuildOnly(True);
      Exit;
    end;

    FMode := omNone;
    SetControlsEnabled(True);
    UpdateButtonState;
    Caption := 'JPSupport-Qt インストーラー';
  
    if CurrentMode = omInstallAndBuild then
    begin
      if FProcess.ExitStatus <> 0 then
        MessageDlg('失敗', 'パッケージの導入に失敗しました(終了コード ' +
          IntToStr(FProcess.ExitStatus) + ')。下段のログをご確認ください。',
            mtError, [mbOK], 0);
    end
    else if CurrentMode = omBuildOnly then
    begin
      if FProcess.ExitStatus = 0 then
      begin
        AppendTop('======================================================================' + LineEnding +
          '終了コード: 0 (正常終了)');
        MessageDlg('完了', 'JPSupport版 Lazarus のセットアップが正常に完了しました！' + LineEnding +
          '「Lazarusを起動」ボタンからいつでも起動できます。', mtInformation, [mbOK], 0);
      end
      else
      begin
        AppendTop('======================================================================' + LineEnding +
          '終了コード: ' + IntToStr(FProcess.ExitStatus) + ' (異常終了 - 下のログを確認してください)');
        MessageDlg('異常終了', 'ビルドが異常終了しました(終了コード ' +
          IntToStr(FProcess.ExitStatus) + ')。' + LineEnding +
          '下段のログをご確認ください。', mtError, [mbOK], 0);
      end;
    end;
  end;
end;

end.
