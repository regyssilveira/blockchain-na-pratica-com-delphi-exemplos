program Chapter14.Environment;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  Blockchain.Primitives,
  Blockchain.Ethereum,
  Blockchain.LocalRpc;

procedure Run;
var
  Rpc: TLocalRpc;
  Output: TJSONObject;
  Value: TJSONValue;
  Client, Network, Height, Address, Balance, BlockHash: string;
  Port: Integer;
  Accounts: Integer;
  function CallString(const AMethod: string; AParameters: TJSONArray): string;
  var Response: TJSONValue;
  begin
    Response := Rpc.Call(AMethod, AParameters);
    try
      if not (Response is TJSONString) then
        raise EInvalidOp.Create('Expected string: ' + AMethod);
      Result := Response.Value;
    finally Response.Free; end;
  end;
  procedure Require(const ACondition: Boolean; const AMessage: string);
  begin
    if not ACondition then raise EInvalidOp.Create(AMessage);
  end;
begin
  if ParamCount <> 1 then
    raise EArgumentException.Create('Uso: Chapter14.Environment porta');
  Port := StrToInt(ParamStr(1));
  if (Port < 1) or (Port > 65535) then
    raise EArgumentException.Create('Porta invalida.');
  Rpc := TLocalRpc.Create(Port);
  try
    Client := CallString('web3_clientVersion', TJSONArray.Create);
    Network := CallString('eth_chainId', TJSONArray.Create);
    Height := CallString('eth_blockNumber', TJSONArray.Create);
    Require(Pos('anvil', LowerCase(Client)) > 0, 'Expected Anvil development client.');
    Require(Network = '0x7a69', 'Expected development chain 31337.');
    Require(Height = '0x0', 'Expected a fresh development chain.');
    Value := Rpc.Call('eth_accounts', TJSONArray.Create);
    try
      Require(Value is TJSONArray, 'Expected account array.');
      Accounts := TJSONArray(Value).Count;
      Require(Accounts = 0, 'Expected no node-managed signing accounts.');
    finally Value.Free; end;
    // Valor privado 1 publicado para teste; o no nao recebe a chave.
    Address := '0x' + BytesToLowerHex(AddressFromPublicKey(
      PublicKeyFromPrivateKey(DecodeHex(StringOfChar('0', 63) + '1'))));
    Balance := CallString('eth_getBalance', TJSONArray.Create(Address, 'latest'));
    Balance := TExactUInt256.FromRpcQuantity(Balance).ToDecimal;
    Require(Balance = '100000000000000000000', 'Expected funded test balance.');
    Value := Rpc.Call('eth_getBlockByNumber', TJSONArray.Create.Add('latest').Add(False));
    try
      Require(Value is TJSONObject, 'Expected latest block object.');
      Require(TJSONObject(Value).GetValue<string>('number') = Height, 'Block number mismatch.');
      BlockHash := TJSONObject(Value).GetValue<string>('hash');
      Require((Copy(BlockHash, 1, 2) = '0x') and
        (Length(DecodeHex(Copy(BlockHash, 3, MaxInt))) = 32), 'Expected 32-byte block hash.');
    finally Value.Free; end;
    Output := TJSONObject.Create;
    try
      Output.AddPair('passed', TJSONBool.Create(True));
      Output.AddPair('client', Client);
      Output.AddPair('chainId', Network);
      Output.AddPair('height', Height);
      Output.AddPair('nodeAccounts', TJSONNumber.Create(Accounts));
      Output.AddPair('fundedAddress', Address);
      Output.AddPair('balanceWei', Balance);
      Output.AddPair('latestBlockHash', BlockHash);
      Writeln(Output.ToJSON);
    finally Output.Free; end;
  finally Rpc.Free; end;
end;

begin
  try Run; except
    on Error: Exception do
    begin
      Writeln(ErrOutput, Error.ClassName, ': ', Error.Message);
      ExitCode := 1;
    end;
  end;
end.
