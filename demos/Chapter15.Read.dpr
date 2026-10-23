program Chapter15.Read;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, Blockchain.LocalRpc, Blockchain.Primitives;

procedure Run;
var
  Rpc: TLocalRpc;
  Value: TJSONValue;
  Port: Integer;
  ChainId: string;
begin
  if ParamCount <> 1 then raise EArgumentException.Create('Uso: Chapter15.Read porta');
  Port := StrToInt(ParamStr(1));
  if (Port < 1) or (Port > 65535) then raise EArgumentException.Create('Porta invalida.');
  Rpc := TLocalRpc.Create(Port);
  try
    Value := Rpc.Call('eth_chainId', TJSONArray.Create);
    try
      if not (Value is TJSONString) then raise ELocalRpcError.Create('Expected chain quantity.');
      ChainId := TExactUInt256.FromRpcQuantity(Value.Value).ToDecimal;
      if ChainId <> '31337' then raise ELocalRpcError.Create('Expected local chain 31337.');
      Writeln('{"chainId":"', ChainId, '"}');
    finally
      Value.Free;
    end;
  finally
    Rpc.Free;
  end;
end;

begin
  try Run; except on Error: Exception do
  begin Writeln(ErrOutput, Error.ClassName, ': ', Error.Message); System.ExitCode := 1; end; end;
end.
