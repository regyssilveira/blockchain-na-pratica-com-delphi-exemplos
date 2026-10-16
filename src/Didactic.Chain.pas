unit Didactic.Chain;

interface

uses System.SysUtils, System.JSON, System.Generics.Collections,
  Didactic.Codec, Didactic.Transaction, Didactic.Block;

type
  TDocumentEntry = record
    Exists: Boolean;
    BlockHeight: UInt64;
    TransactionId: string;
  end;

  TDidacticState = class
  private
    FSequences: TDictionary<string, UInt64>;
    FDocuments: TDictionary<string, TDocumentEntry>;
    FIds: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    function Clone: TDidacticState;
    procedure Apply(const ATransaction: TDocumentTransaction; const AHeight: UInt64;
      const APolicy: TDidacticPolicy);
    function ContainsId(const AId: string): Boolean;
    function Lookup(const AAccount, AHash: string): TDocumentEntry;
    function SequenceOf(const AAccount: string): UInt64;
  end;

  TDidacticChain = class
  private
    FPolicy: TDidacticPolicy;
    FBlocks: TArray<TDidacticBlock>;
    FPending: TArray<TDocumentTransaction>;
    FState: TDidacticState;
    procedure ValidateBlocks;
    procedure RebuildPending(const ATransactions: TArray<TDocumentTransaction>);
  public
    constructor Create(const APolicy: TDidacticPolicy);
    destructor Destroy; override;
    function Clone: TDidacticChain;
    procedure Validate;
    function Submit(const ATransaction: TDocumentTransaction): Boolean;
    function Mine(const ATimestamp: UInt64; const AMaxAttempts: UInt64 = 1000000;
      const AMaxMs: Cardinal = 3000): TMiningResult;
    function AcceptBlock(const ABlock: TDidacticBlock): Boolean;
    function Consider(const ACandidate: TDidacticChain): Boolean;
    function Tip: TDidacticBlock;
    function BlockAt(const AIndex: Integer): TDidacticBlock;
    function PendingAt(const AIndex: Integer): TDocumentTransaction;
    function BlockCount: Integer;
    function PendingCount: Integer;
    function TotalWork: UInt64;
    function Lookup(const AAccount, AHash: string): TDocumentEntry;
    function TransactionState(const AId: string): string;
    function ToJson: TJSONObject;
    class function FromJson(const AObject: TJSONObject; const APolicy: TDidacticPolicy): TDidacticChain; static;
    procedure Save(const APath: string);
    class function Load(const APath: string; const APolicy: TDidacticPolicy): TDidacticChain; static;
    property Policy: TDidacticPolicy read FPolicy;
  end;

implementation

uses System.IOUtils, System.Math, Blockchain.Primitives;

constructor TDidacticState.Create;
begin
  inherited;
  FSequences := TDictionary<string, UInt64>.Create;
  FDocuments := TDictionary<string, TDocumentEntry>.Create;
  FIds := TDictionary<string, Boolean>.Create;
end;

destructor TDidacticState.Destroy;
begin
  FIds.Free;
  FDocuments.Free;
  FSequences.Free;
  inherited;
end;

function TDidacticState.Clone: TDidacticState;
var SequencePair: TPair<string, UInt64>; DocumentPair: TPair<string, TDocumentEntry>;
  IdPair: TPair<string, Boolean>;
begin
  Result := TDidacticState.Create;
  for SequencePair in FSequences do Result.FSequences.Add(SequencePair.Key, SequencePair.Value);
  for DocumentPair in FDocuments do Result.FDocuments.Add(DocumentPair.Key, DocumentPair.Value);
  for IdPair in FIds do Result.FIds.Add(IdPair.Key, IdPair.Value);
end;

function TDidacticState.SequenceOf(const AAccount: string): UInt64;
begin
  if not FSequences.TryGetValue(AAccount, Result) then Result := 0;
end;

function TDidacticState.Lookup(const AAccount, AHash: string): TDocumentEntry;
begin
  FixedHex(AAccount, 32);
  FixedHex(AHash, 32);
  if not FDocuments.TryGetValue(AAccount + ':' + AHash, Result) then Result := Default(TDocumentEntry);
end;

function TDidacticState.ContainsId(const AId: string): Boolean;
begin
  Result := FIds.ContainsKey(AId);
end;

procedure TDidacticState.Apply(const ATransaction: TDocumentTransaction;
  const AHeight: UInt64; const APolicy: TDidacticPolicy);
var Account, Id, DocumentKey: string; PreviousSequence: UInt64; Entry: TDocumentEntry;
begin
  ATransaction.Validate(APolicy);
  Account := ATransaction.Account;
  Id := ATransaction.Id;
  if FIds.ContainsKey(Id) then raise EDidacticValidation.Create('Repeated transaction id.');
  PreviousSequence := SequenceOf(Account);
  if (PreviousSequence = High(UInt64)) or (ATransaction.Sequence <> PreviousSequence + 1) then
    raise EDidacticValidation.Create('Invalid account sequence.');
  DocumentKey := Account + ':' + ATransaction.DocumentHash;
  if FDocuments.ContainsKey(DocumentKey) then raise EDidacticValidation.Create('Document already registered by account.');
  Entry.Exists := True;
  Entry.BlockHeight := AHeight;
  Entry.TransactionId := Id;
  FSequences.AddOrSetValue(Account, ATransaction.Sequence);
  FDocuments.Add(DocumentKey, Entry);
  FIds.Add(Id, True);
end;

constructor TDidacticChain.Create(const APolicy: TDidacticPolicy);
begin
  inherited Create;
  FPolicy := TDidacticPolicy.Create(APolicy.Difficulty);
  FBlocks := TArray<TDidacticBlock>.Create(GenesisBlock(FPolicy));
  FState := TDidacticState.Create;
end;

destructor TDidacticChain.Destroy;
begin
  FState.Free;
  inherited;
end;

function TDidacticChain.BlockAt(const AIndex: Integer): TDidacticBlock;
begin
  if (AIndex < 0) or (AIndex >= Length(FBlocks)) then raise EDidacticValidation.Create('Invalid block index.');
  Result := FBlocks[AIndex];
  Result.Transactions := Copy(Result.Transactions);
end;

function TDidacticChain.Tip: TDidacticBlock;
begin
  Result := BlockAt(High(FBlocks));
end;

function TDidacticChain.PendingAt(const AIndex: Integer): TDocumentTransaction;
begin
  if (AIndex < 0) or (AIndex >= Length(FPending)) then raise EDidacticValidation.Create('Invalid pending index.');
  Result := FPending[AIndex];
end;

function TDidacticChain.BlockCount: Integer;
begin
  Result := Length(FBlocks);
end;

function TDidacticChain.PendingCount: Integer;
begin
  Result := Length(FPending);
end;

function TDidacticChain.TotalWork: UInt64;
begin
  // Dificuldade constante por rede: cada bloco contribui 16^d unidades didaticas.
  Result := UInt64(Length(FBlocks) - 1) * (UInt64(1) shl (4 * FPolicy.Difficulty));
end;

function TDidacticChain.Lookup(const AAccount, AHash: string): TDocumentEntry;
begin
  Result := FState.Lookup(AAccount, AHash);
end;

function TDidacticChain.TransactionState(const AId: string): string;
var Transaction: TDocumentTransaction;
begin
  FixedHex(AId, 32);
  if FState.ContainsId(AId) then Exit('confirmed');
  for Transaction in FPending do if Transaction.Id = AId then Exit('pending');
  Result := 'absent';
end;

procedure TDidacticChain.ValidateBlocks;
var State: TDidacticState; Index: Integer; Transaction: TDocumentTransaction;
  Genesis: TDidacticBlock;
begin
  if (Length(FBlocks) < 1) or (Length(FBlocks) > MaxDidacticBlocks) then raise EDidacticValidation.Create('Invalid chain length.');
  Genesis := GenesisBlock(FPolicy);
  if (FBlocks[0].Hash <> Genesis.Hash) or
    (FBlocks[0].CalculateHash(FPolicy) <> Genesis.Hash) then raise EDidacticValidation.Create('Untrusted genesis.');
  State := TDidacticState.Create;
  try
    FBlocks[0].ValidateContent(FPolicy);
    for Index := 1 to High(FBlocks) do
    begin
      FBlocks[Index].ValidateLink(FPolicy, FBlocks[Index - 1]);
      FBlocks[Index].ValidateContent(FPolicy);
      for Transaction in FBlocks[Index].Transactions do State.Apply(Transaction, FBlocks[Index].Height, FPolicy);
    end;
    FState.Free;
    FState := State;
    State := nil;
  finally State.Free; end;
end;

procedure TDidacticChain.Validate;
var State: TDidacticState; Transaction: TDocumentTransaction;
begin
  ValidateBlocks;
  if Length(FPending) > MaxPendingTransactions then raise EDidacticValidation.Create('Too many pending transactions.');
  State := FState.Clone;
  try
    for Transaction in FPending do State.Apply(Transaction, Length(FBlocks), FPolicy);
  finally State.Free; end;
end;

function TDidacticChain.Submit(const ATransaction: TDocumentTransaction): Boolean;
var Transaction: TDocumentTransaction; State: TDidacticState;
begin
  ATransaction.Validate(FPolicy);
  if FState.ContainsId(ATransaction.Id) then Exit(False);
  for Transaction in FPending do if Transaction.Id = ATransaction.Id then Exit(False);
  if Length(FPending) >= MaxPendingTransactions then raise EDidacticValidation.Create('Pending pool full.');
  State := FState.Clone;
  try
    for Transaction in FPending do State.Apply(Transaction, Length(FBlocks), FPolicy);
    State.Apply(ATransaction, Length(FBlocks), FPolicy);
  finally State.Free; end;
  FPending := FPending + TArray<TDocumentTransaction>.Create(ATransaction);
  Result := True;
end;

procedure TDidacticChain.RebuildPending(const ATransactions: TArray<TDocumentTransaction>);
var Transaction: TDocumentTransaction;
begin
  FPending := nil;
  for Transaction in ATransactions do
    try Submit(Transaction); except on Error: EDidacticValidation do begin end; end;
end;

function TDidacticChain.AcceptBlock(const ABlock: TDidacticBlock): Boolean;
var Existing: TDidacticBlock; State: TDidacticState; Transaction: TDocumentTransaction;
  PreviousPending: TArray<TDocumentTransaction>; StoredBlock: TDidacticBlock;
begin
  ABlock.ValidateContent(FPolicy);
  for Existing in FBlocks do if Existing.Hash = ABlock.Hash then Exit(False);
  if (ABlock.Height <> UInt64(Length(FBlocks))) or (ABlock.PreviousHash <> Tip.Hash) then
    raise ENeedDidacticSync.Create('Block requires chain synchronization.');
  if Length(FBlocks) >= MaxDidacticBlocks then raise EDidacticValidation.Create('Laboratory chain capacity reached.');
  ABlock.ValidateLink(FPolicy, Tip);
  State := FState.Clone;
  try
    for Transaction in ABlock.Transactions do State.Apply(Transaction, ABlock.Height, FPolicy);
    StoredBlock := ABlock;
    StoredBlock.Transactions := Copy(ABlock.Transactions);
    FBlocks := FBlocks + TArray<TDidacticBlock>.Create(StoredBlock);
    FState.Free;
    FState := State;
    State := nil;
  finally State.Free; end;
  PreviousPending := FPending;
  RebuildPending(PreviousPending);
  Result := True;
end;

function TDidacticChain.Mine(const ATimestamp, AMaxAttempts: UInt64;
  const AMaxMs: Cardinal): TMiningResult;
var Block: TDidacticBlock;
begin
  if Length(FPending) = 0 then raise EDidacticValidation.Create('No pending transactions.');
  if Length(FBlocks) >= MaxDidacticBlocks then raise EDidacticValidation.Create('Laboratory chain capacity reached.');
  if ATimestamp <= Tip.Timestamp then raise EDidacticValidation.Create('Timestamp must advance.');
  Block := Default(TDidacticBlock);
  Block.Height := Length(FBlocks);
  Block.PreviousHash := Tip.Hash;
  Block.Timestamp := ATimestamp;
  Block.Difficulty := FPolicy.Difficulty;
  Block.Transactions := Copy(FPending, 0, Min(Length(FPending), MaxBlockTransactions));
  Result := MineBlock(Block, FPolicy, AMaxAttempts, AMaxMs);
  if Result.Found then AcceptBlock(Block);
end;

function TDidacticChain.Consider(const ACandidate: TDidacticChain): Boolean;
var Reconsider: TArray<TDocumentTransaction>; Index: Integer; Block: TDidacticBlock;
  Transaction: TDocumentTransaction;
begin
  ACandidate.Validate;
  if ACandidate.FPolicy.NetworkId <> FPolicy.NetworkId then raise EDidacticValidation.Create('Candidate network differs.');
  Result := False;
  if ACandidate.TotalWork > TotalWork then
  begin
    // Transacoes orfas retornam apenas se continuarem validas no novo estado.
    Reconsider := nil;
    for Index := 1 to High(FBlocks) do
      for Transaction in FBlocks[Index].Transactions do
        Reconsider := Reconsider + TArray<TDocumentTransaction>.Create(Transaction);
    Reconsider := Reconsider + FPending + ACandidate.FPending;
    FBlocks := nil;
    for Index := 0 to ACandidate.BlockCount - 1 do
    begin
      Block := ACandidate.BlockAt(Index);
      FBlocks := FBlocks + TArray<TDidacticBlock>.Create(Block);
    end;
    ValidateBlocks;
    RebuildPending(Reconsider);
    Exit(True);
  end;
  // Empate de trabalho com historico divergente: conservar a cadeia atual.
  if ACandidate.Tip.Hash = Tip.Hash then
  begin
    Reconsider := FPending + ACandidate.FPending;
    Index := Length(FPending);
    RebuildPending(Reconsider);
    Result := Length(FPending) <> Index;
  end;
end;

function TDidacticChain.ToJson: TJSONObject;
var Blocks, Pending: TJSONArray; Block: TDidacticBlock; Transaction: TDocumentTransaction;
begin
  Result := TJSONObject.Create;
  Result.AddPair('schema', '1');
  Result.AddPair('network', FPolicy.NetworkId);
  Result.AddPair('difficulty', UIntToStr(FPolicy.Difficulty));
  Blocks := TJSONArray.Create;
  Result.AddPair('blocks', Blocks);
  for Block in FBlocks do Blocks.AddElement(Block.ToJson);
  Pending := TJSONArray.Create;
  Result.AddPair('pending', Pending);
  for Transaction in FPending do Pending.AddElement(Transaction.ToJson);
end;

class function TDidacticChain.FromJson(const AObject: TJSONObject;
  const APolicy: TDidacticPolicy): TDidacticChain;
var Blocks, Pending: TJSONArray; Index: Integer;
begin
  RequireFields(AObject, ['schema','network','difficulty','blocks','pending']);
  if (JsonText(AObject, 'schema') <> '1') or (JsonText(AObject, 'network') <> APolicy.NetworkId) or
    (JsonUInt(AObject, 'difficulty') <> APolicy.Difficulty) then raise EDidacticValidation.Create('Snapshot policy differs.');
  if not (AObject.GetValue('blocks') is TJSONArray) or not (AObject.GetValue('pending') is TJSONArray) then
    raise EDidacticValidation.Create('Snapshot arrays required.');
  Blocks := AObject.GetValue<TJSONArray>('blocks');
  Pending := AObject.GetValue<TJSONArray>('pending');
  if (Blocks.Count < 1) or (Blocks.Count > MaxDidacticBlocks) or (Pending.Count > MaxPendingTransactions) then
    raise EDidacticValidation.Create('Snapshot capacity exceeded.');
  Result := TDidacticChain.Create(APolicy);
  try
    SetLength(Result.FBlocks, Blocks.Count);
    for Index := 0 to Blocks.Count - 1 do
    begin
      if not (Blocks.Items[Index] is TJSONObject) then raise EDidacticValidation.Create('Block object required.');
      Result.FBlocks[Index] := TDidacticBlock.FromJson(TJSONObject(Blocks.Items[Index]));
    end;
    SetLength(Result.FPending, Pending.Count);
    for Index := 0 to Pending.Count - 1 do
    begin
      if not (Pending.Items[Index] is TJSONObject) then raise EDidacticValidation.Create('Pending object required.');
      Result.FPending[Index] := TDocumentTransaction.FromJson(TJSONObject(Pending.Items[Index]));
    end;
    Result.Validate;
  except Result.Free; raise; end;
end;

function TDidacticChain.Clone: TDidacticChain;
var Document: TJSONObject;
begin
  Document := ToJson;
  try Result := FromJson(Document, FPolicy); finally Document.Free; end;
end;

procedure TDidacticChain.Save(const APath: string);
var Snapshot, Envelope: TJSONObject; Payload: string;
begin
  Validate;
  Snapshot := ToJson;
  Envelope := TJSONObject.Create;
  try
    Payload := Snapshot.ToJSON;
    Envelope.AddPair('schema', '1');
    Envelope.AddPair('sha256', Sha256Bytes(TEncoding.UTF8.GetBytes(Payload)));
    Envelope.AddPair('payload', Payload);
    if TEncoding.UTF8.GetByteCount(Envelope.ToJSON) > MaxSnapshotBytes then raise EDidacticValidation.Create('Snapshot too large.');
    SaveAtomicUtf8(APath, Envelope.ToJSON);
  finally Envelope.Free; Snapshot.Free; end;
end;

class function TDidacticChain.Load(const APath: string; const APolicy: TDidacticPolicy): TDidacticChain;
var Envelope, Snapshot: TJSONValue; Payload: string;
begin
  if TFile.GetSize(APath) > MaxSnapshotBytes then raise EDidacticValidation.Create('Snapshot too large.');
  Envelope := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  try
    if not (Envelope is TJSONObject) then raise EDidacticValidation.Create('Snapshot envelope required.');
    RequireFields(TJSONObject(Envelope), ['schema','sha256','payload']);
    if JsonText(TJSONObject(Envelope), 'schema') <> '1' then raise EDidacticValidation.Create('Unsupported storage schema.');
    Payload := JsonText(TJSONObject(Envelope), 'payload');
    if JsonText(TJSONObject(Envelope), 'sha256') <> Sha256Bytes(TEncoding.UTF8.GetBytes(Payload)) then
      raise EDidacticValidation.Create('Storage checksum mismatch.');
    Snapshot := TJSONObject.ParseJSONValue(Payload);
    try
      if not (Snapshot is TJSONObject) then raise EDidacticValidation.Create('Snapshot object required.');
      Result := FromJson(TJSONObject(Snapshot), APolicy);
    finally Snapshot.Free; end;
  finally Envelope.Free; end;
end;

end.
