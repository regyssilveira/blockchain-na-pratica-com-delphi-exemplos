program Chapter19.Security;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils,
  Blockchain.LocalKeyProtection in '..\src\Blockchain.LocalKeyProtection.pas',
  Blockchain.TrackingAudit in '..\src\Blockchain.TrackingAudit.pas',
  Blockchain.Ethereum, Blockchain.Primitives, Blockchain.TransactionJournal;

function PublishedKey: TBytes;
begin
  // Chave publicamente conhecida. Nunca substitua por chave real neste exercicio.
  Result := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
end;

function ExpectedAccount: TBytes;
begin
  Result := AddressFromPublicKey(PublicKeyFromPrivateKey(PublishedKey));
end;

function OfflineCheckpoint: TTransactionCheckpoint;
var Transaction: TType2Transaction; Raw, Key: TBytes;
begin
  Key := PublishedKey;
  try
    Transaction := Default(TType2Transaction);
    Transaction.ChainId := TExactUInt256.FromDecimal('31337');
    Transaction.Nonce := TExactUInt256.FromDecimal('0');
    Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('1000000000');
    Transaction.MaxFeePerGas := TExactUInt256.FromDecimal('3000000000');
    Transaction.GasLimit := TExactUInt256.FromDecimal('21000');
    Transaction.Destination := DecodeHex(StringOfChar('0', 40));
    Transaction.Amount := TExactUInt256.FromDecimal('0');
    Raw := Transaction.SignedEnvelope(SignDigest(Transaction.SigningHash, Key));
    Result := Default(TTransactionCheckpoint);
    Result.Port := 19345;
    Result.ChainId := '31337';
    Result.RuntimeHex := '0x00';
    Result.Account := '0x' + BytesToLowerHex(ExpectedAccount);
    Result.DocumentHash := Sha256Bytes(TEncoding.UTF8.GetBytes('offline document fixture'));
    Result.Hash := '0x' + BytesToLowerHex(Keccak256(Raw));
    Result.RawHex := '0x' + BytesToLowerHex(Raw);
    Result.State := 'unknown';
    Result.Diagnostic := 'OFFLINE-FIXTURE-DO-NOT-LOG. No node was contacted.';
  finally TLocalKeyProtection.ClearOwned(Key); end;
end;

procedure Run;
var
  Command, Path, ProtectedPath, CheckpointPath: string;
  Key, ProtectedBytes, Recovered: TBytes;
  Checkpoint: TTransactionCheckpoint;
  Output: TJSONObject;
begin
  if ParamCount <> 2 then
    raise EArgumentException.Create('Commands: prepare folder; check-key file; audit checkpoint.');
  Command := ParamStr(1);
  Path := TPath.GetFullPath(ParamStr(2));
  Output := nil;
  try
    if Command = 'prepare' then
    begin
      TDirectory.CreateDirectory(Path);
      ProtectedPath := TPath.Combine(Path, 'published-test-key.dpapi');
      CheckpointPath := TPath.Combine(Path, 'offline-checkpoint.json');
      if TFile.Exists(CheckpointPath) then
        raise EArgumentException.Create('Use a new output directory.');
      Key := PublishedKey;
      try
        ProtectedBytes := TLocalKeyProtection.Protect(Key);
        TLocalKeyProtection.SaveNew(ProtectedPath, ProtectedBytes);
      finally TLocalKeyProtection.ClearOwned(Key); end;
      Checkpoint := OfflineCheckpoint;
      Checkpoint.Save(CheckpointPath);
      Output := TJSONObject.Create;
      Output.AddPair('protectedFileCreated', TJSONBool.Create(True));
      Output.AddPair('offlineFixtureCreated', TJSONBool.Create(True));
      Output.AddPair('transactionSent', TJSONBool.Create(False));
    end
    else if Command = 'check-key' then
    begin
      Recovered := TLocalKeyProtection.Load(Path, ExpectedAccount);
      try
        if BytesToLowerHex(Recovered) <> BytesToLowerHex(PublishedKey) then
          raise ELocalKeyProtection.Create('Unexpected fixture.');
        Output := TJSONObject.Create;
        Output.AddPair('recoveredKnownFixture', TJSONBool.Create(True));
        Output.AddPair('transactionSent', TJSONBool.Create(False));
      finally TLocalKeyProtection.ClearOwned(Recovered); end;
    end
    else if Command = 'audit' then
    begin
      Checkpoint := TTransactionCheckpoint.Load(Path);
      Output := MinimalTrackingAudit(Checkpoint);
    end
    else raise EArgumentException.Create('Unknown command.');
    Writeln(Output.ToJSON);
  finally Output.Free; end;
end;

begin
  try Run;
  except on Error: Exception do
    begin
      // Nao ecoar mensagens de arquivo, conteudo do no, bytes ou parametros recebidos.
      Writeln(Error.ClassName, ': operation failed; inspect local inputs without exporting them.');
      ExitCode := 1;
    end;
  end;
end.
