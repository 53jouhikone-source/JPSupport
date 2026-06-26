// 0001
unit JPSupportUnit;

{$mode objfpc}{$H+}
{$define WITH_GTK2_IM}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  SynEdit, SynEditTypes, SynEditKeyCmds,
  GLib2, Gdk2, Gtk2, Pango,
  Gtk2Globals, LCLType, ExtCtrls, LMessages, LazUTF8,
  Math;

type
  PPgchar         = ^PAnsiChar;
  PPPangoAttrList = ^Pointer;

  PPangoAttribute = ^TPangoAttribute;
  TPangoAttrClass = record
    type_   : guint;
    copy    : pointer;
    destroy : pointer;
    equal   : pointer;
  end;

  TPangoAttribute = record
    klass       : ^TPangoAttrClass;
    start_index : guint;
    end_index   : guint;
  end;

  TPangoAttrInt = record
    attr  : TPangoAttribute;
    value : gint;
  end;
  PPangoAttrInt = ^TPangoAttrInt;

  TPreeditSegment = record
    StartPos : Integer;
    EndPos   : Integer;
    IsActive : Boolean;
  end;

  TGdkRectangle = record
    x, y, width, height : gint;
  end;
  PGdkRectangle = ^TGdkRectangle;

procedure gtk_im_context_get_preedit_string(
            context    : PGtkIMContext;
            str        : PPgchar;
            attrs      : PPPangoAttrList;
            cursor_pos : pgint);
  cdecl; external 'libgtk-x11-2.0.so.0';

procedure gtk_im_context_set_cursor_location(
            context : PGtkIMContext;
            area    : PGdkRectangle);
  cdecl; external 'libgtk-x11-2.0.so.0';

function pango_attr_list_get_iterator(
  list: Pointer): Pointer;
  cdecl; external 'libpango-1.0.so.0';

function pango_attr_iterator_next(
  iterator: Pointer): gboolean;
  cdecl; external 'libpango-1.0.so.0';

function pango_attr_iterator_get(
  iterator: Pointer;
  type_: guint): PPangoAttribute;
  cdecl; external 'libpango-1.0.so.0';

procedure pango_attr_iterator_range(
  iterator: Pointer;
  start_: Pgint;
  end_: Pgint);
  cdecl; external 'libpango-1.0.so.0';

procedure pango_attr_iterator_destroy(
  iterator: Pointer);
  cdecl; external 'libpango-1.0.so.0';

type

  { TJPSupport }

  TJPSupport = class(TSynEdit)
  private
    FIMContext         : PGtkIMContext;
    FGdkWindow         : PGdkWindow;
    FUnderlinePaintBox : TPaintBox;
    FPreeditString     : String;
    FPreeditCursor     : Integer;
    FPreeditSegments   : array of TPreeditSegment;
    FLastCaretXY       : TPoint;
    FPreeditStartXY    : TPoint;
    FIMECommitting     : Boolean;
    FIMFocused         : Boolean;
    FPreeditInserted   : String;
    FInPreeditUpdate   : Boolean;
    FPreeditEndPhysX   : Integer;
    FSegStartPixels    : array of Integer;
    FSegEndPixels      : array of Integer;

    procedure UpdateCursorLocation;
    procedure UpdatePreeditLabel;
    procedure OnUnderlinePaint(Sender: TObject);
    procedure RemovePreeditFromEditor;
    procedure InsertPreeditToEditor(const S: String);

    { IMEイベントハンドラ（内部処理） }
    procedure IMPreeditStart;
    procedure IMPreeditChanged;
    procedure IMPreeditEnd;
    procedure IMCommit(const S: String);
    procedure IMEStatusChange(Sender: TObject;
                Changes: TSynStatusChanges);
    procedure IMEProcessCommand(Sender: TObject;
                var Command: TSynEditorCommand;
                var AChar: TUTF8Char;
                Data: pointer);

  protected
    procedure WMLMIMComposition(var Message: TLMessage);
      message LM_IM_COMPOSITION;
    procedure DoEnter; override;
    procedure DoExit; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InitIME;
  end;

procedure Register;

implementation

{ BACKGROUNDがある範囲リストと重なるか判定 }
function RangeOverlaps(aStart, aEnd, bStart, bEnd: Integer): Boolean;
begin
  Result := (aStart < bEnd) and (aEnd > bStart);
end;

{ GTKコールバック：dataにTJPSupportインスタンスを渡す }

procedure GTKIMPreeditStart(context: PGtkIMContext;
  data: gpointer); cdecl;
begin
  if data = nil then Exit;
  TJPSupport(data).IMPreeditStart;
end;

procedure GTKIMPreeditChanged(context: PGtkIMContext;
  data: gpointer); cdecl;
var
  pstr: PAnsiChar;
  pattrs: Pointer;
  pcurs: gint;
begin
  pstr := nil; pattrs := nil; pcurs := 0;
  gtk_im_context_get_preedit_string(context, @pstr, @pattrs, @pcurs);
  if pstr <> nil then
  begin
    WriteLn('[JPSupportUnit PreeditChanged] preedit=', UTF8String(pstr));
    Flush(Output);
    g_free(pstr);
  end;
  if pattrs <> nil then pango_attr_list_unref(pattrs);
  if data = nil then Exit;
  TJPSupport(data).IMPreeditChanged;
end;

procedure GTKIMPreeditEnd(context: PGtkIMContext;
  data: gpointer); cdecl;
begin
  if data = nil then Exit;
  TJPSupport(data).IMPreeditEnd;
end;

procedure GTKIMCommit(context: PGtkIMContext;
  str: PAnsiChar; data: gpointer); cdecl;
begin
  if str <> nil then
  begin
    WriteLn('[JPSupportUnit GTKIMCommit] str=', UTF8String(str));
    Flush(Output);
  end;
  if data = nil then Exit;
  if str = nil then Exit;
  TJPSupport(data).IMCommit(UTF8String(str));
end;

{ TJPSupport }

constructor TJPSupport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FIMContext        := nil;
  FGdkWindow        := nil;
  FPreeditString    := '';
  FPreeditCursor    := 0;
  SetLength(FPreeditSegments, 0);
  FLastCaretXY      := Point(1, 1);
  FPreeditStartXY   := Point(1, 1);
  FIMECommitting    := False;
  FIMFocused        := False;
  FPreeditInserted  := '';
  FInPreeditUpdate  := False;
  FPreeditEndPhysX  := 1;
  SetLength(FSegStartPixels, 0);
  SetLength(FSegEndPixels,   0);

  { 初回空行挿入防止 }
  if Lines.Count = 0 then
    Lines.Add('');

  FUnderlinePaintBox         := TPaintBox.Create(Self);
  FUnderlinePaintBox.Parent  := Self;
  FUnderlinePaintBox.Visible := False;
  FUnderlinePaintBox.OnPaint := @OnUnderlinePaint;

  Options := Options
    - [eoScrollPastEol]
    - [eoScrollPastEof]
    - [eoAutoIndent];

  OnStatusChange := @IMEStatusChange;
  OnProcessCommand := @IMEProcessCommand;
end;

destructor TJPSupport.Destroy;
begin
  FIMContext := nil;
  inherited Destroy;
end;

procedure TJPSupport.InitIME;
begin
  FIMContext := im_context;
  if FIMContext = nil then Exit;

  g_signal_connect(FIMContext, 'preedit-start',
    TGCallback(@GTKIMPreeditStart), Self);
  g_signal_connect(FIMContext, 'preedit-changed',
    TGCallback(@GTKIMPreeditChanged), Self);
  g_signal_connect(FIMContext, 'preedit-end',
    TGCallback(@GTKIMPreeditEnd), Self);
  g_signal_connect(FIMContext, 'commit',
    TGCallback(@GTKIMCommit), Self);

end;

procedure TJPSupport.WMLMIMComposition(var Message: TLMessage);
var
  S : String;
begin
  inherited;

  if Message.WParam and GTK_IM_FLAG_PREEDIT <> 0 then
  begin
    if Message.LParam = 0 then Exit;
    S := UTF8String(PChar(Message.LParam));
    if S = '' then Exit;
    FPreeditString := S;
    UpdateCursorLocation;
    UpdatePreeditLabel;
  end;

  if Message.WParam and GTK_IM_FLAG_COMMIT <> 0 then
  begin
    FPreeditString := '';
    SetLength(FPreeditSegments, 0);
    UpdatePreeditLabel;
  end;

  if Message.WParam and GTK_IM_FLAG_END <> 0 then
  begin
    FPreeditString := '';
    SetLength(FPreeditSegments, 0);
    UpdatePreeditLabel;
  end;
end;

procedure TJPSupport.DoEnter;
var
  GtkWid : PGtkWidget;
begin
  inherited DoEnter;

  { FGdkWindowが未設定なら初期化を試みる }
  if FGdkWindow = nil then
  begin
    GtkWid := PGtkWidget(Handle);
    if GtkWid <> nil then
    begin
      FGdkWindow := GtkWid^.window;
      if FGdkWindow <> nil then
      begin
        gtk_im_context_set_client_window(FIMContext, FGdkWindow);
        WriteLn('DoEnter: FLastCaretXY=', FLastCaretXY.X, ',', FLastCaretXY.Y);
        UpdateCursorLocation;
        WriteLn('DoEnter: UpdateCursorLocation done');
      end;
    end;
  end;

  if FIMContext = nil then Exit;
  if FGdkWindow = nil then Exit;
  if FIMFocused then Exit;

  gtk_im_context_focus_in(FIMContext);
  FIMFocused := True;
  UpdateCursorLocation;
end;

procedure TJPSupport.DoExit;
begin
  if FIMContext <> nil then
  begin
    RemovePreeditFromEditor;
    FPreeditString := '';
    FPreeditCursor := 0;
    SetLength(FPreeditSegments, 0);
    UpdatePreeditLabel;
    gtk_im_context_focus_out(FIMContext);
    gtk_im_context_set_client_window(FIMContext, nil);
    FGdkWindow := nil;
    FIMFocused := False;
  end;
  inherited DoExit;
end;

procedure TJPSupport.IMEStatusChange(Sender: TObject;
  Changes: TSynStatusChanges);
begin
  if not ((scCaretX in Changes) or
          (scCaretY in Changes)) then Exit;

  if (FPreeditString = '') and
     (not FIMECommitting) and
     (not FInPreeditUpdate) then
    FLastCaretXY := Point(CaretX, CaretY);

  UpdateCursorLocation;
  UpdatePreeditLabel;
end;

procedure TJPSupport.IMPreeditStart;
begin
  FPreeditStartXY := FLastCaretXY;
  UpdateCursorLocation;
end;

procedure TJPSupport.IMPreeditChanged;
var
  pstr      : PAnsiChar;
  pattrs    : Pointer;
  imcursor    : gint;
  iter      : Pointer;
  attr      : PPangoAttribute;
  istart    : gint;
  iend      : gint;
  seg       : TPreeditSegment;
  bgRanges  : array of record
                StartPos : Integer;
                EndPos   : Integer;
              end;
  bgCount   : Integer;
  j         : Integer;
  hasActive : Boolean;
begin
  pstr := nil; pattrs := nil; imcursor := 0;
  gtk_im_context_get_preedit_string(FIMContext,
    @pstr, @pattrs, @imcursor);

  if pstr <> nil then
  begin
    FPreeditString := UTF8String(pstr);
    g_free(pstr);
  end
  else
    FPreeditString := '';

  FPreeditCursor := imcursor;
  SetLength(FPreeditSegments, 0);
  SetLength(bgRanges, 0);
  bgCount := 0;

  if pattrs <> nil then
  begin
    iter := pango_attr_list_get_iterator(pattrs);
    repeat
      istart := 0; iend := 0;
      pango_attr_iterator_range(iter, @istart, @iend);
      attr := pango_attr_iterator_get(iter, PANGO_ATTR_BACKGROUND);
      if attr <> nil then
      begin
        SetLength(bgRanges, bgCount + 1);
        bgRanges[bgCount].StartPos := istart;
        bgRanges[bgCount].EndPos   := iend;
        Inc(bgCount);
      end;
    until not pango_attr_iterator_next(iter);
    pango_attr_iterator_destroy(iter);

    iter := pango_attr_list_get_iterator(pattrs);
    repeat
      istart := 0; iend := 0;
      pango_attr_iterator_range(iter, @istart, @iend);
      attr := pango_attr_iterator_get(iter, PANGO_ATTR_UNDERLINE);
      if attr <> nil then
      begin
        hasActive := False;
        for j := 0 to bgCount - 1 do
          if RangeOverlaps(istart, iend,
               bgRanges[j].StartPos, bgRanges[j].EndPos) then
          begin
            hasActive := True;
            Break;
          end;
        seg.StartPos := istart;
        seg.EndPos   := iend;
        seg.IsActive := hasActive;
        SetLength(FPreeditSegments,
          Length(FPreeditSegments) + 1);
        FPreeditSegments[High(FPreeditSegments)] := seg;
      end;
    until not pango_attr_iterator_next(iter);
    pango_attr_iterator_destroy(iter);

    for j := 0 to bgCount - 1 do
    begin
      seg.StartPos := bgRanges[j].StartPos;
      seg.EndPos   := bgRanges[j].EndPos;
      seg.IsActive := True;
      SetLength(FPreeditSegments,
        Length(FPreeditSegments) + 1);
      FPreeditSegments[High(FPreeditSegments)] := seg;
    end;

    pango_attr_list_unref(pattrs);
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
    FLastCaretXY := Point(CaretX, CaretY);
  end;

  UpdateCursorLocation;
  UpdatePreeditLabel;
end;

procedure TJPSupport.IMPreeditEnd;
begin
  RemovePreeditFromEditor;
  FPreeditString := '';
  FPreeditCursor := 0;
  SetLength(FPreeditSegments, 0);
  UpdatePreeditLabel;
end;

procedure TJPSupport.IMCommit(const S: String);
begin
  if not Focused then Exit;

  FIMECommitting := True;
  try
    RemovePreeditFromEditor;
    FPreeditString := '';
    FPreeditCursor := 0;
    SetLength(FPreeditSegments, 0);
    UpdatePreeditLabel;
    InsertTextAtCaret(S);
    EnsureCursorPosVisible;
    FLastCaretXY := Point(CaretX, CaretY);
  finally
    FIMECommitting := False;
  end;
end;

procedure TJPSupport.RemovePreeditFromEditor;
var
  i         : Integer;
  CharCount : Integer;
begin
  if FPreeditInserted = '' then Exit;

  CharCount := UTF8Length(FPreeditInserted);
  CaretXY := FPreeditStartXY;

  for i := 1 to CharCount do
    CommandProcessor(ecDeleteChar, #0, nil);

  FPreeditInserted := '';
  FPreeditEndPhysX := FPreeditStartXY.X;
  FLastCaretXY     := FPreeditStartXY;
end;

procedure TJPSupport.InsertPreeditToEditor(const S: String);
var
  i        : Integer;
  MoveBack : Integer;
  BoxLeft  : Integer;
  n        : Integer;
  bytePos  : Integer;
  charLen  : Integer;
  colPos   : Integer;
  code     : Cardinal;
  segPx    : TPoint;
begin
  if S = '' then Exit;

  CaretXY := FPreeditStartXY;
  InsertTextAtCaret(S);
  FPreeditInserted := S;
  FPreeditEndPhysX := CaretX;

  BoxLeft := RowColumnToPixels(
               Point(FPreeditStartXY.X,
                     FPreeditStartXY.Y)).X;

  SetLength(FSegStartPixels, Length(FPreeditSegments));
  SetLength(FSegEndPixels,   Length(FPreeditSegments));

  for n := 0 to High(FPreeditSegments) do
  begin
    bytePos := 1;
    colPos  := FPreeditStartXY.X;
    while bytePos <= FPreeditSegments[n].StartPos do
    begin
      charLen := UTF8CodepointSize(@S[bytePos]);
      code    := UTF8CodepointToUnicode(@S[bytePos], charLen);
      if code >= $2E80 then
        Inc(colPos, 2)
      else
        Inc(colPos, 1);
      Inc(bytePos, charLen);
    end;
    segPx := RowColumnToPixels(
               Point(colPos, FPreeditStartXY.Y));
    FSegStartPixels[n] := segPx.X - BoxLeft;

    bytePos := 1;
    colPos  := FPreeditStartXY.X;
    while bytePos <= FPreeditSegments[n].EndPos do
    begin
      charLen := UTF8CodepointSize(@S[bytePos]);
      code    := UTF8CodepointToUnicode(@S[bytePos], charLen);
      if code >= $2E80 then
        Inc(colPos, 2)
      else
        Inc(colPos, 1);
      Inc(bytePos, charLen);
    end;
    segPx := RowColumnToPixels(
               Point(colPos, FPreeditStartXY.Y));
    FSegEndPixels[n] := segPx.X - BoxLeft;
  end;

  MoveBack := UTF8Length(S) - FPreeditCursor;
  for i := 1 to MoveBack do
    CommandProcessor(ecLeft, #0, nil);
end;

procedure TJPSupport.OnUnderlinePaint(Sender: TObject);
var
  CV      : TCanvas;
  UnderY  : Integer;
  i       : Integer;
  X1, X2  : Integer;
begin
  if FPreeditString = '' then Exit;
  if Length(FPreeditSegments) = 0 then Exit;
  if Length(FSegStartPixels) <> Length(FPreeditSegments) then Exit;

  CV := FUnderlinePaintBox.Canvas;
  CV.Brush.Style := bsClear;
  UnderY := LineHeight - 3;

  for i := 0 to High(FPreeditSegments) do
  begin
    X1 := FSegStartPixels[i];
    X2 := FSegEndPixels[i];

    if FPreeditSegments[i].IsActive then
    begin
      CV.Pen.Color := Font.Color;
      CV.Pen.Width := 3;
    end
    else
    begin
      CV.Pen.Color := Font.Color;
      CV.Pen.Width := 1;
    end;
    CV.Line(X1, UnderY, X2, UnderY);
  end;
end;

procedure TJPSupport.UpdateCursorLocation;
var
  ImgPt   : TPoint;
  LHeight : Integer;
  R       : TGdkRectangle;
begin
  if FIMContext = nil then Exit;
  if FGdkWindow = nil then Exit;

  ImgPt := RowColumnToPixels(
             Point(FLastCaretXY.X, FLastCaretXY.Y));

  LHeight := LineHeight;
  if LHeight <= 0 then LHeight := 20;

  R.x      := ImgPt.X;
  R.y      := ImgPt.Y;
  R.width  := 1;
  R.height := LHeight;
  gtk_im_context_set_cursor_location(FIMContext, @R);
end;

procedure TJPSupport.UpdatePreeditLabel;
var
  ImgPt    : TPoint;
  EndImgPt : TPoint;
  TxtW     : Integer;
  TxtH     : Integer;
  OffsetX  : Integer;
begin
  if FPreeditString <> '' then
  begin
    ImgPt   := RowColumnToPixels(
                 Point(FPreeditStartXY.X, FPreeditStartXY.Y));
    OffsetX := ImgPt.X;

    EndImgPt := RowColumnToPixels(
                  Point(FPreeditEndPhysX, FPreeditStartXY.Y));
    TxtW := EndImgPt.X - ImgPt.X;
    if TxtW <= 0 then
      TxtW := CharWidth;

    TxtH := LineHeight + 4;

    FUnderlinePaintBox.Left    := OffsetX;
    FUnderlinePaintBox.Top     := ImgPt.Y;
    FUnderlinePaintBox.Width   := TxtW;
    FUnderlinePaintBox.Height  := TxtH;
    FUnderlinePaintBox.Visible := True;
    FUnderlinePaintBox.BringToFront;
    FUnderlinePaintBox.Invalidate;
  end
  else
    FUnderlinePaintBox.Visible := False;
end;

procedure TJPSupport.IMEProcessCommand(Sender: TObject;
  var Command: TSynEditorCommand; var AChar: TUTF8Char;
  Data: pointer);
begin
  UpdateCursorLocation;

  if Command = ecChar then
    Command := ecNone;

  if FIMECommitting and (Command = ecLineBreak) then
    Command := ecNone;
end;

procedure Register;
begin
  RegisterComponents('IME', [TJPSupport]);
end;

end.
