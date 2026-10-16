program DocumentRegistry.Cli;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils,
  Blockchain.Primitives in '..\src\Blockchain.Primitives.pas',
  Blockchain.Ethereum in '..\src\Blockchain.Ethereum.pas',
  Blockchain.LocalRpc in '..\src\Blockchain.LocalRpc.pas',
  Blockchain.TransactionJournal in '..\src\Blockchain.TransactionJournal.pas',
  Blockchain.DocumentRegistry in '..\src\Blockchain.DocumentRegistry.pas';

procedure Run;
var
  Command, CheckpointPath: string;
  Artifact, Output: TJSONObject;
  Registry: TDocumentRegistry;
  Checkpoint: TTransactionCheckpoint;
  Submission: TLocalSubmission;
  Found: TDocumentRecord;
  Receipt: TJSONObject;
  Runtime, Key, QueryHash: TBytes;
  Rpc: TLocalRpc;
  Value: TJSONValue;
  Port, TimeoutMs: Integer;
  procedure RequireCount(const AMinimum, AMaximum: Integer);
  begin
    if (ParamCount < AMinimum) or (ParamCount > AMaximum) then
      raise EArgumentException.Create('Argumentos invalidos. Consulte o roteiro de reproducao.');
  end;
  procedure LoadContext;
  begin
    CheckpointPath := ParamStr(2);
    Checkpoint := TTransactionCheckpoint.Load(CheckpointPath);
    if (Checkpoint.ChainId <> '31337') or
      (Checkpoint.RuntimeHex <> '0x' + BytesToLowerHex(Runtime)) then
      raise EArgumentException.Create('Configuracao preservada difere do artefato/rede esperados.');
    Registry := TDocumentRegistry.Create(Checkpoint.Port, TExactUInt256.FromDecimal('31337'), Runtime);
    Registry.JournalPath := CheckpointPath;
  end;
begin
  if ParamCount = 0 then raise EArgumentException.Create('Comandos: hash, deploy, register, wait, query, verify, mine.');
  Command := ParamStr(1);
  if Command = 'hash' then
  begin
    RequireCount(2, 2);
    Writeln(Sha256File(ParamStr(2)));
    Exit;
  end;
  if Command = 'mine' then
  begin
    RequireCount(2, 2);
    Port := StrToInt(ParamStr(2));
    if (Port < 1) or (Port > 65535) then raise EArgumentException.Create('Porta invalida.');
    Rpc := TLocalRpc.Create(Port);
    try
      Value := Rpc.Call('evm_mine', TJSONArray.Create);
      Value.Free;
      Writeln('Bloco minerado no Anvil local.');
    finally Rpc.Free; end;
    Exit;
  end;
  Artifact := TJSONObject.ParseJSONValue(TFile.ReadAllText('build\contract\DocumentRegistry.json', TEncoding.UTF8)) as TJSONObject;
  Registry := nil;
  Output := TJSONObject.Create;
  try
    if not Assigned(Artifact) then raise EArgumentException.Create('Artefato ausente ou invalido.');
    Runtime := DecodeHex(Artifact.GetValue<string>('runtimeBytecode'));
    // Chave privada de teste publicamente conhecida, exclusiva desta rede local.
    Key := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
    if Command = 'deploy' then
    begin
      RequireCount(3, 3);
      Port := StrToInt(ParamStr(3));
      if (Port < 1) or (Port > 65535) then raise EArgumentException.Create('Porta invalida.');
      Registry := TDocumentRegistry.Create(Port, TExactUInt256.FromDecimal('31337'), Runtime);
      Registry.JournalPath := ParamStr(2);
      Submission := Registry.Deploy(DecodeHex(Artifact.GetValue<string>('creationBytecode')), Key);
      Output.AddPair('state', 'submitted');
      Output.AddPair('hash', Submission.Hash);
    end
    else if Command = 'register' then
    begin
      RequireCount(4, 4);
      LoadContext;
      if Checkpoint.State <> 'succeeded' then raise EArgumentException.Create('Confirme a implantacao antes de registrar.');
      Registry.Attach(Checkpoint.ContractAddress);
      Registry.JournalPath := ParamStr(4);
      Submission := Registry.RegisterFile(ParamStr(3), Key);
      Output.AddPair('state', 'submitted');
      Output.AddPair('hash', Submission.Hash);
    end
    else if Command = 'wait' then
    begin
      RequireCount(2, 3);
      LoadContext;
      if ParamCount = 3 then TimeoutMs := StrToInt(ParamStr(3)) else TimeoutMs := 30000;
      if (TimeoutMs < 1) or (TimeoutMs > 30000) then raise EArgumentException.Create('Prazo deve estar entre 1 e 30000 ms.');
      Receipt := Registry.AwaitReceipt(Checkpoint.Hash, TimeoutMs, 1000);
      try
        Checkpoint := TTransactionCheckpoint.Load(CheckpointPath);
        Output.AddPair('state', Checkpoint.State);
        Output.AddPair('hash', Checkpoint.Hash);
        if not Assigned(Receipt) then System.ExitCode := 2
        else
        begin
          Output.AddPair('receipt', Receipt.Clone as TJSONValue);
          if Checkpoint.State = 'reverted' then System.ExitCode := 3;
          TFile.WriteAllText(CheckpointPath + '.receipt.json', Receipt.ToJSON, TEncoding.UTF8);
        end;
      finally Receipt.Free; end;
    end
    else if (Command = 'query') or (Command = 'verify') then
    begin
      if Command = 'verify' then RequireCount(3, 3) else RequireCount(2, 2);
      LoadContext;
      Registry.Attach(Checkpoint.ContractAddress);
      if Command = 'verify' then QueryHash := ParseDocumentHash(Sha256File(ParamStr(3)))
      else QueryHash := ParseDocumentHash(Checkpoint.DocumentHash);
      Found := Registry.Lookup(DecodeHex(Checkpoint.Account), QueryHash);
      if Found.Exists and (BytesToLowerHex(QueryHash) = Checkpoint.DocumentHash) and (Checkpoint.BlockNumber <> '') and
        (Found.BlockNumber.ToDecimal <> Checkpoint.BlockNumber) then
        raise ELocalRpcError.Create('Bloco consultado difere do recibo preservado.');
      Output.AddPair('found', TJSONBool.Create(Found.Exists));
      Output.AddPair('blockNumber', Found.BlockNumber.ToDecimal);
      Output.AddPair('contractAddress', Checkpoint.ContractAddress);
      Output.AddPair('documentSha256', BytesToLowerHex(QueryHash));
      Output.AddPair('matchesCheckpointDocument', TJSONBool.Create(BytesToLowerHex(QueryHash) = Checkpoint.DocumentHash));
      Rpc := TLocalRpc.Create(Checkpoint.Port);
      try
        Value := Rpc.Call('eth_getTransactionCount', TJSONArray.Create(Checkpoint.Account, 'latest'));
        try Output.AddPair('nonce', Value.Clone as TJSONValue); finally Value.Free; end;
      finally Rpc.Free; end;
      TFile.WriteAllText(CheckpointPath + '.query.json', Output.ToJSON, TEncoding.UTF8);
      if not Found.Exists then System.ExitCode := 4;
    end
    else raise EArgumentException.Create('Comando desconhecido.');
    Writeln(Output.ToJSON);
  finally
    Output.Free;
    Registry.Free;
    Artifact.Free;
  end;
end;

begin
  try Run; except
    on Error: Exception do
    begin
      Writeln(Error.ClassName, ': ', Error.Message);
      Writeln('Se um envio foi tentado, preserve o checkpoint e consulte o hash; nao reenvie automaticamente.');
      System.ExitCode := 1;
    end;
  end;
end.
