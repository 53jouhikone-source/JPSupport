#!/usr/bin/env python3
"""
JPSupport (Qt5 / SynEdit) patches, consolidated - final state (with
bunsetsu/segment-aware preedit display, cursor tracking, and a
color/thickness-distinguished underline for the focused segment).
Applies, in order, to a pristine fixes_4 checkout:
  1. lcl/lmessages.pp
       - LM_IM_QUERY_CARET_POS, LM_IM_SET_PREEDIT
       - TIMEPreeditSegment (Start/Length/Focused/Bold) / TIMEPreeditInfo /
         PIMEPreeditInfo types
  2. components/synedit/synedit.pp
       - TCustomSynEdit.WMImeQueryCaretPos
       - TCustomSynEdit.WMImeSetPreedit + lazily-created TPaintBox overlay
         that renders segment-highlighted preedit text (the focused
         segment gets a background highlight plus a thick, saturated-blue
         underline offset below the baseline, other segments get a plain
         thin underline), a cursor-tracking line, and hides/restores
         SynEdit's own caret while composing
  3. lcl/interfaces/qt5/cbindings/src/qevent_c.h + qevent_c.cpp
       - QInputMethodEvent attribute accessors (count/type/start/length/
         backgroundColor/bold), needed to read bunsetsu segmentation and
         cursor position - not exposed by upstream libQt5Pas at all
  4. lcl/interfaces/qt5/qt56.pas
       - Pascal external bindings for the above
  5. lcl/interfaces/qt5/qtwidgets.pas
       - SlotInputMethod: commit-string truncation fix, preedit-followup
         fix, dispatch of LM_IM_SET_PREEDIT (with parsed segment/cursor
         info) to LCLObject
       - SlotInputMethodQuery: answers Qt::ImCursorRectangle via
         LM_IM_QUERY_CARET_POS dispatch; Result stays False unless an
         answer was actually supplied (returning True unconditionally
         breaks IME activation - see in-code comment)

NOTE: this script only patches the Pascal/C++ *sources*. libQt5Pas.so
still needs to be rebuilt from cbindings/ after this runs (the Dockerfile
does this in the following RUN step), and Lazarus itself still needs to
be built with make bigide LCL_PLATFORM=qt5.
"""
import sys

import os as _os
# JPSupport-Qt: the Lazarus source tree to patch. Defaults to the current
# working directory (so "cd /path/to/your/lazarus-src && python3
# apply_jpsupport_patches.py" just works), but can be overridden via the
# LAZARUS_SRC_PATH environment variable if you'd rather run this script
# from elsewhere.
LAZARUS_SRC = _os.environ.get("LAZARUS_SRC_PATH", _os.getcwd())


def patch_lmessages():
    path = f"{LAZARUS_SRC}/lcl/lmessages.pp"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    old = """  LM_UNKNOWN        = LM_INTERFACELAST + 1;
  LM_IM_COMPOSITION = LM_USER + $FFF0; // gtk IM"""
    new = """  LM_UNKNOWN        = LM_INTERFACELAST + 1;
  LM_IM_COMPOSITION = LM_USER + $FFF0; // gtk IM
  // JPSupport (Qt5): caret/cursor rectangle query, used so that
  // TQtWidget.SlotInputMethodQuery (a generic LCL-layer handler that must
  // not depend on the SynEdit package) can ask a control - without knowing
  // its concrete type - for the screen rectangle where an input-method
  // candidate/preedit popup should be anchored. The control (e.g.
  // TCustomSynEdit) answers via a WMImeQueryCaretPos-style message handler.
  LM_IM_QUERY_CARET_POS = LM_USER + $FFEF;
  // JPSupport (Qt5): notifies a control of the current IME preedit
  // (composition-in-progress) string plus bunsetsu/segment and cursor
  // info, so the control can render it itself. This exists because
  // custom-painted controls (TSynEdit, backed by QLCLAbstractScrollArea)
  // do not receive Qt's own native preedit overlay painting. LParam
  // points at a TIMEPreeditInfo record (see below).
  LM_IM_SET_PREEDIT = LM_USER + $FFEE;
type
  // JPSupport (Qt5/SynEdit): describes one bunsetsu (segment) of an IME
  // preedit string, so a control can render segments differently (e.g.
  // the currently-focused segment highlighted, others just underlined).
  TIMEPreeditSegment = record
    Start, Length: Integer;
    Focused: Boolean;
    // True if the IME marked this segment's font as bold (currently
    // parsed but not used for rendering - the focused segment is instead
    // distinguished by a colored/thickened underline; kept in case a
    // future refinement wants font-weight info too).
    Bold: Boolean;
  end;
  // Fixed-size segment array (rather than a dynamic array) to keep the
  // LM_IM_SET_PREEDIT message payload a simple, self-contained record
  // that can be passed by pointer without lifetime/reference-counting
  // concerns across the message-dispatch boundary.
  TIMEPreeditInfo = record
    Text: WideString;
    SegmentCount: Integer;
    Segments: array[0..31] of TIMEPreeditSegment;
    // Cursor position within Text (0-based) and whether it should be
    // shown at all, from Qt's Cursor attribute (Length=0 means "hidden").
    CursorPos: Integer;
    CursorVisible: Boolean;
  end;
  PIMEPreeditInfo = ^TIMEPreeditInfo;
const
  // GTK IM Flags"""
    if content.count(old) != 1:
        print("ERROR (lmessages.pp): anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: lmessages.pp patched.")


def patch_synedit():
    path = f"{LAZARUS_SRC}/components/synedit/synedit.pp"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    old_decl = """    function CaretXPix: Integer; override;
    function CaretYPix: Integer; override;"""
    new_decl = """    function CaretXPix: Integer; override;
    function CaretYPix: Integer; override;
    // JPSupport (Qt5): answers a caret/cursor-rectangle query sent by
    // TQtWidget.SlotInputMethodQuery (lcl/interfaces/qt5/qtwidgets.pas).
    // TQtWidget is a generic LCL-layer class that must not depend on the
    // SynEdit package, so it cannot cast LCLObject to TCustomSynEdit and
    // read CaretXPix/CaretYPix directly; instead it dispatches this
    // message to whatever control has focus, and this handler (present
    // only on TCustomSynEdit) fills in the TRect passed via Message.LParam.
    procedure WMImeQueryCaretPos(var Message: TMessage); message LM_IM_QUERY_CARET_POS;
    // JPSupport (Qt5): receives the current IME preedit (composition,
    // with bunsetsu/segment and cursor info) from TQtWidget.SlotInputMethod,
    // so this control can render it itself (see LM_IM_SET_PREEDIT comment
    // in lmessages.pp for why this is necessary for a custom-painted
    // control like TSynEdit).
    procedure WMImeSetPreedit(var Message: TMessage); message LM_IM_SET_PREEDIT;"""
    if content.count(old_decl) != 1:
        print("ERROR (synedit.pp): CaretXPix/CaretYPix declaration anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_decl, new_decl, 1)

    old_priv_anchor = """  private
    procedure SetImeHandler(AValue: LazSynIme);
  protected
    // SynEdit takes ownership
    property ImeHandler: LazSynIme read FImeHandler write SetImeHandler;"""
    new_priv_anchor = """  private
    // JPSupport (Qt5): overlay box used to render the IME preedit
    // (composition-in-progress) string, with bunsetsu/segment highlight
    // and a cursor-tracking line, on top of the editor - since TSynEdit
    // is custom-painted and never receives Qt's native preedit rendering
    // (see LM_IM_SET_PREEDIT in lmessages.pp). Created lazily on first
    // use; never destroyed except with the editor itself.
    FJPSupportPreeditBox: TPaintBox;
    FJPSupportPreeditInfo: TIMEPreeditInfo;
    procedure JPSupportEnsurePreeditBox;
    procedure JPSupportPreeditBoxPaint(Sender: TObject);
    procedure SetImeHandler(AValue: LazSynIme);
  protected
    // SynEdit takes ownership
    property ImeHandler: LazSynIme read FImeHandler write SetImeHandler;"""
    if content.count(old_priv_anchor) != 1:
        print("ERROR (synedit.pp): private-section anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_priv_anchor, new_priv_anchor, 1)

    old_impl = """function TCustomSynEdit.CaretYPix: Integer;
var
  p: TPoint;
begin
  p := FCaret.ViewedLineCharPos;
  p.y := p.y - TopView + 1;
  Result := ScreenXYToPixels(p).Y;
end;"""
    new_impl = """function TCustomSynEdit.CaretYPix: Integer;
var
  p: TPoint;
begin
  p := FCaret.ViewedLineCharPos;
  p.y := p.y - TopView + 1;
  Result := ScreenXYToPixels(p).Y;
end;

procedure TCustomSynEdit.WMImeQueryCaretPos(var Message: TMessage);
var
  R: PRect;
begin
  R := PRect(Message.LParam);
  if R = nil then
    Exit;
  R^.Left := CaretXPix;
  R^.Top := CaretYPix;
  R^.Right := R^.Left + 2;
  R^.Bottom := R^.Top + LineHeight;
  Message.Result := 1;
end;

procedure TCustomSynEdit.JPSupportEnsurePreeditBox;
begin
  if FJPSupportPreeditBox <> nil then
    Exit;
  FJPSupportPreeditBox := TPaintBox.Create(Self);
  FJPSupportPreeditBox.Parent := Self;
  FJPSupportPreeditBox.Visible := False;
  FJPSupportPreeditBox.OnPaint := @JPSupportPreeditBoxPaint;
end;

procedure TCustomSynEdit.JPSupportPreeditBoxPaint(Sender: TObject);
var
  TextH: Integer;
  i, SegStart, SegLen, SegLeft, SegW: Integer;
  SegText: WideString;
  IsFocused: Boolean;
  CursorX: Integer;
const
  // JPSupport (Qt5): fallback highlight color for the currently-focused
  // bunsetsu (segment), used since Fcitx5/Mozc's own TextFormat
  // background is read but a consistent, theme-independent highlight is
  // preferable to whatever raw color Qt reports.
  clJPSupportFocusedSegment = $00D8B000; // BGR: a muted (pale) blue highlight
  // A more saturated blue than the pale highlight above, so the thick
  // underline is visually distinct from the highlight fill it sits on
  // top of (same color for both would make the underline invisible).
  clJPSupportFocusedUnderline = $00E08000; // BGR: a stronger, saturated blue
begin
  with FJPSupportPreeditBox.Canvas do
  begin
    Font := Self.Font;
    TextH := TextHeight('Wg');
    Brush.Color := Self.Color;
    Brush.Style := bsSolid;
    FillRect(ClipRect);
    SegLeft := 0;
    if FJPSupportPreeditInfo.SegmentCount = 0 then
    begin
      // No segment attributes at all (e.g. still in raw romaji-typing
      // stage, before Fcitx5/Mozc has started segmenting) - draw the
      // whole preedit string as one plain, underlined run.
      TextOut(0, 0, FJPSupportPreeditInfo.Text);
      Pen.Color := Font.Color;
      Line(0, TextH - 1, TextWidth(FJPSupportPreeditInfo.Text), TextH - 1);
    end
    else
    begin
      for i := 0 to FJPSupportPreeditInfo.SegmentCount - 1 do
      begin
        SegStart := FJPSupportPreeditInfo.Segments[i].Start;
        SegLen := FJPSupportPreeditInfo.Segments[i].Length;
        IsFocused := FJPSupportPreeditInfo.Segments[i].Focused;
        if (SegStart < 0) or (SegLen <= 0) or
           (SegStart + SegLen > Length(FJPSupportPreeditInfo.Text)) then
          Continue;
        SegText := Copy(FJPSupportPreeditInfo.Text, SegStart + 1, SegLen);
        Font.Style := Self.Font.Style;
        SegW := TextWidth(SegText);
        if IsFocused then
        begin
          Brush.Color := clJPSupportFocusedSegment;
          Brush.Style := bsSolid;
          // Leave the bottom few pixels of the highlight unfilled, so the
          // thick underline drawn below (in a more saturated color)
          // remains visible instead of blending into a same-toned fill.
          FillRect(Rect(SegLeft, 0, SegLeft + SegW, TextH - 3));
        end;
        Font.Color := Self.Font.Color;
        Brush.Style := bsClear;
        TextOut(SegLeft, 0, SegText);
        // JPSupport: underline for the currently-focused segment - drawn
        // as a filled rectangle (not a thick Pen line) so the extra
        // thickness extends only downward from the baseline instead of
        // bleeding symmetrically upward into the text, and in a
        // saturated accent color - matching the bold, clearly-offset,
        // colored underline convention seen in native GTK IME rendering
        // (e.g. Gedit + Fcitx5/Mozc). Other segments keep the plain,
        // thin, text-colored underline right at the baseline.
        if IsFocused then
        begin
          Brush.Color := clJPSupportFocusedUnderline;
          Brush.Style := bsSolid;
          FillRect(Rect(SegLeft, TextH - 2, SegLeft + SegW, TextH + 1));
          Brush.Style := bsClear;
        end
        else
        begin
          Pen.Color := Self.Font.Color;
          Pen.Width := 1;
          Line(SegLeft, TextH - 1, SegLeft + SegW, TextH - 1);
        end;
        Inc(SegLeft, SegW);
      end;
    end;
    // JPSupport: cursor position within the composing (preedit) text,
    // reported by Fcitx5/Mozc via Qt's Cursor attribute - moves as the
    // user adjusts bunsetsu (segment) boundaries with Shift+Left/Right.
    // A plain, slightly-thick line in the text color is enough since
    // SynEdit's own caret is hidden while composing (see WMImeSetPreedit)
    // and no longer visually competes with it.
    if FJPSupportPreeditInfo.CursorVisible and (FJPSupportPreeditInfo.CursorPos >= 0) and
       (FJPSupportPreeditInfo.CursorPos <= Length(FJPSupportPreeditInfo.Text)) then
    begin
      CursorX := TextWidth(Copy(FJPSupportPreeditInfo.Text, 1, FJPSupportPreeditInfo.CursorPos));
      Pen.Color := Font.Color;
      Pen.Width := 2;
      Line(CursorX, 0, CursorX, TextH);
      Pen.Width := 1;
    end;
  end;
end;

procedure TCustomSynEdit.WMImeSetPreedit(var Message: TMessage);
var
  Info: PIMEPreeditInfo;
  TextW, TextH: Integer;
begin
  Info := PIMEPreeditInfo(Message.LParam);
  if Info = nil then
    Exit;
  JPSupportEnsurePreeditBox;
  FJPSupportPreeditInfo := Info^;
  if Length(FJPSupportPreeditInfo.Text) = 0 then
  begin
    FJPSupportPreeditBox.Visible := False;
    // JPSupport: composition ended - restore SynEdit's own (blinking)
    // caret, which we hid while composing (see below).
    ScreenCaret.Visible := not (eoNoCaret in Options);
  end
  else
  begin
    // JPSupport: while composing, hide SynEdit's real caret. Otherwise it
    // keeps blinking, unmoving, at the position where composition
    // started, which looks like "the cursor is stuck" even though our
    // own preedit-internal cursor line (above) correctly follows
    // bunsetsu/segment navigation - the two carets were simply competing
    // for attention, and the real one (blinking) is far more prominent.
    ScreenCaret.Visible := False;
    Canvas.Font := Self.Font;
    TextW := Canvas.TextWidth(FJPSupportPreeditInfo.Text);
    TextH := Canvas.TextHeight(FJPSupportPreeditInfo.Text);
    // +2 extra pixels of height to fit the focused-segment underline,
    // which is drawn a couple pixels below the text baseline.
    FJPSupportPreeditBox.SetBounds(CaretXPix, CaretYPix, TextW + 2, TextH + 3);
    FJPSupportPreeditBox.Visible := True;
    FJPSupportPreeditBox.Invalidate;
  end;
  Message.Result := 1; // acknowledge: this control handles preedit itself
end;"""
    if content.count(old_impl) != 1:
        print("ERROR (synedit.pp): CaretYPix implementation anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_impl, new_impl, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: synedit.pp patched.")


def patch_qevent_c():
    h_path = f"{LAZARUS_SRC}/lcl/interfaces/qt5/cbindings/src/qevent_c.h"
    cpp_path = f"{LAZARUS_SRC}/lcl/interfaces/qt5/cbindings/src/qevent_c.cpp"

    with open(h_path, "r", encoding="utf-8") as f:
        h = f.read()
    old_h = "C_EXPORT QInputMethodEventH QInputMethodEvent_Create3(const QInputMethodEventH other);"
    new_h = """C_EXPORT QInputMethodEventH QInputMethodEvent_Create3(const QInputMethodEventH other);
// JPSupport (Qt5/SynEdit): segment (bunsetsu) info for the preedit string.
// Qt exposes this via QInputMethodEvent::attributes() (a QList<Attribute>),
// which was not previously wrapped at all. Each Attribute has a type
// (TextFormat / Cursor / Selection / Language / Ruby), a start/length
// range into the preedit string, and a QVariant value. For TextFormat,
// the value is a QTextFormat whose background() distinguishes the
// currently-focused segment (opaque highlight color) from other,
// already-converted segments (usually no background, or a paler one) -
// this is what IMEs like Fcitx5/Mozc use to show bunsetsu segmentation.
C_EXPORT int QInputMethodEvent_attributeCount(QInputMethodEventH handle);
C_EXPORT int QInputMethodEvent_attributeType(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeStart(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeLength(QInputMethodEventH handle, int index);
// Returns the TextFormat attribute's background color as 0xAARRGGBB, or
// -1 if this attribute has no background set (e.g. not a TextFormat
// attribute, or a TextFormat with no background brush).
C_EXPORT int QInputMethodEvent_attributeBackgroundColor(QInputMethodEventH handle, int index);
// Returns 1 if the TextFormat attribute's font is bold, 0 if not, -1 if
// not applicable. Parsed and available, though the focused segment is
// currently distinguished visually by underline color/thickness instead.
C_EXPORT int QInputMethodEvent_attributeBold(QInputMethodEventH handle, int index);"""
    if h.count(old_h) != 1:
        print("ERROR (qevent_c.h): anchor not found exactly once.")
        sys.exit(1)
    h = h.replace(old_h, new_h, 1)
    with open(h_path, "w", encoding="utf-8") as f:
        f.write(h)
    print("OK: qevent_c.h patched.")

    with open(cpp_path, "r", encoding="utf-8") as f:
        cpp = f.read()
    old_cpp = """QInputMethodEventH QInputMethodEvent_Create3(const QInputMethodEventH other)
{
	return (QInputMethodEventH) new QInputMethodEvent(*(const QInputMethodEvent*)other);
}"""
    new_cpp = """QInputMethodEventH QInputMethodEvent_Create3(const QInputMethodEventH other)
{
	return (QInputMethodEventH) new QInputMethodEvent(*(const QInputMethodEvent*)other);
}

int QInputMethodEvent_attributeCount(QInputMethodEventH handle)
{
	return ((QInputMethodEvent *)handle)->attributes().count();
}

int QInputMethodEvent_attributeType(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	return (int) attrs.at(index).type;
}

int QInputMethodEvent_attributeStart(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return 0;
	return attrs.at(index).start;
}

int QInputMethodEvent_attributeLength(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return 0;
	return attrs.at(index).length;
}

int QInputMethodEvent_attributeBackgroundColor(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	const QInputMethodEvent::Attribute &attr = attrs.at(index);
	if (attr.type != QInputMethodEvent::TextFormat)
		return -1;
	QTextFormat fmt = attr.value.value<QTextFormat>();
	QBrush bg = fmt.background();
	if (bg.style() == Qt::NoBrush)
		return -1;
	QColor c = bg.color();
	return (c.alpha() << 24) | (c.red() << 16) | (c.green() << 8) | c.blue();
}

int QInputMethodEvent_attributeBold(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	const QInputMethodEvent::Attribute &attr = attrs.at(index);
	if (attr.type != QInputMethodEvent::TextFormat)
		return -1;
	QTextFormat fmt = attr.value.value<QTextFormat>();
	QTextCharFormat cfmt = fmt.toCharFormat();
	return cfmt.font().bold() ? 1 : 0;
}"""
    if cpp.count(old_cpp) != 1:
        print("ERROR (qevent_c.cpp): anchor not found exactly once.")
        sys.exit(1)
    cpp = cpp.replace(old_cpp, new_cpp, 1)
    with open(cpp_path, "w", encoding="utf-8") as f:
        f.write(cpp)
    print("OK: qevent_c.cpp patched.")


def patch_qt56():
    path = f"{LAZARUS_SRC}/lcl/interfaces/qt5/qt56.pas"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    old = "function QInputMethodEvent_Create(other: QInputMethodEventH): QInputMethodEventH; cdecl; external Qt5PasLib name 'QInputMethodEvent_Create3';"
    new = """function QInputMethodEvent_Create(other: QInputMethodEventH): QInputMethodEventH; cdecl; external Qt5PasLib name 'QInputMethodEvent_Create3';
// JPSupport (Qt5/SynEdit): segment (bunsetsu) attribute accessors. See the
// comment above the C++ declarations in cbindings/src/qevent_c.h for
// details on what each attribute represents.
function QInputMethodEvent_attributeCount(handle: QInputMethodEventH): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeCount';
function QInputMethodEvent_attributeType(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeType';
function QInputMethodEvent_attributeStart(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeStart';
function QInputMethodEvent_attributeLength(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeLength';
function QInputMethodEvent_attributeBackgroundColor(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeBackgroundColor';
function QInputMethodEvent_attributeBold(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt5PasLib name 'QInputMethodEvent_attributeBold';"""
    if content.count(old) != 1:
        print("ERROR (qt56.pas): anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: qt56.pas patched.")


def patch_qtwidgets():
    path = f"{LAZARUS_SRC}/lcl/interfaces/qt5/qtwidgets.pas"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    old_method = """function TQtWidget.SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  InputEvent: QInputMethodEventH;
  WStr: WideString;
  UnicodeChar: Cardinal;
  UnicodeOutLen: integer;
  KeyEvent: QKeyEventH;
begin
  Result := True;
  if not (QEvent_type(Event) = QEventInputMethod) then Exit;
  {$ifdef VerboseQt}
    DebugLn('TQtWidget.SlotInputMethod ', dbgsname(LCLObject));
  {$endif}
  InputEvent := QInputMethodEventH(Event);
  QInputMethodEvent_commitString(InputEvent, @WStr);
  UnicodeChar := UTF8CodepointToUnicode(PChar(WStr), UnicodeOutLen);
  {$IFDEF VerboseQtKeys}
  writeln('> TQtWidget.SlotInputMethod ',dbgsname(LCLObject),' event=QEventInputMethod:');
  writeln('   commmitString ',WStr,' len ',length(WStr),' UnicodeChar ',UnicodeChar,
    ' UnicodeLen ',UnicodeOutLen);
  writeln('   sending QEventKeyPress');
  {$ENDIF}

  KeyEvent := QKeyEvent_create(QEventKeyPress, PtrInt(UnicodeChar), QGUIApplication_keyboardModifiers, @WStr, False, 1);
  try
    // do not send it to queue, just pass it to SlotKey
    Result := SlotKey(Sender, KeyEvent);
  finally
    QKeyEvent_destroy(KeyEvent);
  end;
  {$IFDEF VerboseQtKeys}
  writeln('< TQtWidget.SlotInputMethod End: ',dbgsname(LCLObject),' event=QEventInputMethod, sent QEventKeyPress');
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotMouse"""

    new_method = """function TQtWidget.SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  InputEvent: QInputMethodEventH;
  WStr: WideString;
  PreeditStr: WideString;
  CharStr: WideString;
  UnicodeChar: Cardinal;
  KeyEvent: QKeyEventH;
  i: Integer;
  PreeditMsg: TLMessage;
  PreeditInfo: TIMEPreeditInfo;
  AttrCount, AttrIdx: Integer;
begin
  Result := True;
  if not (QEvent_type(Event) = QEventInputMethod) then Exit;
  {$ifdef VerboseQt}
    DebugLn('TQtWidget.SlotInputMethod ', dbgsname(LCLObject));
  {$endif}
  InputEvent := QInputMethodEventH(Event);
  QInputMethodEvent_commitString(InputEvent, @WStr);
  if Length(WStr) = 0 then
  begin
    QInputMethodEvent_preeditString(InputEvent, @PreeditStr);
    {$IFDEF VerboseQtKeys}
    DebugLn('JPSupport DEBUG: SlotInputMethod preeditString=[' + PreeditStr +
      '] len=' + IntToStr(Length(PreeditStr)) +
      ' widget=' + dbgsname(LCLObject));
    {$ENDIF}
    // JPSupport (Qt5/SynEdit): try to let the control render the preedit
    // string itself (needed for custom-painted controls such as TSynEdit,
    // which never receive Qt's native preedit overlay - see
    // LM_IM_SET_PREEDIT comment in lmessages.pp). If the control does not
    // recognize this message (e.g. TEdit/QLineEdit, which already paints
    // its own native preedit), Msg.Result stays 0 and we fall back to the
    // previous behavior (Result:=False, let Qt handle it natively).
    Result := False;
    if (LCLObject <> nil) and (LCLObject is TControl) then
    begin
      FillChar(PreeditInfo, SizeOf(PreeditInfo), 0);
      PreeditInfo.Text := PreeditStr;
      PreeditInfo.CursorPos := -1;
      PreeditInfo.CursorVisible := False;
      // JPSupport (Qt5): read QInputMethodEvent::attributes() to find
      // bunsetsu (segment) boundaries and cursor position. TextFormat
      // attributes with a background color set are what Fcitx5/Mozc use
      // to mark the currently-focused segment; other TextFormat
      // attributes (no background) mark already-converted-but-not-
      // focused segments. The Cursor attribute gives the IME-reported
      // cursor position within the preedit text (Length=0 means hidden).
      // Selection/Language/Ruby attributes are ignored here.
      AttrCount := QInputMethodEvent_attributeCount(InputEvent);
      for AttrIdx := 0 to AttrCount - 1 do
      begin
        if QInputMethodEvent_attributeType(InputEvent, AttrIdx) = Ord(QInputMethodEventCursor) then
        begin
          PreeditInfo.CursorPos := QInputMethodEvent_attributeStart(InputEvent, AttrIdx);
          PreeditInfo.CursorVisible := QInputMethodEvent_attributeLength(InputEvent, AttrIdx) <> 0;
          Continue;
        end;
        if QInputMethodEvent_attributeType(InputEvent, AttrIdx) <> Ord(QInputMethodEventTextFormat) then
          Continue;
        if PreeditInfo.SegmentCount > High(PreeditInfo.Segments) then
          Break;
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Start := QInputMethodEvent_attributeStart(InputEvent, AttrIdx);
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Length := QInputMethodEvent_attributeLength(InputEvent, AttrIdx);
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Focused :=
          QInputMethodEvent_attributeBackgroundColor(InputEvent, AttrIdx) <> -1;
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Bold :=
          QInputMethodEvent_attributeBold(InputEvent, AttrIdx) = 1;
        Inc(PreeditInfo.SegmentCount);
      end;
      FillChar(PreeditMsg, SizeOf(PreeditMsg), 0);
      PreeditMsg.Msg := LM_IM_SET_PREEDIT;
      PreeditMsg.LParam := PtrInt(@PreeditInfo);
      PreeditMsg.Result := 0;
      TControl(LCLObject).Dispatch(PreeditMsg);
      if PreeditMsg.Result <> 0 then
        Result := True; // control painted the preedit itself; don't let Qt also try
    end;
    Exit;
  end;

  {$IFDEF VerboseQtKeys}
  writeln('> TQtWidget.SlotInputMethod ',dbgsname(LCLObject),' event=QEventInputMethod:');
  writeln('   commmitString ',WStr,' len ',length(WStr));
  writeln('   sending ',length(WStr),' x QEventKeyPress');
  {$ENDIF}

  // NOTE (JPSupport patch): the original code passed the *entire*
  // (possibly multi-character, e.g. CJK) commit string through
  // UTF8CodepointToUnicode(PChar(WStr), ...) - but WStr is a WideString
  // (UTF-16), not UTF-8. Decoding UTF-16 bytes as if they were UTF-8
  // silently truncated any commit string longer than a couple of
  // characters (only the first, mis-decoded "codepoint" survived).
  // Fix: iterate over the real UTF-16 code units of WStr and send one
  // synthetic key press per character, so multi-character commits
  // (as produced by Fcitx5/Mozc for Japanese, Chinese, Korean, etc.)
  // are no longer dropped. Astral-plane characters (surrogate pairs)
  // are not specially handled here, which is an acceptable limitation
  // for this fix's scope (CJK BMP input).
  for i := 1 to Length(WStr) do
  begin
    CharStr := WStr[i];
    UnicodeChar := Word(WStr[i]);
    KeyEvent := QKeyEvent_create(QEventKeyPress, PtrInt(UnicodeChar), QGUIApplication_keyboardModifiers, @CharStr, False, 1);
    try
      // do not send it to queue, just pass it to SlotKey
      Result := SlotKey(Sender, KeyEvent);
    finally
      QKeyEvent_destroy(KeyEvent);
    end;
  end;
  {$IFDEF VerboseQtKeys}
  writeln('< TQtWidget.SlotInputMethod End: ',dbgsname(LCLObject),' event=QEventInputMethod, sent ',length(WStr),' x QEventKeyPress');
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotInputMethodQuery
  Params:  Sender - the QObject the event was sent to
           Event  - QInputMethodQueryEvent
  Returns: True only if we actually supplied an answer

  JPSupport (Qt5 / SynEdit): Qt asks widgets, via QEvent::InputMethodQuery,
  where the input-method candidate/preedit popup should be positioned
  (Qt::ImCursorRectangle). TQtWidget (this generic LCL layer) has no
  built-in notion of "caret position" for custom-painted controls such as
  TSynEdit (LCL's standard Win32-style caret API - QtCaret.pas /
  GetCaretPos/SetCaretPos - is never called by SynEdit, since SynEdit paints
  its own caret). So we special-case TCustomSynEdit here (indirectly, via a
  generic LM_IM_QUERY_CARET_POS message dispatch so this file need not
  depend on the SynEdit package) and read its CaretXPix/CaretYPix (already
  client-area/local-coordinate based) to answer the query with a real,
  cursor-following rectangle instead of Qt's fallback (which is why the
  candidate window was previously stuck at a fixed position near the
  bottom-center of the editor).

  IMPORTANT: a single QInputMethodQueryEvent can request several different
  pieces of information at once (Qt::ImEnabled, ImHints, ImCursorRectangle,
  ImSurroundingText, etc.) and is sent very frequently - far more often than
  just when a candidate popup needs positioning. Result must stay False
  unless we actually supplied a value ourselves: returning True
  unconditionally tells Qt "fully handled", which suppresses Qt's own
  default inputMethodQuery() handling for the *other* flags in the same
  request (notably Qt::ImEnabled) and breaks IME activation entirely
  (Ctrl+Space / Zenkaku-Hankaku stop working).
 ------------------------------------------------------------------------------}
function TQtWidget.SlotInputMethodQuery(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  QueryEvent: QInputMethodQueryEventH;
  Queries: QtInputMethodQueries;
  CursorRect: TRect;
  V: QVariantH;
  Msg: TLMessage;
begin
  Result := False;
  try
    QueryEvent := QInputMethodQueryEventH(Event);
    Queries := QInputMethodQueryEvent_queries(QueryEvent);
    if (Queries and QtImCursorRectangle) = 0 then
      Exit;
    if (LCLObject = nil) or not (LCLObject is TControl) then
      Exit;
    FillChar(CursorRect, SizeOf(CursorRect), 0);
    FillChar(Msg, SizeOf(Msg), 0);
    Msg.Msg := LM_IM_QUERY_CARET_POS;
    Msg.LParam := PtrInt(@CursorRect);
    Msg.Result := 0;
    // Dispatch is safe even if LCLObject has no handler for this message:
    // unhandled messages fall through to TObject's DefaultHandler, which
    // simply leaves Msg.Result at 0 and does nothing else.
    TControl(LCLObject).Dispatch(Msg);
    if Msg.Result = 0 then
      Exit; // control did not answer this query (not a TCustomSynEdit, e.g.)
    V := QVariant_Create(PRect(@CursorRect));
    try
      QInputMethodQueryEvent_setValue(QueryEvent, QtImCursorRectangle, V);
    finally
      QVariant_destroy(V);
    end;
    Result := True;
    {$IFDEF VerboseQtKeys}
    DebugLn('JPSupport DEBUG: SlotInputMethodQuery Rect=', dbgs(CursorRect),
      ' widget=', dbgsname(LCLObject));
    {$ENDIF}
  except
    on E: Exception do
    begin
      Result := False;
      DebugLn('JPSupport DEBUG: SlotInputMethodQuery EXCEPTION: ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotMouse"""

    if content.count(old_method) != 1:
        print("ERROR (qtwidgets.pas): SlotInputMethod block anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_method, new_method, 1)

    old_decl = "    function SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;"
    new_decl = ("    function SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;\n"
                "    function SlotInputMethodQuery(Sender: QObjectH; Event: QEventH): Boolean; cdecl;")
    if content.count(old_decl) != 1:
        print("ERROR (qtwidgets.pas): declaration anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_decl, new_decl, 1)

    old_case = """        QEventInputMethod:
          begin
            Result := SlotInputMethod(Sender, Event);
          end;"""
    new_case = """        QEventInputMethod:
          begin
            Result := SlotInputMethod(Sender, Event);
          end;
        QEventInputMethodQuery:
          begin
            Result := SlotInputMethodQuery(Sender, Event);
          end;"""
    if content.count(old_case) != 1:
        print("ERROR (qtwidgets.pas): case-branch anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_case, new_case, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: qtwidgets.pas patched.")




def patch_qevent_c_qt6():
    h_path = f"{LAZARUS_SRC}/lcl/interfaces/qt6/cbindings/src/qevent_c.h"
    cpp_path = f"{LAZARUS_SRC}/lcl/interfaces/qt6/cbindings/src/qevent_c.cpp"

    with open(h_path, "r", encoding="utf-8") as f:
        h = f.read()
    old_h = "C_EXPORT int QInputMethodEvent_replacementLength(QInputMethodEventH handle);"
    new_h = """C_EXPORT int QInputMethodEvent_replacementLength(QInputMethodEventH handle);
// JPSupport (Qt6/SynEdit): segment (bunsetsu) info for the preedit string.
// Mirrors the Qt5 cbindings extension of the same name - see the Qt5
// qevent_c.h comment (patch_qevent_c above) for the full rationale.
C_EXPORT int QInputMethodEvent_attributeCount(QInputMethodEventH handle);
C_EXPORT int QInputMethodEvent_attributeType(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeStart(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeLength(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeBackgroundColor(QInputMethodEventH handle, int index);
C_EXPORT int QInputMethodEvent_attributeBold(QInputMethodEventH handle, int index);"""
    if h.count(old_h) != 1:
        print("ERROR (qt6 qevent_c.h): anchor not found exactly once.")
        sys.exit(1)
    h = h.replace(old_h, new_h, 1)
    with open(h_path, "w", encoding="utf-8") as f:
        f.write(h)
    print("OK: qt6 qevent_c.h patched.")

    with open(cpp_path, "r", encoding="utf-8") as f:
        cpp = f.read()
    old_cpp = """int QInputMethodEvent_replacementLength(QInputMethodEventH handle)
{
	return (int) ((QInputMethodEvent *)handle)->replacementLength();
}"""
    new_cpp = """int QInputMethodEvent_replacementLength(QInputMethodEventH handle)
{
	return (int) ((QInputMethodEvent *)handle)->replacementLength();
}

int QInputMethodEvent_attributeCount(QInputMethodEventH handle)
{
	return ((QInputMethodEvent *)handle)->attributes().count();
}

int QInputMethodEvent_attributeType(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	return (int) attrs.at(index).type;
}

int QInputMethodEvent_attributeStart(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return 0;
	return attrs.at(index).start;
}

int QInputMethodEvent_attributeLength(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return 0;
	return attrs.at(index).length;
}

int QInputMethodEvent_attributeBackgroundColor(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	const QInputMethodEvent::Attribute &attr = attrs.at(index);
	if (attr.type != QInputMethodEvent::TextFormat)
		return -1;
	QTextFormat fmt = attr.value.value<QTextFormat>();
	QBrush bg = fmt.background();
	if (bg.style() == Qt::NoBrush)
		return -1;
	QColor c = bg.color();
	return (c.alpha() << 24) | (c.red() << 16) | (c.green() << 8) | c.blue();
}

int QInputMethodEvent_attributeBold(QInputMethodEventH handle, int index)
{
	const QList<QInputMethodEvent::Attribute> &attrs = ((QInputMethodEvent *)handle)->attributes();
	if (index < 0 || index >= attrs.count())
		return -1;
	const QInputMethodEvent::Attribute &attr = attrs.at(index);
	if (attr.type != QInputMethodEvent::TextFormat)
		return -1;
	QTextFormat fmt = attr.value.value<QTextFormat>();
	QTextCharFormat cfmt = fmt.toCharFormat();
	return cfmt.font().bold() ? 1 : 0;
}"""
    if cpp.count(old_cpp) != 1:
        print("ERROR (qt6 qevent_c.cpp): anchor not found exactly once.")
        sys.exit(1)
    cpp = cpp.replace(old_cpp, new_cpp, 1)
    with open(cpp_path, "w", encoding="utf-8") as f:
        f.write(cpp)
    print("OK: qt6 qevent_c.cpp patched.")


def patch_qt62():
    path = f"{LAZARUS_SRC}/lcl/interfaces/qt6/qt62.pas"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    old = "function QInputMethodEvent_replacementLength(handle: QInputMethodEventH): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_replacementLength';"
    new = """function QInputMethodEvent_replacementLength(handle: QInputMethodEventH): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_replacementLength';
// JPSupport (Qt6/SynEdit): segment (bunsetsu) attribute accessors. Mirrors
// the Qt5 binding of the same name in qt56.pas.
function QInputMethodEvent_attributeCount(handle: QInputMethodEventH): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeCount';
function QInputMethodEvent_attributeType(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeType';
function QInputMethodEvent_attributeStart(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeStart';
function QInputMethodEvent_attributeLength(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeLength';
function QInputMethodEvent_attributeBackgroundColor(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeBackgroundColor';
function QInputMethodEvent_attributeBold(handle: QInputMethodEventH; index: Integer): Integer; cdecl; external Qt6PasLib name 'QInputMethodEvent_attributeBold';"""
    if content.count(old) != 1:
        print("ERROR (qt62.pas): anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: qt62.pas patched.")


def patch_qtwidgets_qt6():
    path = f"{LAZARUS_SRC}/lcl/interfaces/qt6/qtwidgets.pas"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    old_method = """function TQtWidget.SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  InputEvent: QInputMethodEventH;
  WStr: WideString;
  UnicodeChar: Cardinal;
  UnicodeOutLen: integer;
  KeyEvent: QKeyEventH;
begin
  Result := True;
  if not (QEvent_type(Event) = QEventInputMethod) then Exit;
  {$ifdef VerboseQt}
    DebugLn('TQtWidget.SlotInputMethod ', dbgsname(LCLObject));
  {$endif}
  InputEvent := QInputMethodEventH(Event);
  QInputMethodEvent_commitString(InputEvent, @WStr);
  UnicodeChar := UTF8CodepointToUnicode(PChar(WStr), UnicodeOutLen);
  {$IFDEF VerboseQtKeys}
  writeln('> TQtWidget.SlotInputMethod ',dbgsname(LCLObject),' event=QEventInputMethod:');
  writeln('   commmitString ',WStr,' len ',length(WStr),' UnicodeChar ',UnicodeChar,
    ' UnicodeLen ',UnicodeOutLen);
  writeln('   sending QEventKeyPress');
  {$ENDIF}

  KeyEvent := QKeyEvent_create(QEventKeyPress, PtrInt(UnicodeChar), QGUIApplication_keyboardModifiers, @WStr, False, 1);
  try
    // do not send it to queue, just pass it to SlotKey
    Result := SlotKey(Sender, KeyEvent);
  finally
    QKeyEvent_destroy(KeyEvent);
  end;
  {$IFDEF VerboseQtKeys}
  writeln('< TQtWidget.SlotInputMethod End: ',dbgsname(LCLObject),' event=QEventInputMethod, sent QEventKeyPress');
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotMouse"""

    new_method = """function TQtWidget.SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  InputEvent: QInputMethodEventH;
  WStr: WideString;
  PreeditStr: WideString;
  CharStr: WideString;
  UnicodeChar: Cardinal;
  KeyEvent: QKeyEventH;
  i: Integer;
  PreeditMsg: TLMessage;
  PreeditInfo: TIMEPreeditInfo;
  AttrCount, AttrIdx: Integer;
begin
  Result := True;
  if not (QEvent_type(Event) = QEventInputMethod) then Exit;
  {$ifdef VerboseQt}
    DebugLn('TQtWidget.SlotInputMethod ', dbgsname(LCLObject));
  {$endif}
  InputEvent := QInputMethodEventH(Event);
  QInputMethodEvent_commitString(InputEvent, @WStr);
  if Length(WStr) = 0 then
  begin
    QInputMethodEvent_preeditString(InputEvent, @PreeditStr);
    {$IFDEF VerboseQtKeys}
    DebugLn('JPSupport DEBUG: SlotInputMethod preeditString=[' + PreeditStr +
      '] len=' + IntToStr(Length(PreeditStr)) +
      ' widget=' + dbgsname(LCLObject));
    {$ENDIF}
    // JPSupport (Qt6/SynEdit): try to let the control render the preedit
    // string itself (needed for custom-painted controls such as TSynEdit,
    // which never receive Qt's native preedit overlay - see
    // LM_IM_SET_PREEDIT comment in lmessages.pp). If the control does not
    // recognize this message (e.g. TEdit/QLineEdit, which already paints
    // its own native preedit), Msg.Result stays 0 and we fall back to the
    // previous behavior (Result:=False, let Qt handle it natively).
    Result := False;
    if (LCLObject <> nil) and (LCLObject is TControl) then
    begin
      FillChar(PreeditInfo, SizeOf(PreeditInfo), 0);
      PreeditInfo.Text := PreeditStr;
      PreeditInfo.CursorPos := -1;
      PreeditInfo.CursorVisible := False;
      // JPSupport (Qt6): mirrors the Qt5 SlotInputMethod implementation -
      // see comment there for details on what each attribute type
      // represents.
      AttrCount := QInputMethodEvent_attributeCount(InputEvent);
      for AttrIdx := 0 to AttrCount - 1 do
      begin
        if QInputMethodEvent_attributeType(InputEvent, AttrIdx) = Ord(QInputMethodEventCursor) then
        begin
          PreeditInfo.CursorPos := QInputMethodEvent_attributeStart(InputEvent, AttrIdx);
          PreeditInfo.CursorVisible := QInputMethodEvent_attributeLength(InputEvent, AttrIdx) <> 0;
          Continue;
        end;
        if QInputMethodEvent_attributeType(InputEvent, AttrIdx) <> Ord(QInputMethodEventTextFormat) then
          Continue;
        if PreeditInfo.SegmentCount > High(PreeditInfo.Segments) then
          Break;
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Start := QInputMethodEvent_attributeStart(InputEvent, AttrIdx);
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Length := QInputMethodEvent_attributeLength(InputEvent, AttrIdx);
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Focused :=
          QInputMethodEvent_attributeBackgroundColor(InputEvent, AttrIdx) <> -1;
        PreeditInfo.Segments[PreeditInfo.SegmentCount].Bold :=
          QInputMethodEvent_attributeBold(InputEvent, AttrIdx) = 1;
        Inc(PreeditInfo.SegmentCount);
      end;
      FillChar(PreeditMsg, SizeOf(PreeditMsg), 0);
      PreeditMsg.Msg := LM_IM_SET_PREEDIT;
      PreeditMsg.LParam := PtrInt(@PreeditInfo);
      PreeditMsg.Result := 0;
      TControl(LCLObject).Dispatch(PreeditMsg);
      if PreeditMsg.Result <> 0 then
        Result := True; // control painted the preedit itself; don't let Qt also try
    end;
    Exit;
  end;

  {$IFDEF VerboseQtKeys}
  writeln('> TQtWidget.SlotInputMethod ',dbgsname(LCLObject),' event=QEventInputMethod:');
  writeln('   commmitString ',WStr,' len ',length(WStr));
  writeln('   sending ',length(WStr),' x QEventKeyPress');
  {$ENDIF}

  // NOTE (JPSupport patch): the original code passed the *entire*
  // (possibly multi-character, e.g. CJK) commit string through
  // UTF8CodepointToUnicode(PChar(WStr), ...) - but WStr is a WideString
  // (UTF-16), not UTF-8. Decoding UTF-16 bytes as if they were UTF-8
  // silently truncated any commit string longer than a couple of
  // characters (only the first, mis-decoded "codepoint" survived).
  // Fix: iterate over the real UTF-16 code units of WStr and send one
  // synthetic key press per character, so multi-character commits
  // (as produced by Fcitx5/Mozc for Japanese, Chinese, Korean, etc.)
  // are no longer dropped. Astral-plane characters (surrogate pairs)
  // are not specially handled here, which is an acceptable limitation
  // for this fix's scope (CJK BMP input).
  for i := 1 to Length(WStr) do
  begin
    CharStr := WStr[i];
    UnicodeChar := Word(WStr[i]);
    KeyEvent := QKeyEvent_create(QEventKeyPress, PtrInt(UnicodeChar), QGUIApplication_keyboardModifiers, @CharStr, False, 1);
    try
      // do not send it to queue, just pass it to SlotKey
      Result := SlotKey(Sender, KeyEvent);
    finally
      QKeyEvent_destroy(KeyEvent);
    end;
  end;
  {$IFDEF VerboseQtKeys}
  writeln('< TQtWidget.SlotInputMethod End: ',dbgsname(LCLObject),' event=QEventInputMethod, sent ',length(WStr),' x QEventKeyPress');
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotInputMethodQuery
  Params:  Sender - the QObject the event was sent to
           Event  - QInputMethodQueryEvent
  Returns: True only if we actually supplied an answer

  JPSupport (Qt6 / SynEdit): mirrors the Qt5 SlotInputMethodQuery - see
  that implementation's comment (lcl/interfaces/qt5/qtwidgets.pas) for the
  full rationale.
 ------------------------------------------------------------------------------}
function TQtWidget.SlotInputMethodQuery(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  QueryEvent: QInputMethodQueryEventH;
  Queries: QtInputMethodQueries;
  CursorRect: TRect;
  V: QVariantH;
  Msg: TLMessage;
begin
  Result := False;
  try
    QueryEvent := QInputMethodQueryEventH(Event);
    Queries := QInputMethodQueryEvent_queries(QueryEvent);
    if (Queries and QtImCursorRectangle) = 0 then
      Exit;
    if (LCLObject = nil) or not (LCLObject is TControl) then
      Exit;
    FillChar(CursorRect, SizeOf(CursorRect), 0);
    FillChar(Msg, SizeOf(Msg), 0);
    Msg.Msg := LM_IM_QUERY_CARET_POS;
    Msg.LParam := PtrInt(@CursorRect);
    Msg.Result := 0;
    TControl(LCLObject).Dispatch(Msg);
    if Msg.Result = 0 then
      Exit;
    V := QVariant_Create(PRect(@CursorRect));
    try
      QInputMethodQueryEvent_setValue(QueryEvent, QtImCursorRectangle, V);
    finally
      QVariant_destroy(V);
    end;
    Result := True;
    {$IFDEF VerboseQtKeys}
    DebugLn('JPSupport DEBUG: SlotInputMethodQuery Rect=', dbgs(CursorRect),
      ' widget=', dbgsname(LCLObject));
    {$ENDIF}
  except
    on E: Exception do
    begin
      Result := False;
      DebugLn('JPSupport DEBUG: SlotInputMethodQuery EXCEPTION: ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

{------------------------------------------------------------------------------
  Function: TQtWidget.SlotMouse"""

    if content.count(old_method) != 1:
        print("ERROR (qt6 qtwidgets.pas): SlotInputMethod block anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_method, new_method, 1)

    old_decl = "    function SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;"
    new_decl = ("    function SlotInputMethod(Sender: QObjectH; Event: QEventH): Boolean; cdecl;\n"
                "    function SlotInputMethodQuery(Sender: QObjectH; Event: QEventH): Boolean; cdecl;")
    if content.count(old_decl) != 1:
        print("ERROR (qt6 qtwidgets.pas): declaration anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_decl, new_decl, 1)

    old_case = """        QEventInputMethod:
          begin
            Result := SlotInputMethod(Sender, Event);
          end;"""
    new_case = """        QEventInputMethod:
          begin
            Result := SlotInputMethod(Sender, Event);
          end;
        QEventInputMethodQuery:
          begin
            Result := SlotInputMethodQuery(Sender, Event);
          end;"""
    if content.count(old_case) != 1:
        print("ERROR (qt6 qtwidgets.pas): case-branch anchor not found exactly once.")
        sys.exit(1)
    content = content.replace(old_case, new_case, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: qt6 qtwidgets.pas patched.")


if __name__ == "__main__":
    # JPSupport: target selection so a single script can serve both the
    # Qt5-only and Qt6-only Dockerfiles without one platform's build
    # failing due to the other's (currently platform-specific-in-detail)
    # anchors. Usage: apply_jpsupport_patches.py [qt5|qt6|both]
    # Defaults to "both" for interactive/manual use.
    target = sys.argv[1] if len(sys.argv) > 1 else "both"
    if target not in ("qt5", "qt6", "both"):
        print(f"ERROR: unknown target '{target}' (expected qt5, qt6, or both).")
        sys.exit(1)

    # lmessages.pp and synedit.pp are platform-independent (shared by
    # Qt5 and Qt6 alike), so they are always applied regardless of target.
    patch_lmessages()
    patch_synedit()

    if target in ("qt5", "both"):
        patch_qevent_c()
        patch_qt56()
        patch_qtwidgets()

    if target in ("qt6", "both"):
        patch_qevent_c_qt6()
        patch_qt62()
        patch_qtwidgets_qt6()

    print(f"OK: all JPSupport patches ({target}) applied successfully.")
