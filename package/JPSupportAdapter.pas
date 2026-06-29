// 0037
unit JPSupportAdapter;

{$mode objfpc}{$H+}
{$define WITH_GTK2_IM}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, Graphics,
  SynEdit, SynEditTypes, SynEditKeyCmds,
  GLib2, Gdk2, Gtk2, Pango,
  Gtk2Globals, LCLType, LMessages, LazUTF8,
  Math;

type
  PPgchar         = ^PAnsiChar;
  PPPangoAttrList = ^Pointer;

  TGdkRectangle = record
    x, y, width, height : gint;
  end;
  PGdkRectangle = ^TGdkRectangle;

  { TJPSupportAdapter }

  TPreeditSegment = record
    StartPos : Integer;
    EndPos   : Integer;
    IsActive : Boolean;
  end;

  TJPSupportAdapter = class
  private
    FEditor          : TCustomSynEdit;
    FGdkWindow       : PGdkWindow;
    FPreeditString   : String;
    FPreeditCursor   : Integer;
    FLastCaretXY     : TPoint;
    FPreeditStartXY  : TPoint;
    FIMECommitting   : Boolean;
    FIMFocused       : Boolean;
    FPreeditInserted : String;
    FInPreeditUpdate : Boolean;
    FPreeditEndPhysX     : Integer;
    FInPreedit           : Boolean;
    FIMActive            : Boolean;
    FUnderlinePaintBox   : TPaintBox;
    FPreeditSegments     : array of TPreeditSegment;
    FSegStartPixels      : array of Integer;
    FSegEndPixels        : array of Integer;
    FKeyPressHandlerID   : gulong;
    FGtkWidget           : PGtkWidget;
    FSnooperID           : guint;

    procedure UpdateCursorLocation;
    procedure UpdatePreeditUnderline;
    procedure OnUnderlinePaint(Sender: TObject);
    procedure RemovePreeditFromEditor;
    procedure InsertPreeditToEditor(const S: String);
    procedure IMPreeditStart;
    procedure IMPreeditChanged;
    procedure IMPreeditEnd;
    procedure IMCommit(const S: String);
    procedure OnProcessCommand(Sender: TObject; AfterProcessing: Boolean;
      var Handled: Boolean; var Command: TSynEditorCommand;
      var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
    procedure OnStatusChanged(Sender: TObject;
                Changes: TSynStatusChanges);
  public
    FMyIMContext         : PGtkIMContext;
    constructor Create;
    destructor Destroy; override;
    procedure Attach(AEditor: TCustomSynEdit);
    procedure Detach;
    procedure DoEnter;
    procedure DoExit;
  end;

procedure gtk_im_context_get_preedit_string(
            context    : PGtkIMContext;
            str        : PPgchar;
            attrs      : PPPangoAttrList;
            cursor_pos : pgint);
  cdecl; external 'libgtk-x11-2.0.so.0';

function pango_attr_list_get_iterator(
  list: Pointer): Pointer;
  cdecl; external 'libpango-1.0.so.0';

function pango_attr_iterator_next(
  iterator: Pointer): gboolean;
  cdecl; external 'libpango-1.0.so.0';

function pango_attr_iterator_get(
  iterator: Pointer;
  type_: guint): Pointer;
  cdecl; external 'libpango-1.0.so.0';

procedure pango_attr_iterator_range(
  iterator: Pointer;
  start_: Pgint;
  end_: Pgint);
  cdecl; external 'libpango-1.0.so.0';

procedure pango_attr_iterator_destroy(
  iterator: Pointer);
  cdecl; external 'libpango-1.0.so.0';

procedure gtk_im_context_set_cursor_location(
            context : PGtkIMContext;
            area    : PGdkRectangle);
  cdecl; external 'libgtk-x11-2.0.so.0';

function gtk_im_multicontext_new: PGtkIMContext;
  cdecl; external 'libgtk-x11-2.0.so.0';

function gtk_im_context_filter_keypress(
            context: PGtkIMContext;
            event  : Pointer): gboolean;
  cdecl; external 'libgtk-x11-2.0.so.0';

type
  TGtkKeySnooperFunc = function(grab_widget: PGtkWidget;
    event: Pointer; func_data: Pointer): gint; cdecl;

function gtk_key_snooper_install(snooper_func: TGtkKeySnooperFunc;
  func_data: Pointer): guint;
  cdecl; external 'libgtk-x11-2.0.so.0';

procedure gtk_key_snooper_remove(snooper_handler_id: guint);
  cdecl; external 'libgtk-x11-2.0.so.0';

function g_signal_handlers_disconnect_matched(instance: Pointer;
  mask: guint; signal_id: guint; detail: guint32; closure: Pointer;
  func: Pointer; data: Pointer): guint;
  cdecl; external 'libglib-2.0.so.0';

function g_signal_handler_is_connected(instance: Pointer;
  handler_id: gulong): gboolean;
  cdecl; external 'libglib-2.0.so.0';

procedure g_signal_handler_disconnect(instance: Pointer;
  handler_id: gulong);
  cdecl; external 'libglib-2.0.so.0';

implementation

{ TJPSupportAdapter }

constructor TJPSupportAdapter.Create;
begin
  inherited Create;
  FEditor          := nil;
  FGdkWindow       := nil;
  FPreeditString   := '';
  FPreeditCursor   := 0;
  FLastCaretXY     := Point(1, 1);
  FPreeditStartXY  := Point(1, 1);
  FIMECommitting   := False;
  FIMFocused       := False;
  FPreeditInserted := '';
  FInPreeditUpdate := False;
  FPreeditEndPhysX := 1;
  FSnooperID       := 0;
  FInPreedit       := False;
  FIMActive        := False;
  FUnderlinePaintBox := nil;
  SetLength(FPreeditSegments, 0);
  SetLength(FSegStartPixels, 0);
  SetLength(FSegEndPixels, 0);
end;

destructor TJPSupportAdapter.Destroy;
begin
  Detach;
  inherited Destroy;
end;

procedure TJPSupportAdapter.Attach(AEditor: TCustomSynEdit);
begin
  if FEditor <> nil then Detach;
  FEditor := AEditor;


  FEditor.RegisterStatusChangedHandler(@OnStatusChanged,
    [scCaretX, scCaretY]);
  FEditor.RegisterCommandHandler(@OnProcessCommand, Self);

  { 下線表示用PaintBoxを作成 }
  if FUnderlinePaintBox = nil then
  begin
    FUnderlinePaintBox := TPaintBox.Create(nil);
    FUnderlinePaintBox.Parent  := FEditor;
    FUnderlinePaintBox.Visible := False;
    FUnderlinePaintBox.OnPaint := @OnUnderlinePaint;
  end;
end;

procedure TJPSupportAdapter.Detach;
begin
  if FEditor = nil then Exit;
  try
    FEditor.UnRegisterStatusChangedHandler(@OnStatusChanged);
    FEditor.UnregisterCommandHandler(@OnProcessCommand);
  except
    { Lazarus終了時にFEditorが既に解放済みの場合は無視 }
  end;
  FEditor    := nil;
  FGdkWindow := nil;
  FIMFocused := False;
  FIMActive  := False;
  if FUnderlinePaintBox <> nil then
  begin
    FUnderlinePaintBox.Visible := False;
    FreeAndNil(FUnderlinePaintBox);
  end;
end;

function SnooperFunc(grab_widget: PGtkWidget;
  event: Pointer; func_data: Pointer): gint; cdecl;
var
  Adapter: TJPSupportAdapter;
begin
  Result := 0;
  if func_data = nil then Exit;
  Adapter := TJPSupportAdapter(func_data);
  if Adapter.FMyIMContext = nil then Exit;
  { 毎回IMContextを再アタッチ（Widget再生成対策） }
  if Adapter.FGdkWindow <> nil then
  begin
    gtk_im_context_set_client_window(Adapter.FMyIMContext, Adapter.FGdkWindow);
    gtk_im_context_focus_in(Adapter.FMyIMContext);
  end;
  if gtk_im_context_filter_keypress(Adapter.FMyIMContext, event) then
    Result := 1
  else
    Result := 0;
end;

procedure GTK_CommitSignal(ctx: PGtkIMContext; str: PAnsiChar;
  data: Pointer); cdecl;
begin
  if data = nil then Exit;
  if str <> nil then
    TJPSupportAdapter(data).IMCommit(UTF8String(str));
end;

procedure GTK_PreeditChangedSignal(ctx: PGtkIMContext; data: Pointer); cdecl;
var
  pstr  : PAnsiChar;
  pattrs: Pointer;
  pcurs : gint;
begin
  pstr := nil; pattrs := nil; pcurs := 0;
  gtk_im_context_get_preedit_string(ctx, @pstr, @pattrs, @pcurs);
  if pstr <> nil then
  begin
    g_free(pstr);
  end else
  if pattrs <> nil then pango_attr_list_unref(pattrs);
  if data = nil then Exit;
  TJPSupportAdapter(data).IMPreeditChanged;
end;

procedure GTK_PreeditStartSignal(ctx: PGtkIMContext; data: Pointer); cdecl;
begin
  if data = nil then Exit;
  TJPSupportAdapter(data).IMPreeditStart;
end;

procedure GTK_PreeditEndSignal(ctx: PGtkIMContext; data: Pointer); cdecl;
begin
  if data = nil then Exit;
  TJPSupportAdapter(data).IMPreeditEnd;
end;



procedure TJPSupportAdapter.DoEnter;
var
  GtkWid: PGtkWidget;
begin
  if FGdkWindow = nil then
  begin
    GtkWid := PGtkWidget(FEditor.Handle);
    if GtkWid <> nil then
      FGdkWindow := GtkWid^.window;
  end;
  if FGdkWindow = nil then Exit;
  if FIMFocused then Exit;
  FIMFocused := True;
  FIMActive  := True;
  Flush(Output);
  { LCLのim_contextにもfocus_inを通知（Fcitx5との連携に必要） }
  if im_context <> nil then
  begin
    gtk_im_context_set_client_window(im_context, FGdkWindow);
    gtk_im_context_focus_in(im_context);
  end;
  UpdateCursorLocation;

  { 独自IMContextを作成のみ（シグナル登録・keypressフックは後で） }
  Flush(Output);
  if FMyIMContext = nil then
  begin
    FMyIMContext := gtk_im_multicontext_new;
    Flush(Output);
  end;
  gtk_im_context_set_client_window(FMyIMContext, FGdkWindow);
  gtk_im_context_focus_in(FMyIMContext);

  { 独自コンテキストにシグナル登録（二重登録防止） }
  g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
    @GTK_PreeditStartSignal, Self);
  g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
    @GTK_PreeditChangedSignal, Self);
  g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
    @GTK_PreeditEndSignal, Self);
  g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
    @GTK_CommitSignal, Self);
  g_signal_connect(FMyIMContext, 'preedit-start',
    TGCallback(@GTK_PreeditStartSignal), Self);
  g_signal_connect(FMyIMContext, 'preedit-changed',
    TGCallback(@GTK_PreeditChangedSignal), Self);
  g_signal_connect(FMyIMContext, 'preedit-end',
    TGCallback(@GTK_PreeditEndSignal), Self);
  g_signal_connect(FMyIMContext, 'commit',
    TGCallback(@GTK_CommitSignal), Self);

  Flush(Output);
  { key snooper でキーイベントを横取り（Widget再生成の影響を受けない） }
  Flush(Output);
  if FSnooperID = 0 then
  begin
    FSnooperID := gtk_key_snooper_install(@SnooperFunc, Self);
    Flush(Output);
  end;
end;

procedure TJPSupportAdapter.DoExit;
var
  IMCtx: PGtkIMContext;
begin
  IMCtx := im_context;
  RemovePreeditFromEditor;
  FPreeditString := '';
  FPreeditCursor := 0;
  if IMCtx <> nil then
  begin
    gtk_im_context_focus_out(IMCtx);
    gtk_im_context_set_client_window(IMCtx, nil);
  end;
  if FMyIMContext <> nil then
  begin
      if FSnooperID <> 0 then
    begin
      gtk_key_snooper_remove(FSnooperID);
      FSnooperID := 0;
    end;
    if (FKeyPressHandlerID <> 0) and (FGtkWidget <> nil) then
    begin
      try
        g_signal_handler_disconnect(FGtkWidget, FKeyPressHandlerID);
      except
      end;
      FKeyPressHandlerID := 0;
    end;
    g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
      @GTK_PreeditStartSignal, Self);
    g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
      @GTK_PreeditChangedSignal, Self);
    g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
      @GTK_PreeditEndSignal, Self);
    g_signal_handlers_disconnect_matched(FMyIMContext, 5, 0, 0, nil,
      @GTK_CommitSignal, Self);
    gtk_im_context_focus_out(FMyIMContext);
    gtk_im_context_set_client_window(FMyIMContext, nil);
    g_object_unref(FMyIMContext);
    FMyIMContext := nil;
  end;
  FGtkWidget := nil;
  FGdkWindow := nil;
  FIMFocused := False;
end;

procedure TJPSupportAdapter.OnProcessCommand(Sender: TObject; AfterProcessing: Boolean;
  var Handled: Boolean; var Command: TSynEditorCommand;
  var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
begin
  if AfterProcessing then Exit;
  if Command = ecChar then
  begin
    if FIMActive then
    begin
      Handled := True;
      Command := ecNone;
    end;
  end;
  if FIMECommitting and (Command = ecLineBreak) then
  begin
    Handled := True;
    Command := ecNone;
  end;
end;

procedure TJPSupportAdapter.OnStatusChanged(Sender: TObject;
  Changes: TSynStatusChanges);
begin
  if not ((scCaretX in Changes) or (scCaretY in Changes)) then Exit;
  if (FPreeditString = '') and
     (not FIMECommitting) and
     (not FInPreeditUpdate) then
    FLastCaretXY := Point(FEditor.CaretX, FEditor.CaretY);
  UpdateCursorLocation;
end;

procedure TJPSupportAdapter.OnUnderlinePaint(Sender: TObject);
var
  CV    : TCanvas;
  UnderY: Integer;
  i     : Integer;
begin
  if FPreeditString = '' then Exit;
  if Length(FPreeditSegments) = 0 then Exit;
  if Length(FSegStartPixels) <> Length(FPreeditSegments) then Exit;
  CV := FUnderlinePaintBox.Canvas;
  CV.Brush.Style := bsClear;
  UnderY := FEditor.LineHeight - 3;
  for i := 0 to High(FPreeditSegments) do
  begin
    if FPreeditSegments[i].IsActive then
    begin
      CV.Pen.Color := FEditor.Font.Color;
      CV.Pen.Width := 3;
    end
    else
    begin
      CV.Pen.Color := FEditor.Font.Color;
      CV.Pen.Width := 1;
    end;
    CV.Line(FSegStartPixels[i], UnderY, FSegEndPixels[i], UnderY);
  end;
end;

procedure TJPSupportAdapter.UpdatePreeditUnderline;
var
  ImgPt    : TPoint;
  EndImgPt : TPoint;
  TxtW     : Integer;
  BoxLeft  : Integer;
  n        : Integer;
  bytePos  : Integer;
  charLen  : Integer;
  colPos   : Integer;
  code     : Cardinal;
  segPx    : TPoint;
begin
  if FUnderlinePaintBox = nil then Exit;
  if FEditor = nil then Exit;
  if FPreeditString <> '' then
  begin
    ImgPt   := FEditor.RowColumnToPixels(
                 Point(FPreeditStartXY.X, FPreeditStartXY.Y));
    BoxLeft := ImgPt.X;
    EndImgPt := FEditor.RowColumnToPixels(
                  Point(FPreeditEndPhysX, FPreeditStartXY.Y));
    TxtW := EndImgPt.X - ImgPt.X;
    if TxtW <= 0 then TxtW := FEditor.CharWidth;

    SetLength(FSegStartPixels, Length(FPreeditSegments));
    SetLength(FSegEndPixels,   Length(FPreeditSegments));
    for n := 0 to High(FPreeditSegments) do
    begin
      bytePos := 1; colPos := FPreeditStartXY.X;
      while (bytePos <= FPreeditSegments[n].StartPos) and
            (bytePos <= Length(FPreeditString)) do
      begin
        charLen := UTF8CodepointSize(@FPreeditString[bytePos]);
        code    := UTF8CodepointToUnicode(@FPreeditString[bytePos], charLen);
        if code >= $2E80 then Inc(colPos, 2) else Inc(colPos, 1);
        Inc(bytePos, charLen);
      end;
      segPx := FEditor.RowColumnToPixels(Point(colPos, FPreeditStartXY.Y));
      FSegStartPixels[n] := segPx.X - BoxLeft;

      bytePos := 1; colPos := FPreeditStartXY.X;
      while (bytePos <= FPreeditSegments[n].EndPos) and
            (bytePos <= Length(FPreeditString)) do
      begin
        charLen := UTF8CodepointSize(@FPreeditString[bytePos]);
        code    := UTF8CodepointToUnicode(@FPreeditString[bytePos], charLen);
        if code >= $2E80 then Inc(colPos, 2) else Inc(colPos, 1);
        Inc(bytePos, charLen);
      end;
      segPx := FEditor.RowColumnToPixels(Point(colPos, FPreeditStartXY.Y));
      FSegEndPixels[n] := segPx.X - BoxLeft;
    end;

    FUnderlinePaintBox.Left    := ImgPt.X;
    FUnderlinePaintBox.Top     := ImgPt.Y;
    FUnderlinePaintBox.Width   := TxtW;
    FUnderlinePaintBox.Height  := FEditor.LineHeight + 4;
    FUnderlinePaintBox.Visible := True;
    FUnderlinePaintBox.BringToFront;
    FUnderlinePaintBox.Invalidate;
  end
  else
    FUnderlinePaintBox.Visible := False;
end;

procedure TJPSupportAdapter.UpdateCursorLocation;
var
  ImgPt  : TPoint;
  LHeight: Integer;
  R      : TGdkRectangle;
begin
  if FMyIMContext = nil then Exit;
  if FGdkWindow = nil then Exit;
  ImgPt := FEditor.RowColumnToPixels(
              Point(FLastCaretXY.X, FLastCaretXY.Y));
  LHeight := FEditor.LineHeight;
  if LHeight <= 0 then LHeight := 20;
  R.x := ImgPt.X; R.y := ImgPt.Y;
  R.width := 1;   R.height := LHeight;
  gtk_im_context_set_cursor_location(FMyIMContext, @R);
end;

procedure TJPSupportAdapter.RemovePreeditFromEditor;
var
  i, CharCount: Integer;
begin
  if FPreeditInserted = '' then Exit;
  CharCount := UTF8Length(FPreeditInserted);
  FEditor.CaretXY := FPreeditStartXY;
  for i := 1 to CharCount do
    FEditor.CommandProcessor(ecDeleteChar, #0, nil);
  FPreeditInserted := '';
  FPreeditEndPhysX := FPreeditStartXY.X;
  FLastCaretXY     := FPreeditStartXY;
end;

procedure TJPSupportAdapter.InsertPreeditToEditor(const S: String);
var
  i, MoveBack: Integer;
begin
  if S = '' then Exit;
  FEditor.CaretXY := FPreeditStartXY;
  FEditor.InsertTextAtCaret(S);
  FPreeditInserted := S;
  FPreeditEndPhysX := FEditor.CaretX;
  MoveBack := UTF8Length(S) - FPreeditCursor;
  for i := 1 to MoveBack do
    FEditor.CommandProcessor(ecLeft, #0, nil);
end;

procedure TJPSupportAdapter.IMPreeditStart;
begin
  FInPreedit := True;
  FIMActive  := True;
  FPreeditStartXY := FLastCaretXY;
  UpdateCursorLocation;
end;

procedure TJPSupportAdapter.IMPreeditChanged;
var
  pstr     : PAnsiChar;
  pattrs   : Pointer;
  imcursor : gint;
  iter     : Pointer;
  bgRanges : array of record StartPos, EndPos: Integer; end;
  bgCount  : Integer;
  istart   : gint;
  iend     : gint;
  hasActive: Boolean;
  seg      : TPreeditSegment;
  j        : Integer;
begin
  if FMyIMContext = nil then Exit;
  pstr := nil; pattrs := nil; imcursor := 0;
  gtk_im_context_get_preedit_string(FMyIMContext,
    @pstr, @pattrs, @imcursor);
  if pstr <> nil then
  begin
    FPreeditString := UTF8String(pstr);
    g_free(pstr);
  end
  else
    FPreeditString := '';
  FPreeditCursor := imcursor;
  if pattrs <> nil then
    pango_attr_list_unref(pattrs);
  { Pango属性からセグメント情報を取得 }
  SetLength(FPreeditSegments, 0);
  if pattrs <> nil then
  begin
    bgCount := 0;
      iter := pango_attr_list_get_iterator(pattrs);
      repeat
        istart := 0; iend := 0;
        pango_attr_iterator_range(iter, @istart, @iend);
        if pango_attr_iterator_get(iter, 10) <> nil then  { PANGO_ATTR_BACKGROUND }
        begin
          { BGをアクティブセグメント（太い下線）として登録 }
          seg.StartPos := istart;
          seg.EndPos   := iend;
          seg.IsActive := True;
          SetLength(FPreeditSegments, Length(FPreeditSegments) + 1);
          FPreeditSegments[High(FPreeditSegments)] := seg;
        end;
      until not pango_attr_iterator_next(iter);
      pango_attr_iterator_destroy(iter);

      { preedit全体に細い下線を追加（BGセグメント以外） }
      if Length(FPreeditString) > 0 then
      begin
        seg.StartPos := 0;
        seg.EndPos   := Length(FPreeditString);
        seg.IsActive := False;
        SetLength(FPreeditSegments, Length(FPreeditSegments) + 1);
        FPreeditSegments[High(FPreeditSegments)] := seg;
      end;
  end;

  if not FInPreeditUpdate then
  begin
    FInPreeditUpdate := True;
    try
      RemovePreeditFromEditor;
      if FPreeditString <> '' then
        InsertPreeditToEditor(FPreeditString);
    finally
      FInPreeditUpdate := False;
    end;
    FLastCaretXY := Point(FEditor.CaretX, FEditor.CaretY);
  end;
  UpdateCursorLocation;
  UpdatePreeditUnderline;
end;

function IsHalfwidthKatakana(const S: String): Boolean;
var
  P: PByte;
begin
  Result := False;
  if S = '' then Exit;
  if UTF8Length(S) <> 1 then Exit;
  P := PByte(PAnsiChar(S));
  { 半角カタカナ U+FF65-U+FF9F: UTF-8 = EF BD A5 〜 EF BE 9F }
  if P[0] <> $EF then Exit;
  { U+FF01-U+FF5E (EF BC 81 〜 EF BD 9E): 全角英数記号 }
  { U+FF65-U+FF9F (EF BD A5 〜 EF BE 9F): 半角カタカナ }
  { Mozcの子音中間文字はU+FF41-U+FF5A (EF BD 81〜9A): 全角小文字英字 }
  if P[1] = $BD then Result := True  { EF BD xx は全角・半角混在域 → 全部スキップ }
  else if P[1] = $BE then Result := (P[2] <= $9F);
end;



procedure TJPSupportAdapter.IMPreeditEnd;
begin
  if FIMECommitting then Exit;
  RemovePreeditFromEditor;
  FPreeditString := '';
  FPreeditCursor := 0;
  FInPreedit := False;
  SetLength(FPreeditSegments, 0);
  UpdatePreeditUnderline;
end;

procedure TJPSupportAdapter.IMCommit(const S: String);
begin
  FIMECommitting := True;
  try
    RemovePreeditFromEditor;
    FPreeditString := '';
    FPreeditCursor := 0;
    FInPreedit := False;
    FEditor.InsertTextAtCaret(S);
    FEditor.EnsureCursorPosVisible;
    FLastCaretXY    := Point(FEditor.CaretX, FEditor.CaretY);
    FPreeditStartXY := FLastCaretXY;
  finally
    FIMECommitting := False;
  end;
end;

end.
