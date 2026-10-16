unit Blockchain.TransactionJournal;

interface

uses System.SysUtils;

type
  TTransactionCheckpoint = record
    Port: Word;
    ChainId: string;
    RuntimeHex: string;
    ContractAddress: string;
    Account: string;
    DocumentHash: string;
    Hash: string;
    RawHex: string;
    State: string;
    BlockNumber: string;
    Diagnostic: string;
    procedure Validate;
    procedure Save(const APath: string);
    class function Load(const APath: string): TTransactionCheckpoint; static;
  end;

implementation

uses System.JSON, System.IOUtils, Winapi.Windows,
  Blockchain.Ethereum, Blockchain.Primitives;

procedure TTransactionCheckpoint.Validate;
var Raw: TBytes;
begin
  if Port = 0 then raise EArgumentException.Create('Invalid checkpoint port.');
  if TExactUInt256.FromDecimal(ChainId).ToDecimal = '0' then
    raise EArgumentException.Create('Invalid checkpoint chain id.');
  if Length(DecodeHex(RuntimeHex)) = 0 then raise EArgumentException.Create('Empty runtime.');
  AbiAddress(DecodeHex(Account));
  if ContractAddress <> '' then AbiAddress(DecodeHex(ContractAddress));
  if DocumentHash <> '' then ParseDocumentHash(DocumentHash);
  if BlockNumber <> '' then TExactUInt256.FromDecimal(BlockNumber);
  Raw := DecodeHex(RawHex);
  if (Length(Raw) = 0) or (Raw[0] <> 2) then raise EArgumentException.Create('Expected type-2 envelope.');
  if Hash <> '0x' + BytesToLowerHex(Keccak256(Raw)) then
    raise EArgumentException.Create('Checkpoint hash does not match signed bytes.');
  if (State <> 'prepared') and (State <> 'unknown') and (State <> 'submitted') and
    (State <> 'rejected') and (State <> 'pending') and (State <> 'succeeded') and
    (State <> 'reverted') then raise EArgumentException.Create('Invalid checkpoint state.');
end;

procedure TTransactionCheckpoint.Save(const APath: string);
var Document: TJSONObject; Path, Temporary: string; Identifier: TGUID;
begin
  Validate;
  Path := TPath.GetFullPath(APath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
  CreateGUID(Identifier);
  Temporary := Path + '.' + GUIDToString(Identifier) + '.tmp';
  Document := TJSONObject.Create;
  try
    Document.AddPair('schema', TJSONNumber.Create(1));
    Document.AddPair('port', TJSONNumber.Create(Port));
    Document.AddPair('chainId', ChainId);
    Document.AddPair('runtimeHex', RuntimeHex);
    Document.AddPair('contractAddress', ContractAddress);
    Document.AddPair('account', Account);
    Document.AddPair('documentHash', DocumentHash);
    Document.AddPair('hash', Hash);
    Document.AddPair('rawTransaction', RawHex);
    Document.AddPair('state', State);
    Document.AddPair('blockNumber', BlockNumber);
    Document.AddPair('diagnostic', Diagnostic);
    try
      TFile.WriteAllText(Temporary, Document.ToJSON, TEncoding.UTF8);
      if not MoveFileEx(PChar(Temporary), PChar(Path), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
        RaiseLastOSError;
    finally
      if TFile.Exists(Temporary) then TFile.Delete(Temporary);
    end;
  finally Document.Free; end;
end;

class function TTransactionCheckpoint.Load(const APath: string): TTransactionCheckpoint;
var Document: TJSONValue; PortValue: Integer;
  function Text(const AName: string): string;
  var Value: TJSONValue;
  begin
    Value := TJSONObject(Document).GetValue(AName);
    if not (Value is TJSONString) then raise EArgumentException.Create('Invalid checkpoint field: ' + AName);
    Result := Value.Value;
  end;
begin
  Result := Default(TTransactionCheckpoint);
  Document := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  try
    if not (Document is TJSONObject) then raise EArgumentException.Create('Invalid checkpoint JSON.');
    if not (TJSONObject(Document).GetValue('schema') is TJSONNumber) or
      (TJSONObject(Document).GetValue('schema').Value <> '1') then
      raise EArgumentException.Create('Unsupported checkpoint schema.');
    if not (TJSONObject(Document).GetValue('port') is TJSONNumber) or
      not TryStrToInt(TJSONObject(Document).GetValue('port').Value, PortValue) or
      (PortValue < 1) or (PortValue > 65535) then raise EArgumentException.Create('Invalid checkpoint port.');
    Result.Port := PortValue;
    Result.ChainId := Text('chainId');
    Result.RuntimeHex := Text('runtimeHex');
    Result.ContractAddress := Text('contractAddress');
    Result.Account := Text('account');
    Result.DocumentHash := Text('documentHash');
    Result.Hash := Text('hash');
    Result.RawHex := Text('rawTransaction');
    Result.State := Text('state');
    Result.BlockNumber := Text('blockNumber');
    Result.Diagnostic := Text('diagnostic');
    Result.Validate;
  finally Document.Free; end;
end;

end.
