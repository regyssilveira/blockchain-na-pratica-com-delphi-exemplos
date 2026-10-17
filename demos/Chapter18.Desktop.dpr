program Chapter18.Desktop;

uses System.SysUtils, Vcl.Forms,
  Blockchain.RegistryForm in '..\src\Blockchain.RegistryForm.pas',
  Blockchain.RegistryWorkflow in '..\src\Blockchain.RegistryWorkflow.pas';

var MainForm: TRegistryForm; Port: Integer;
begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Port := 19345;
  if ParamCount > 0 then Port := StrToInt(ParamStr(1));
  if (Port < 1024) or (Port > 65535) then raise EArgumentException.Create('Porta local invalida.');
  if (ParamCount <> 0) and (ParamCount <> 1) and (ParamCount <> 3) then
    raise EArgumentException.Create('Uso: Chapter18.Desktop [porta] [pasta-autoteste implantacao-pendente]');
  if ParamCount = 3 then Application.ShowMainForm := False;
  Application.CreateForm(TRegistryForm, MainForm);
  if ParamCount = 3 then MainForm.Configure(Port, ParamStr(2), ParamStr(3))
  else MainForm.Configure(Port, '', '');
  Application.Run;
end.
