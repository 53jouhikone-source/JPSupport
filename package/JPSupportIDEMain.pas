// 0005
unit JPSupportIDEMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  SrcEditorIntf,
  SynEdit,
  JPSupportAdapter;

type
  TJPSupportIDEHook = class
  private
    FAdapter      : TJPSupportAdapter;
    FCurrentEditor: TCustomSynEdit;
  public
    constructor Create;
    destructor Destroy; override;
    procedure OnActiveEditorChanged(Sender: TObject);
  end;

procedure Register;

implementation

var
  GHook: TJPSupportIDEHook = nil;

constructor TJPSupportIDEHook.Create;
begin
  inherited Create;
  FAdapter       := TJPSupportAdapter.Create;
  FCurrentEditor := nil;
end;

destructor TJPSupportIDEHook.Destroy;
begin
  FAdapter.Detach;
  FreeAndNil(FAdapter);
  inherited Destroy;
end;

procedure TJPSupportIDEHook.OnActiveEditorChanged(Sender: TObject);
var
  SrcEdit: TSourceEditorInterface;
  Editor : TCustomSynEdit;
begin
  SrcEdit := SourceEditorManagerIntf.ActiveEditor;
  if SrcEdit = nil then
  begin
    FAdapter.DoExit;
    FCurrentEditor := nil;
    Exit;
  end;
  Editor := TCustomSynEdit(SrcEdit.EditorControl);
  if Editor = nil then Exit;
  if Editor = FCurrentEditor then Exit;
  WriteLn('JPSupport: Editor changed, attaching Handle=', PtrUInt(Editor.Handle));
  if Editor.Parent <> nil then
    WriteLn('JPSupport: Parent Handle=', PtrUInt(Editor.Parent.Handle))
  else
    WriteLn('JPSupport: Parent is nil');
  Flush(Output);
  FAdapter.DoExit;
  FAdapter.Detach;
  FCurrentEditor := Editor;
  FAdapter.Attach(Editor);
  FAdapter.DoEnter;
  WriteLn('JPSupport: Attach done');
  Flush(Output);
end;

procedure Register;
begin
  GHook := TJPSupportIDEHook.Create;
  if SourceEditorManagerIntf <> nil then
    SourceEditorManagerIntf.RegisterChangeEvent(
      semEditorActivate, @GHook.OnActiveEditorChanged);
end;

finalization
  if GHook <> nil then
    FreeAndNil(GHook);

end.
