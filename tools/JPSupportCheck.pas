// JPSupportCheck
program JPSupportCheck;

{$mode objfpc}{$H+}
{$define WITH_GTK2_IM}

uses
  Classes, SysUtils, Process,
  GLib2, Gdk2, Gtk2, Pango;

// ===== コマンド実行 =====
function RunCommand(const ACmd: string): string;
var
  P: TProcess;
  S: TStringList;
begin
  Result := '';
  P := TProcess.Create(nil);
  S := TStringList.Create;
  try
    P.Options := [poWaitOnExit, poUsePipes];
    P.Executable := '/bin/bash';
    P.Parameters.Add('-c');
    P.Parameters.Add(ACmd);
    P.Execute;
    S.LoadFromStream(P.Output);
    Result := Trim(S.Text);
  finally
    P.Free;
    S.Free;
  end;
end;

// ===== ひらがな判定 =====
function ContainsHiragana(const S: string): Boolean;
var
  U: UnicodeString;
  C: WideChar;
  I: Integer;
begin
  Result := False;
  U := UTF8Decode(S);
  for I := 1 to Length(U) do
  begin
    C := U[I];
    if (Ord(C) >= $3040) and (Ord(C) <= $309F) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

// ===== preedit-changed シグナルハンドラ =====
var
  GPreeditText: string = '';
  GCommitText: string = '';

procedure OnPreeditChanged(AContext: PGtkIMContext; AData: gpointer); cdecl;
var
  PStr: PPGChar;
  PAttrs: PPangoAttrList;
  CursorPos: gint;
begin
  PStr := nil;
  gtk_im_context_get_preedit_string(AContext, PStr, PAttrs, @CursorPos);
  if (PStr <> nil) and (PStr^ <> nil) then
    GPreeditText := PStr^;
end;

procedure OnCommit(AContext: PGtkIMContext; AStr: PGChar; AData: gpointer); cdecl;
begin
  if AStr <> nil then
    GCommitText := AStr;
end;

// ===== GTK2 IMテスト =====
function TestIMInput: Boolean;
var
  LazarusWinID: string;
  ClipResult: string;

  function DoTest: Boolean;
  begin
    Result := False;
    RunCommand('fcitx5-remote -c');
    Sleep(500);
    RunCommand('fcitx5-remote -o');
    Sleep(500);
    RunCommand('xdotool key --window ' + LazarusWinID + ' 0xff2a');
    Sleep(500);
    RunCommand('xdotool type --window ' + LazarusWinID + ' "a"');
    Sleep(500);
    RunCommand('xdotool key --window ' + LazarusWinID + ' Return');
    Sleep(500);
    RunCommand('xdotool key --window ' + LazarusWinID + ' ctrl+a');
    Sleep(500);
    RunCommand('xdotool key --window ' + LazarusWinID + ' ctrl+c');
    Sleep(500);
    ClipResult := RunCommand('xclip -o -selection clipboard 2>/dev/null');
    RunCommand('xdotool key --window ' + LazarusWinID + ' ctrl+z');
    Sleep(300);
    RunCommand('xdotool key --window ' + LazarusWinID + ' ctrl+z');
    Sleep(300);
    RunCommand('xdotool key --window ' + LazarusWinID + ' ctrl+z');
    Result := ContainsHiragana(ClipResult);
  end;

begin
  Result := False;

  // Lazarusが起動しているか確認
  if RunCommand('pgrep -x lazarus') = '' then
  begin
    WriteLn('');
    WriteLn('  NG: Lazarusが起動していません。Lazarusを起動後、再度このプログラムを実行してください。');
    Exit;
  end;

  // ソースエディタのウィンドウIDを取得
  LazarusWinID := RunCommand('xdotool search --name "ソースエディタ" 2>/dev/null | head -1');
  if LazarusWinID = '' then
  begin
    WriteLn('');
    WriteLn('  NG: LazarusのウィンドウIDが取得できません');
    Exit;
  end;

  // フォーカスを移す
  RunCommand('xdotool windowfocus --sync ' + LazarusWinID);
  RunCommand('xdotool windowactivate --sync ' + LazarusWinID);
  RunCommand('xdotool mousemove --window ' + LazarusWinID + ' --polar 0 0');
  RunCommand('xdotool click --window ' + LazarusWinID + ' 1');
  Sleep(1500);

  // テスト実行（失敗時はリトライ）
  if DoTest then
    Result := True
  else
  begin
    Sleep(1000);
    if DoTest then
      Result := True
    else
      WriteLn('  ClipResult=[', ClipResult, ']');
  end;
end;

// ===== メイン =====
var
  AllOK: Boolean;
  GTK_IM, XMOD, IMModPath, IMServer, PKGCheck: string;
begin
  AllOK := True;
  WriteLn('=== JPSupport 環境診断 ===');
  WriteLn('');

  // ① 環境変数チェック
  GTK_IM := GetEnvironmentVariable('GTK_IM_MODULE');
  XMOD   := GetEnvironmentVariable('XMODIFIERS');

  if (GTK_IM = 'fcitx') or (GTK_IM = 'fcitx5') or (GTK_IM = 'ibus') then
    WriteLn('① GTK_IM_MODULE=' + GTK_IM + ' ... OK')
  else
  begin
    WriteLn('① GTK_IM_MODULE=' + GTK_IM + ' ... NG');
    AllOK := False;
  end;

  if (XMOD = '@im=fcitx') or (XMOD = '@im=fcitx5') or (XMOD = '@im=ibus') then
    WriteLn('  XMODIFIERS=' + XMOD + ' ... OK')
  else
  begin
    WriteLn('  XMODIFIERS=' + XMOD + ' ... NG');
    AllOK := False;
  end;

  // ② GTK2 IMモジュールチェック
  IMModPath := RunCommand('find /usr/lib -path "*/gtk-2.0/*" -name "im-fcitx5.so" -o -path "*/gtk-2.0/*" -name "im-ibus.so" 2>/dev/null | head -1');
  if IMModPath <> '' then
    WriteLn('② GTK2 IMモジュール ... OK')
  else
  begin
    WriteLn('② GTK2 IMモジュール ... NG');
    AllOK := False;
  end;

  // ③ IMサーバー起動確認
  if (GTK_IM = 'fcitx') or (GTK_IM = 'fcitx5') then
  begin
    IMServer := RunCommand('fcitx5-remote');
    if (IMServer = '1') or (IMServer = '2') then
      WriteLn('③ IMサーバー(Fcitx5) ... OK')
    else
    begin
      WriteLn('③ IMサーバー(Fcitx5) ... NG');
      AllOK := False;
    end;
  end
  else if GTK_IM = 'ibus' then
  begin
    IMServer := RunCommand('pgrep -x ibus-daemon');
    if IMServer <> '' then
      WriteLn('③ IMサーバー(IBus) ... OK')
    else
    begin
      WriteLn('③ IMサーバー(IBus) ... NG');
      AllOK := False;
    end;
  end;

  // ④ JPSupportインストール確認
  PKGCheck := RunCommand('grep -l "JPSupport" ~/.lazarus/packagefiles.xml 2>/dev/null');
  if PKGCheck <> '' then
    WriteLn('④ JPSupportインストール ... OK')
  else
  begin
    WriteLn('④ JPSupportインストール ... NG');
    AllOK := False;
  end;

  // ⑤ 日本語入力テスト
  Write('⑤ 日本語入力テスト ... ');
  if TestIMInput then
    WriteLn('OK')
  else
  begin
    WriteLn('NG');
    AllOK := False;
  end;

  WriteLn('');
  if AllOK then
    WriteLn('=== 診断完了: 環境は整っています ===')
  else
    WriteLn('=== 診断完了: 問題が検出されました ===');

  if AllOK then
    Halt(0)
  else
    Halt(1);
end.
