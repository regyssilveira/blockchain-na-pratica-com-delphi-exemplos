unit Blockchain.DocumentRegistry;

interface

uses System.SysUtils, System.JSON, Blockchain.Primitives, Blockchain.LocalRpc;

type
  TLocalSubmission = record
    Hash: string;
    RawHex: string;
  end;

  TDocumentRecord = record
    Exists: Boolean;
    BlockNumber: TExactUInt256;
  end;

  TDocumentRegistry = class
  private
    FRpc: TLocalRpc;
    FChainId: TExactUInt256;
    FRuntimeHex: string;
    FAddress: string;
    FPort: Word;
    FJournalPath: string;
    function CallString(const AMethod: string; AParameters: TJSONArray): string;
    procedure CheckNetwork(const ABudgetMs: Cardinal = 8000);
    procedure CheckContract(const AAddress: string);
    function Submit(const APrivateKey, ADestination, AData: TBytes;
      const AGasLimit: string): TLocalSubmission;
  public
    constructor Create(const APort: Word; const AChainId: TExactUInt256;
      const ARuntimeBytecode: TBytes; const ARpc: TLocalRpc = nil);
    destructor Destroy; override;
    function Deploy(const ACreationBytecode, APrivateKey: TBytes): TLocalSubmission;
    procedure Attach(const AAddress: string);
    function RegisterHash(const AHash, APrivateKey: TBytes): TLocalSubmission;
    function RegisterFile(const APath: string; const APrivateKey: TBytes): TLocalSubmission;
    // Permite exercitar diretamente o contrato, inclusive chamadas malformadas.
    function SubmitCall(const AData, APrivateKey: TBytes): TLocalSubmission;
    function Lookup(const AAccount, AHash: TBytes): TDocumentRecord;
    // Exclusivo do laboratorio Anvil; o chamador libera o recibo retornado.
    function MineReceipt(const AHash: string): TJSONObject;
    // Nil significa prazo esgotado com resultado ainda pendente, nunca rejeicao.
    function AwaitReceipt(const AHash: string; const ATotalMs: Cardinal = 30000;
      const APollMs: Cardinal = 1000): TJSONObject;
    property Address: string read FAddress;
    property JournalPath: string read FJournalPath write FJournalPath;
  end;

implementation

uses Blockchain.Ethereum, Blockchain.TransactionJournal, System.IOUtils,
  System.Diagnostics, System.Classes, System.Math;

constructor TDocumentRegistry.Create(const APort: Word;
  const AChainId: TExactUInt256; const ARuntimeBytecode: TBytes; const ARpc: TLocalRpc);
begin
  inherited Create;
  if AChainId.ToDecimal = '0' then raise EArgumentException.Create('Chain id must be positive.');
  if Length(ARuntimeBytecode) = 0 then raise EArgumentException.Create('Expected runtime is empty.');
  FChainId := AChainId;
  FPort := APort;
  FRuntimeHex := '0x' + BytesToLowerHex(ARuntimeBytecode);
  // A instancia passa a ser propriedade do cliente, inclusive quando e um duplo de teste.
  FRpc := ARpc;
  if not Assigned(FRpc) then FRpc := TLocalRpc.Create(APort);
end;

destructor TDocumentRegistry.Destroy;
begin
  FRpc.Free;
  inherited;
end;

function TDocumentRegistry.CallString(const AMethod: string; AParameters: TJSONArray): string;
var Value: TJSONValue;
begin
  Value := FRpc.Call(AMethod, AParameters);
  try
    if not (Value is TJSONString) then raise ELocalRpcError.Create('Expected JSON string: ' + AMethod);
    Result := Value.Value;
  finally Value.Free; end;
end;

procedure TDocumentRegistry.CheckNetwork(const ABudgetMs: Cardinal);
var Value: TJSONValue;
begin
  Value := FRpc.Call('eth_chainId', TJSONArray.Create, ABudgetMs);
  try
    if not (Value is TJSONString) then raise ELocalRpcError.Create('Chain id must be a quantity string.');
    if TExactUInt256.FromRpcQuantity(Value.Value).ToDecimal <> FChainId.ToDecimal then
      raise EArgumentException.Create('Configured chain id differs from node.');
  finally Value.Free; end;
end;

procedure TDocumentRegistry.CheckContract(const AAddress: string);
begin
  AbiAddress(DecodeHex(AAddress));
  if CallString('eth_getCode', TJSONArray.Create(AAddress, 'latest')) <> FRuntimeHex then
    raise EArgumentException.Create('Contract runtime differs from compiled artifact.');
end;

procedure TDocumentRegistry.Attach(const AAddress: string);
begin
  CheckNetwork;
  CheckContract(AAddress);
  FAddress := AAddress;
end;

function TDocumentRegistry.Submit(const APrivateKey, ADestination, AData: TBytes;
  const AGasLimit: string): TLocalSubmission;
var Transaction: TType2Transaction; Sender: string; Raw: TBytes;
  Checkpoint: TTransactionCheckpoint;
  procedure SaveState(const AState, ADiagnostic: string);
  begin
    if FJournalPath = '' then Exit;
    Checkpoint.State := AState;
    Checkpoint.Diagnostic := ADiagnostic;
    Checkpoint.Save(FJournalPath);
  end;
begin
  if (FJournalPath <> '') and TFile.Exists(FJournalPath) then
    raise EArgumentException.Create('Checkpoint already exists; resume instead of sending again.');
  CheckNetwork;
  if Length(ADestination) > 0 then CheckContract('0x' + BytesToLowerHex(ADestination));
  Sender := '0x' + BytesToLowerHex(AddressFromPublicKey(PublicKeyFromPrivateKey(APrivateKey)));
  Transaction.ChainId := FChainId;
  Transaction.Nonce := TExactUInt256.FromRpcQuantity(CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'pending')));
  // Taxas fixas somente para a rede Anvil configurada pelo roteiro.
  Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('1000000000');
  Transaction.MaxFeePerGas := TExactUInt256.FromDecimal('3000000000');
  Transaction.GasLimit := TExactUInt256.FromDecimal(AGasLimit);
  Transaction.Destination := Copy(ADestination);
  Transaction.Amount := TExactUInt256.FromDecimal('0');
  Transaction.Data := Copy(AData);
  Raw := Transaction.SignedEnvelope(SignDigest(Transaction.SigningHash, APrivateKey));
  Result.RawHex := '0x' + BytesToLowerHex(Raw);
  Result.Hash := '0x' + BytesToLowerHex(Keccak256(Raw));
  Checkpoint := Default(TTransactionCheckpoint);
  Checkpoint.Port := FPort;
  Checkpoint.ChainId := FChainId.ToDecimal;
  Checkpoint.RuntimeHex := FRuntimeHex;
  if Length(ADestination) > 0 then Checkpoint.ContractAddress := '0x' + BytesToLowerHex(ADestination);
  Checkpoint.Account := Sender;
  if (Length(AData) = 36) and
    (BytesToLowerHex(Copy(AData, 0, 4)) = BytesToLowerHex(AbiSelector('register(bytes32)'))) then
    Checkpoint.DocumentHash := BytesToLowerHex(Copy(AData, 4, 32));
  Checkpoint.Hash := Result.Hash;
  Checkpoint.RawHex := Result.RawHex;
  SaveState('prepared', 'Signed locally; not sent.');
  // Persistir antes do envio: se a resposta ou o processo se perder, consultar o hash original.
  SaveState('unknown', 'Send may be attempted; do not resend automatically.');
  try
    if CallString('eth_sendRawTransaction', TJSONArray.Create.Add(Result.RawHex)) <> Result.Hash then
      raise ELocalRpcError.Create('Node returned a different transaction hash.');
  except
    on Error: EJsonRpcError do
    begin
      SaveState('rejected', Error.Message);
      raise;
    end;
    on Error: ELocalRpcError do
    begin
      SaveState('unknown', Error.Message);
      raise;
    end;
  end;
  SaveState('submitted', 'Node accepted signed bytes; inclusion not confirmed.');
end;

function TDocumentRegistry.Deploy(const ACreationBytecode, APrivateKey: TBytes): TLocalSubmission;
begin
  if Length(ACreationBytecode) = 0 then raise EArgumentException.Create('Creation bytecode is empty.');
  Result := Submit(APrivateKey, nil, ACreationBytecode, '1000000');
end;

function TDocumentRegistry.SubmitCall(const AData, APrivateKey: TBytes): TLocalSubmission;
begin
  if FAddress = '' then raise EArgumentException.Create('Attach a verified contract first.');
  Result := Submit(APrivateKey, DecodeHex(FAddress), AData, '150000');
end;

function TDocumentRegistry.RegisterHash(const AHash, APrivateKey: TBytes): TLocalSubmission;
begin
  Result := SubmitCall(AbiCall('register(bytes32)', [AbiBytes32(AHash)]), APrivateKey);
end;

function TDocumentRegistry.RegisterFile(const APath: string; const APrivateKey: TBytes): TLocalSubmission;
begin
  Result := RegisterHash(ParseDocumentHash(Sha256File(APath)), APrivateKey);
end;

function TDocumentRegistry.Lookup(const AAccount, AHash: TBytes): TDocumentRecord;
var Data, Encoded: TBytes; Request: TJSONObject; Parameters: TJSONArray;
begin
  Data := AbiCall('lookup(address,bytes32)', [AbiAddress(AAccount), AbiBytes32(AHash)]);
  CheckNetwork;
  CheckContract(FAddress);
  Request := TJSONObject.Create;
  Request.AddPair('to', FAddress);
  Request.AddPair('data', '0x' + BytesToLowerHex(Data));
  Parameters := TJSONArray.Create;
  Parameters.AddElement(Request);
  Parameters.Add('latest');
  Encoded := DecodeHex(CallString('eth_call', Parameters));
  if Length(Encoded) <> 64 then raise ELocalRpcError.Create('Expected two ABI return words.');
  Result.Exists := DecodeAbiBoolean(Copy(Encoded, 0, 32));
  Result.BlockNumber := TExactUInt256.FromBigEndianBytes(Copy(Encoded, 32, 32));
  if Result.Exists <> (Result.BlockNumber.ToDecimal <> '0') then
    raise ELocalRpcError.Create('Inconsistent registry result.');
end;

function TDocumentRegistry.MineReceipt(const AHash: string): TJSONObject;
var Value: TJSONValue;
begin
  Value := FRpc.Call('evm_mine', TJSONArray.Create);
  Value.Free;
  Value := FRpc.Call('eth_getTransactionReceipt', TJSONArray.Create.Add(AHash));
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise ELocalRpcError.Create('Receipt unavailable after local mining; outcome unknown.');
  end;
  Result := TJSONObject(Value);
end;

function TDocumentRegistry.AwaitReceipt(const AHash: string; const ATotalMs,
  APollMs: Cardinal): TJSONObject;
var
  Clock: TStopwatch;
  Value: TJSONValue;
  Receipt: TJSONObject;
  Checkpoint: TTransactionCheckpoint;
  Remaining: Cardinal;
  Logs, Topics: TJSONArray;
  Event: TJSONObject;
  function Budget: Cardinal;
  begin
    if Clock.ElapsedMilliseconds >= ATotalMs then Exit(0);
    Result := ATotalMs - Cardinal(Clock.ElapsedMilliseconds);
  end;
  procedure SaveState(const AState, ADiagnostic: string);
  begin
    if FJournalPath = '' then Exit;
    if not (((Checkpoint.State = 'succeeded') or (Checkpoint.State = 'reverted')) and
      ((AState = 'unknown') or (AState = 'pending'))) then Checkpoint.State := AState;
    Checkpoint.Diagnostic := ADiagnostic;
    Checkpoint.Save(FJournalPath);
  end;
  function Text(const AName: string): string;
  var Field: TJSONValue;
  begin
    Field := Receipt.GetValue(AName);
    if not (Field is TJSONString) then raise ELocalRpcError.Create('Invalid receipt field: ' + AName);
    Result := Field.Value;
  end;
begin
  Result := nil;
  if (ATotalMs = 0) or (APollMs = 0) then raise EArgumentException.Create('Receipt timing must be positive.');
  if (Copy(AHash, 1, 2) <> '0x') or (Length(DecodeHex(AHash)) <> 32) then
    raise EArgumentException.Create('Transaction hash must contain 32 bytes.');
  if FJournalPath <> '' then
  begin
    Checkpoint := TTransactionCheckpoint.Load(FJournalPath);
    if (Checkpoint.Hash <> AHash) or (Checkpoint.Port <> FPort) or
      (Checkpoint.ChainId <> FChainId.ToDecimal) or (Checkpoint.RuntimeHex <> FRuntimeHex) then
      raise EArgumentException.Create('Checkpoint does not match tracking configuration.');
    if Checkpoint.State = 'rejected' then
      raise EArgumentException.Create('Stored node rejection; do not classify as pending.');
  end;
  Clock := TStopwatch.StartNew;
  try
    CheckNetwork(Budget);
    repeat
      Remaining := Budget;
      if Remaining = 0 then Break;
      Value := FRpc.Call('eth_getTransactionReceipt', TJSONArray.Create.Add(AHash), Remaining);
      try
        if Value is TJSONObject then
        begin
          Receipt := TJSONObject(Value);
          if Text('transactionHash') <> AHash then raise ELocalRpcError.Create('Receipt hash mismatch.');
          if (Text('status') <> '0x0') and (Text('status') <> '0x1') then
            raise ELocalRpcError.Create('Invalid receipt status.');
          if Length(DecodeHex(Text('blockHash'))) <> 32 then raise ELocalRpcError.Create('Invalid block hash.');
          TExactUInt256.FromRpcQuantity(Text('gasUsed'));
          Checkpoint.BlockNumber := TExactUInt256.FromRpcQuantity(Text('blockNumber')).ToDecimal;
          AbiAddress(DecodeHex(Text('from')));
          if not (Receipt.GetValue('logs') is TJSONArray) then raise ELocalRpcError.Create('Invalid receipt logs.');
          if (FJournalPath <> '') and (Text('from') <> Checkpoint.Account) then
            raise ELocalRpcError.Create('Receipt sender mismatch.');
          Logs := Receipt.GetValue<TJSONArray>('logs');
          if (Text('status') = '0x0') and (Logs.Count <> 0) then
            raise ELocalRpcError.Create('Reverted receipt cannot contain committed events.');
          if (FJournalPath <> '') and (Checkpoint.DocumentHash <> '') and (Text('status') = '0x1') then
          begin
            if Text('to') <> Checkpoint.ContractAddress then raise ELocalRpcError.Create('Receipt destination mismatch.');
            if (Logs.Count <> 1) or not (Logs.Items[0] is TJSONObject) then
              raise ELocalRpcError.Create('Expected one document registration event.');
            Event := TJSONObject(Logs.Items[0]);
            if Event.GetValue<string>('address', '') <> Checkpoint.ContractAddress then
              raise ELocalRpcError.Create('Event contract mismatch.');
            if not (Event.GetValue('topics') is TJSONArray) then raise ELocalRpcError.Create('Invalid event topics.');
            Topics := Event.GetValue<TJSONArray>('topics');
            if (Topics.Count <> 3) or
              (Topics.Items[0].Value <> '0x' + BytesToLowerHex(Keccak256(TEncoding.ASCII.GetBytes('DocumentRegistered(address,bytes32,uint256)')))) or
              (Topics.Items[1].Value <> '0x' + BytesToLowerHex(AbiAddress(DecodeHex(Checkpoint.Account)))) or
              (Topics.Items[2].Value <> '0x' + Checkpoint.DocumentHash) then
              raise ELocalRpcError.Create('Registration event does not match account/document.');
            if TExactUInt256.FromBigEndianBytes(DecodeHex(Event.GetValue<string>('data', ''))).ToDecimal <> Checkpoint.BlockNumber then
              raise ELocalRpcError.Create('Event block differs from receipt.');
          end;
          if (FJournalPath <> '') and (Checkpoint.ContractAddress = '') and (Text('status') = '0x1') then
          begin
            Checkpoint.ContractAddress := Text('contractAddress');
            AbiAddress(DecodeHex(Checkpoint.ContractAddress));
          end;
          if Text('status') = '0x1' then SaveState('succeeded', 'Included with status 0x1.')
          else SaveState('reverted', 'Included with status 0x0; execution reverted.');
          Result := Receipt;
          Value := nil;
          Exit;
        end;
        if not (Value is TJSONNull) then raise ELocalRpcError.Create('Receipt must be object or null.');
      finally Value.Free; end;
      SaveState('pending', 'Receipt absent; do not resend.');
      Remaining := Budget;
      if Remaining > 0 then TThread.Sleep(Min(APollMs, Remaining));
    until Budget = 0;
  except
    on Error: ELocalRpcTimeout do
    begin
      SaveState('unknown', Error.Message);
      Exit(nil);
    end;
    on Error: Exception do
    begin
      SaveState('unknown', Error.Message);
      raise;
    end;
  end;
  SaveState('pending', 'Tracking deadline expired; outcome still unknown. Resume by original hash.');
end;

end.
