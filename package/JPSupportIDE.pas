{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit JPSupportIDE;

{$warn 5023 off : no warning about unused units}
interface

uses
  JPSupportIDEMain, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('JPSupportIDEMain', @JPSupportIDEMain.Register);
end;

initialization
  RegisterPackage('JPSupportIDE', @Register);
end.
