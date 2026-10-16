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
    function CallString(const AMethod: string; AParameters: TJSONArray): string;
    procedure CheckNetwork;
    procedure CheckContract(const AAddress: string);
    function Submit(const APrivateKey, ADestination, AData: TBytes;
      const AGasLimit: string): TLocalSubmission;
  public
    constructor Create(const APort: Word; const AChainId: TExactUInt256;
      const ARuntimeBytecode: TBytes);
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
    property Address: string read FAddress;
  end;

implementation

uses Blockchain.Ethereum;

constructor TDocumentRegistry.Create(const APort: Word;
  const AChainId: TExactUInt256; const ARuntimeBytecode: TBytes);
begin
  inherited Create;
  if AChainId.ToDecimal = '0' then raise EArgumentException.Create('Chain id must be positive.');
  if Length(ARuntimeBytecode) = 0 then raise EArgumentException.Create('Expected runtime is empty.');
  FChainId := AChainId;
  FRuntimeHex := '0x' + BytesToLowerHex(ARuntimeBytecode);
  FRpc := TLocalRpc.Create(APort);
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

procedure TDocumentRegistry.CheckNetwork;
begin
  if TExactUInt256.FromRpcQuantity(CallString('eth_chainId', TJSONArray.Create)).ToDecimal <>
    FChainId.ToDecimal then raise EArgumentException.Create('Configured chain id differs from node.');
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
begin
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
  if CallString('eth_sendRawTransaction', TJSONArray.Create.Add(Result.RawHex)) <> Result.Hash then
    raise ELocalRpcError.Create('Node returned a different transaction hash.');
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

end.
