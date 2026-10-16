unit Didactic.Block;

interface

uses System.SysUtils, System.JSON, Didactic.Codec, Didactic.Transaction;

type
  TMiningResult = record
    Found: Boolean;
    Attempts: UInt64;
    ElapsedMs: Int64;
  end;

  TDidacticBlock = record
    Height: UInt64;
    PreviousHash: string;
    Timestamp: UInt64;
    Difficulty: Byte;
    Nonce: UInt64;
    Transactions: TArray<TDocumentTransaction>;
    Hash: string;
    function CanonicalBytes(const APolicy: TDidacticPolicy): TBytes;
    function CalculateHash(const APolicy: TDidacticPolicy): string;
    procedure ValidateLink(const APolicy: TDidacticPolicy; const APrevious: TDidacticBlock);
    procedure ValidateContent(const APolicy: TDidacticPolicy);
    function ToJson: TJSONObject;
    class function FromJson(const AObject: TJSONObject): TDidacticBlock; static;
  end;

function HasProofOfWork(const AHash: string; const ADifficulty: Byte): Boolean;
function MineBlock(var ABlock: TDidacticBlock; const APolicy: TDidacticPolicy;
  const AMaxAttempts: UInt64 = 1000000; const AMaxMs: Cardinal = 3000;
  const ACancel: TFunc<Boolean> = nil): TMiningResult;
function GenesisBlock(const APolicy: TDidacticPolicy): TDidacticBlock;

implementation

uses System.Diagnostics, Blockchain.Primitives;

function TDidacticBlock.CanonicalBytes(const APolicy: TDidacticPolicy): TBytes;
var Transaction: TDocumentTransaction; Encoded: TBytes;
begin
  if Length(Transactions) > MaxBlockTransactions then raise EDidacticValidation.Create('Too many block transactions.');
  Result := TextBytes('DIDACTIC-BLOCK-1') + TextBytes(APolicy.NetworkId) +
    UIntBytes(Height, 8) + FixedHex(PreviousHash, 32) + UIntBytes(Timestamp, 8) +
    UIntBytes(Difficulty, 1) + UIntBytes(Nonce, 8) + UIntBytes(Length(Transactions), 4);
  for Transaction in Transactions do
  begin
    Encoded := Transaction.SignedBytes;
    Result := Result + UIntBytes(Length(Encoded), 4) + Encoded;
  end;
end;

function TDidacticBlock.CalculateHash(const APolicy: TDidacticPolicy): string;
begin
  Result := Sha256Bytes(CanonicalBytes(APolicy));
end;

function HasProofOfWork(const AHash: string; const ADifficulty: Byte): Boolean;
begin
  TDidacticPolicy.Create(ADifficulty);
  FixedHex(AHash, 32);
  Result := Copy(AHash, 1, ADifficulty) = StringOfChar('0', ADifficulty);
end;

procedure TDidacticBlock.ValidateLink(const APolicy: TDidacticPolicy; const APrevious: TDidacticBlock);
begin
  if (APrevious.Height = High(UInt64)) or (Height <> APrevious.Height + 1) or
    (PreviousHash <> APrevious.Hash) then raise EDidacticValidation.Create('Broken block link.');
  if Timestamp <= APrevious.Timestamp then raise EDidacticValidation.Create('Block timestamp must increase.');
  if Hash <> CalculateHash(APolicy) then raise EDidacticValidation.Create('Block content hash mismatch.');
end;

procedure TDidacticBlock.ValidateContent(const APolicy: TDidacticPolicy);
var Transaction: TDocumentTransaction;
begin
  if Difficulty <> APolicy.Difficulty then raise EDidacticValidation.Create('Block difficulty differs from network policy.');
  if (Hash <> CalculateHash(APolicy)) or not HasProofOfWork(Hash, Difficulty) then
    raise EDidacticValidation.Create('Invalid content hash or proof of work.');
  if (Height <> 0) and (Length(Transactions) = 0) then raise EDidacticValidation.Create('Non-genesis block must contain transactions.');
  for Transaction in Transactions do Transaction.Validate(APolicy);
end;

function MineBlock(var ABlock: TDidacticBlock; const APolicy: TDidacticPolicy;
  const AMaxAttempts: UInt64; const AMaxMs: Cardinal; const ACancel: TFunc<Boolean>): TMiningResult;
var Clock: TStopwatch; CandidateHash: string;
begin
  if (AMaxAttempts = 0) or (AMaxMs = 0) then raise EDidacticValidation.Create('Mining limits must be positive.');
  if ABlock.Difficulty <> APolicy.Difficulty then raise EDidacticValidation.Create('Mining difficulty mismatch.');
  Result := Default(TMiningResult);
  Clock := TStopwatch.StartNew;
  ABlock.Hash := '';
  ABlock.Nonce := 0;
  while Result.Attempts < AMaxAttempts do
  begin
    if Assigned(ACancel) and ACancel() then Break;
    if Clock.ElapsedMilliseconds >= AMaxMs then Break;
    ABlock.Nonce := Result.Attempts;
    CandidateHash := ABlock.CalculateHash(APolicy);
    Inc(Result.Attempts);
    if HasProofOfWork(CandidateHash, ABlock.Difficulty) then
    begin
      ABlock.Hash := CandidateHash;
      Result.Found := True;
      Break;
    end;
  end;
  Result.ElapsedMs := Clock.ElapsedMilliseconds;
end;

function GenesisBlock(const APolicy: TDidacticPolicy): TDidacticBlock;
begin
  Result := Default(TDidacticBlock);
  Result.PreviousHash := StringOfChar('0', 64);
  Result.Difficulty := APolicy.Difficulty;
  // Nonces publicados no vetor independente; nao minerar outra ancora durante uma carga.
  case APolicy.Difficulty of
    2: Result.Nonce := 286;
    3: Result.Nonce := 5140;
    4: Result.Nonce := 30654;
  else raise EDidacticValidation.Create('Unsupported genesis policy.'); end;
  Result.Hash := Result.CalculateHash(APolicy);
  Result.ValidateContent(APolicy);
end;

function TDidacticBlock.ToJson: TJSONObject;
var Values: TJSONArray; Transaction: TDocumentTransaction;
begin
  Result := TJSONObject.Create;
  Result.AddPair('height', UIntToStr(Height));
  Result.AddPair('previousHash', PreviousHash);
  Result.AddPair('timestamp', UIntToStr(Timestamp));
  Result.AddPair('difficulty', UIntToStr(Difficulty));
  Result.AddPair('nonce', UIntToStr(Nonce));
  Result.AddPair('hash', Hash);
  Values := TJSONArray.Create;
  Result.AddPair('transactions', Values);
  for Transaction in Transactions do Values.AddElement(Transaction.ToJson);
end;

class function TDidacticBlock.FromJson(const AObject: TJSONObject): TDidacticBlock;
var Values: TJSONArray; Index: Integer; DifficultyValue: UInt64;
begin
  RequireFields(AObject, ['height','previousHash','timestamp','difficulty','nonce','hash','transactions']);
  Result := Default(TDidacticBlock);
  Result.Height := JsonUInt(AObject, 'height');
  Result.PreviousHash := JsonText(AObject, 'previousHash');
  FixedHex(Result.PreviousHash, 32);
  Result.Timestamp := JsonUInt(AObject, 'timestamp');
  DifficultyValue := JsonUInt(AObject, 'difficulty');
  if (DifficultyValue < 2) or (DifficultyValue > 4) then raise EDidacticValidation.Create('Invalid block difficulty.');
  Result.Difficulty := DifficultyValue;
  Result.Nonce := JsonUInt(AObject, 'nonce');
  Result.Hash := JsonText(AObject, 'hash');
  FixedHex(Result.Hash, 32);
  if not (AObject.GetValue('transactions') is TJSONArray) then raise EDidacticValidation.Create('Transactions array required.');
  Values := AObject.GetValue<TJSONArray>('transactions');
  if Values.Count > MaxBlockTransactions then raise EDidacticValidation.Create('Too many block transactions.');
  SetLength(Result.Transactions, Values.Count);
  for Index := 0 to Values.Count - 1 do
  begin
    if not (Values.Items[Index] is TJSONObject) then raise EDidacticValidation.Create('Transaction object required.');
    Result.Transactions[Index] := TDocumentTransaction.FromJson(TJSONObject(Values.Items[Index]));
  end;
end;

end.
