program DocumentRegistry.Demo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON, System.IOUtils, Winapi.Windows, Winapi.TlHelp32,
  Blockchain.Primitives in '..\src\Blockchain.Primitives.pas',
  Blockchain.Ethereum in '..\src\Blockchain.Ethereum.pas',
  Blockchain.LocalRpc in '..\src\Blockchain.LocalRpc.pas',
  Blockchain.DocumentRegistry in '..\src\Blockchain.DocumentRegistry.pas';

function LoadedModules: TJSONArray;
var Snapshot: THandle; Entry: TModuleEntry32;
begin
  Result := TJSONArray.Create;
  try
    Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId);
    if Snapshot = INVALID_HANDLE_VALUE then RaiseLastOSError;
    try
      Entry.dwSize := SizeOf(Entry);
      if not Module32First(Snapshot, Entry) then RaiseLastOSError;
      repeat
        Result.Add(string(Entry.szExePath));
      until not Module32Next(Snapshot, Entry);
    finally CloseHandle(Snapshot); end;
  except Result.Free; raise; end;
end;

procedure Run;
var
  Artifact, Evidence, Receipt: TJSONObject;
  Registry: TDocumentRegistry;
  PrivateKey, DocumentHash, Account: TBytes;
  Deployment, Registration: TLocalSubmission;
  Found: TDocumentRecord;
  ContractAddress, BlockNumber: string;
begin
  if ParamCount <> 1 then raise EArgumentException.Create('Informe o caminho de um arquivo.');
  // Falha de leitura ocorre antes de implantar ou assinar qualquer transacao.
  DocumentHash := ParseDocumentHash(Sha256File(ParamStr(1)));
  Artifact := TJSONObject.ParseJSONValue(TFile.ReadAllText('build\contract\DocumentRegistry.json', TEncoding.UTF8)) as TJSONObject;
  Registry := nil;
  Evidence := TJSONObject.Create;
  try
    if not Assigned(Artifact) then raise EArgumentException.Create('Artefato do contrato invalido.');
    Registry := TDocumentRegistry.Create(StrToInt(GetEnvironmentVariable('P04_ANVIL_PORT')),
      TExactUInt256.FromDecimal('31337'), DecodeHex(Artifact.GetValue<string>('runtimeBytecode')));
    // Chave privada de teste publicamente conhecida; saldo somente no Anvil local.
    PrivateKey := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
    Account := AddressFromPublicKey(PublicKeyFromPrivateKey(PrivateKey));
    Deployment := Registry.Deploy(DecodeHex(Artifact.GetValue<string>('creationBytecode')), PrivateKey);
    Receipt := Registry.MineReceipt(Deployment.Hash);
    try
      if Receipt.GetValue<string>('status') <> '0x1' then raise ELocalRpcError.Create('Implantacao revertida.');
      ContractAddress := Receipt.GetValue<string>('contractAddress');
      Evidence.AddPair('deploymentReceipt', Receipt.Clone as TJSONValue);
    finally Receipt.Free; end;
    Registry.Attach(ContractAddress);
    Registration := Registry.RegisterHash(DocumentHash, PrivateKey);
    Receipt := Registry.MineReceipt(Registration.Hash);
    try
      if Receipt.GetValue<string>('status') <> '0x1' then raise ELocalRpcError.Create('Registro revertido.');
      BlockNumber := TExactUInt256.FromRpcQuantity(Receipt.GetValue<string>('blockNumber')).ToDecimal;
      Evidence.AddPair('registrationReceipt', Receipt.Clone as TJSONValue);
    finally Receipt.Free; end;
    Found := Registry.Lookup(Account, DocumentHash);
    if not Found.Exists or (Found.BlockNumber.ToDecimal <> BlockNumber) then
      raise ELocalRpcError.Create('Consulta divergiu do recibo.');
    Evidence.AddPair('documentSha256', BytesToLowerHex(DocumentHash));
    Evidence.AddPair('account', '0x' + BytesToLowerHex(Account));
    Evidence.AddPair('contractAddress', ContractAddress);
    Evidence.AddPair('deploymentRawTransaction', Deployment.RawHex);
    Evidence.AddPair('registrationRawTransaction', Registration.RawHex);
    Evidence.AddPair('lookupExists', TJSONBool.Create(Found.Exists));
    Evidence.AddPair('lookupBlock', Found.BlockNumber.ToDecimal);
    Evidence.AddPair('loadedModules', LoadedModules);
    Evidence.AddPair('passed', TJSONBool.Create(True));
    TFile.WriteAllText('build\Anvil\demo.json', Evidence.ToJSON, TEncoding.UTF8);
    Writeln('SHA-256 do arquivo: ', BytesToLowerHex(DocumentHash));
    Writeln('Contrato implantado e conferido: ', ContractAddress);
    Writeln('Transacao de implantacao: ', Deployment.Hash);
    Writeln('Transacao de registro: ', Registration.Hash);
    Writeln('Consulta confirmou o registro no bloco ', Found.BlockNumber.ToDecimal);
    Writeln('Evidencia: build/Anvil/demo.json');
  finally
    Evidence.Free;
    Registry.Free;
    Artifact.Free;
  end;
end;

begin
  try
    Run;
  except
    on Error: Exception do
    begin
      Writeln(Error.ClassName, ': ', Error.Message);
      System.ExitCode := 1;
    end;
  end;
end.
