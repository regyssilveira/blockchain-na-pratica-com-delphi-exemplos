unit Didactic.Core.Tests;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TDidacticCoreTests = class
  public
    [Test]
    [TestCase('D2', '2')]
    [TestCase('D3', '3')]
    [TestCase('D4', '4')]
    procedure GenesisMatchesIndependentBytes(const ADifficulty: Integer);
    [Test] procedure TransactionAndBlockMatchIndependentOracle;
    [Test] procedure InvalidLongerHistoryCannotWin;
    [Test] procedure AdvertisedWorkAndChangedDifficultyAreRejected;
    [Test]
    [TestCase('LeadingZero', '01')]
    [TestCase('Negative', '-1')]
    [TestCase('Plus', '+1')]
    [TestCase('Fraction', '1.0')]
    [TestCase('Exponent', '1e2')]
    [TestCase('Overflow', '18446744073709551616')]
    procedure RejectNoncanonicalInteger(const AValue: string);
    [Test] procedure ExactIntegersAndDeterministicSignature;
    [Test]
    [TestCase('Document', 'document')]
    [TestCase('Network', 'network')]
    [TestCase('PublicKey', 'public')]
    [TestCase('Sequence', 'sequence')]
    [TestCase('R', 'r')]
    [TestCase('S', 's')]
    [TestCase('Parity', 'parity')]
    procedure SignedTransactionTampering(const AField: string);
    [Test] procedure JsonIsTransportNotHashRepresentation;
    [Test] procedure JsonRejectsUnknownAndDuplicateFields;
    [Test] procedure PendingInclusionReplayAndAccountIsolation;
    [Test] procedure InvalidSequenceAndBusinessDuplicate;
    [Test] procedure ChangedBlockAndRecomputedOldLink;
    [Test] procedure InvalidBlockDoesNotMutateChain;
    [Test] procedure PersistenceRestoresPendingAndConfirmed;
    [Test]
    [TestCase('Truncated', 'truncated')]
    [TestCase('Checksum', 'checksum')]
    [TestCase('TamperedChain', 'chain')]
    [TestCase('Schema', 'schema')]
    procedure CorruptStorageNeverLoads(const ACase: string);
    [Test] procedure FailedAtomicReplacementPreservesPreviousFile;
    [Test] procedure FixedGenesisAndDifficultyAreMandatory;
    [Test] procedure MiningBoundsAndDifficultyExperiments;
    [Test] procedure ValidEqualForkIsKeptUntilMoreWork;
    [Test] procedure OrphanRequeueAndConflictingSequenceDiscard;
    [Test] procedure SameTipCanSynchronizePending;
    [Test] procedure PoolAndSnapshotBounds;
  end;

implementation

uses System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  Winapi.Windows, Didactic.Codec, Didactic.Transaction, Didactic.Block,
  Didactic.Chain, Blockchain.Primitives, Blockchain.Ethereum;

function Key(const AValue: Integer = 1): TBytes;
begin
  Result := DecodeHex(StringOfChar('0', 63) + IntToHex(AValue, 1).ToLower);
end;

function Doc(const AValue: string): string;
begin
  Result := Sha256Bytes(TEncoding.UTF8.GetBytes(AValue));
end;

function Tx(const AValue: string; const ASequence: UInt64 = 1;
  const AKey: Integer = 1): TDocumentTransaction;
begin
  Result := TDocumentTransaction.Sign(TDidacticPolicy.Create, Key(AKey), Doc(AValue), ASequence);
end;

function PathForTest: string;
var Identifier: TGUID;
begin
  CreateGUID(Identifier);
  Result := 'build\Didactic\storage\' + GUIDToString(Identifier) + '.json';
end;

procedure Seal(const AChain: TDidacticChain; const ATimestamp: UInt64);
var Mining: TMiningResult;
begin
  Mining := AChain.Mine(ATimestamp);
  Assert.IsTrue(Mining.Found);
end;

procedure TDidacticCoreTests.GenesisMatchesIndependentBytes(const ADifficulty: Integer);
var Document: TJSONValue; Vector: TJSONObject; Block, Mined: TDidacticBlock;
  Policy: TDidacticPolicy; Mining: TMiningResult;
begin
  Policy := TDidacticPolicy.Create(ADifficulty);
  Document := TJSONObject.ParseJSONValue(TFile.ReadAllText('fixtures\didactic\genesis-reference.json', TEncoding.UTF8));
  try
    Vector := Document.GetValue<TJSONArray>('vectors').Items[ADifficulty - 2] as TJSONObject;
    Block := GenesisBlock(Policy);
    Assert.AreEqual(Vector.GetValue<string>('hash'), Block.Hash);
    Assert.AreEqual(Vector.GetValue<string>('nonce'), UIntToStr(Block.Nonce));
    Assert.AreEqual(Vector.GetValue<string>('canonicalHex'), BytesToLowerHex(Block.CanonicalBytes(Policy)));
    Mined := Block;
    Mining := MineBlock(Mined, Policy, 1000000, 5000);
    Assert.IsTrue(Mining.Found);
    Assert.AreEqual(Block.Hash, Mined.Hash);
    Assert.AreEqual(Block.Nonce + 1, Mining.Attempts);
  finally Document.Free; end;
end;

procedure TDidacticCoreTests.RejectNoncanonicalInteger(const AValue: string);
begin
  Assert.WillRaise(procedure begin CanonicalUInt(AValue); end, EDidacticValidation);
end;

procedure TDidacticCoreTests.TransactionAndBlockMatchIndependentOracle;
var Reference: TJSONValue; Transaction: TDocumentTransaction; Block: TDidacticBlock;
  Mining: TMiningResult; Policy: TDidacticPolicy;
begin
  Policy := TDidacticPolicy.Create;
  Reference := TJSONObject.ParseJSONValue(TFile.ReadAllText('fixtures\didactic\transaction-reference.json', TEncoding.UTF8));
  try
    Transaction := TDocumentTransaction.Sign(Policy, Key, Sha256File('fixtures\p02\document-a.txt'), 1);
    Assert.AreEqual(Reference.GetValue<string>('payloadHex'), BytesToLowerHex(Transaction.Payload));
    Assert.AreEqual(Reference.GetValue<string>('signingDigest'), Sha256Bytes(Transaction.Payload));
    Assert.AreEqual(Reference.GetValue<string>('r'), Transaction.SignatureR);
    Assert.AreEqual(Reference.GetValue<string>('s'), Transaction.SignatureS);
    Assert.AreEqual(Reference.GetValue<string>('parity'), UIntToStr(Transaction.Parity));
    Assert.AreEqual(Reference.GetValue<string>('account'), Transaction.Account);
    Assert.AreEqual(Reference.GetValue<string>('id'), Transaction.Id);
    Assert.AreEqual(Reference.GetValue<string>('signedHex'), BytesToLowerHex(Transaction.SignedBytes));
    Block := Default(TDidacticBlock);
    Block.Height := 1; Block.Timestamp := 1; Block.Difficulty := 2;
    Block.PreviousHash := GenesisBlock(Policy).Hash;
    Block.Transactions := TArray<TDocumentTransaction>.Create(Transaction);
    Mining := MineBlock(Block, Policy);
    Assert.IsTrue(Mining.Found);
    Assert.AreEqual(Reference.GetValue<string>('block.hash'), Block.Hash);
    Assert.AreEqual(Reference.GetValue<string>('block.nonce'), UIntToStr(Block.Nonce));
    Assert.AreEqual(Reference.GetValue<string>('block.canonicalHex'), BytesToLowerHex(Block.CanonicalBytes(Policy)));
  finally Reference.Free; end;
end;

procedure TDidacticCoreTests.InvalidLongerHistoryCannotWin;
var Current, Longer: TDidacticChain; First, Second: TDidacticBlock;
  Snapshot: TJSONObject; Blocks: TJSONArray; Mining: TMiningResult; Original: string;
begin
  Current := TDidacticChain.Create(TDidacticPolicy.Create);
  Longer := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Current.Submit(Tx('trusted-current')); Seal(Current, 1); Original := Current.Tip.Hash;
    Longer.Submit(Tx('a')); Seal(Longer, 1); Longer.Submit(Tx('b', 2)); Seal(Longer, 2);
    First := Longer.BlockAt(1); Second := Longer.BlockAt(2);
    First.Transactions[0].DocumentHash := Doc('altered-without-key');
    Mining := MineBlock(First, TDidacticPolicy.Create); Assert.IsTrue(Mining.Found);
    Second.PreviousHash := First.Hash;
    Mining := MineBlock(Second, TDidacticPolicy.Create); Assert.IsTrue(Mining.Found);
    Snapshot := Longer.ToJson;
    try
      Blocks := Snapshot.GetValue<TJSONArray>('blocks');
      Blocks.Remove(2).Free; Blocks.Remove(1).Free;
      Blocks.AddElement(First.ToJson); Blocks.AddElement(Second.ToJson);
      Assert.WillRaise(procedure var Invalid: TDidacticChain; begin
        Invalid := TDidacticChain.FromJson(Snapshot, TDidacticPolicy.Create);
        try Current.Consider(Invalid); finally Invalid.Free; end;
      end, EDidacticValidation);
      Assert.AreEqual(Original, Current.Tip.Hash);
    finally Snapshot.Free; end;
  finally Longer.Free; Current.Free; end;
end;

procedure TDidacticCoreTests.AdvertisedWorkAndChangedDifficultyAreRejected;
var Chain: TDidacticChain; Document: TJSONObject; Block: TDidacticBlock;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Chain.Submit(Tx('a')); Seal(Chain, 1);
    Document := Chain.ToJson;
    try
      Document.AddPair('work', '18446744073709551615');
      Assert.WillRaise(procedure var Invalid: TDidacticChain; begin
        Invalid := TDidacticChain.FromJson(Document, TDidacticPolicy.Create); Invalid.Free;
      end, EDidacticValidation);
    finally Document.Free; end;
    Block := Chain.Tip; Block.Difficulty := 3;
    Assert.WillRaise(procedure begin Block.ValidateContent(TDidacticPolicy.Create); end, EDidacticValidation);
    Block.Difficulty := 0;
    Assert.WillRaise(procedure begin Block.ValidateContent(TDidacticPolicy.Create); end, EDidacticValidation);
  finally Chain.Free; end;
end;

procedure TDidacticCoreTests.ExactIntegersAndDeterministicSignature;
var First, Second: TDocumentTransaction; Document: TJSONObject;
begin
  First := Tx('a', 9007199254740993);
  Second := Tx('a', 9007199254740993);
  Assert.AreEqual(First.Id, Second.Id);
  Assert.AreEqual('0020000000000001', BytesToLowerHex(UIntBytes(First.Sequence, 8)));
  Document := First.ToJson;
  try
    Second := TDocumentTransaction.FromJson(Document);
    Second.Validate(TDidacticPolicy.Create);
    Assert.AreEqual(First.Id, Second.Id);
    Assert.AreEqual('9007199254740993', JsonText(Document, 'sequence'));
  finally Document.Free; end;
  First := Tx('a', High(UInt64));
  First.Validate(TDidacticPolicy.Create);
  Assert.AreEqual('ffffffffffffffff', BytesToLowerHex(UIntBytes(First.Sequence, 8)));
  Assert.WillRaise(procedure begin Tx('a', 0); end, EDidacticValidation);
end;

procedure TDidacticCoreTests.SignedTransactionTampering(const AField: string);
var Transaction: TDocumentTransaction;
begin
  Transaction := Tx('a');
  if AField = 'document' then Transaction.DocumentHash := Doc('b');
  if AField = 'network' then Transaction.Network := 'foreign-network';
  if AField = 'public' then Transaction.PublicKey := '05' + Copy(Transaction.PublicKey, 3, MaxInt);
  if AField = 'sequence' then Transaction.Sequence := 2;
  if AField = 'r' then Transaction.SignatureR := StringOfChar('0', 64);
  if AField = 's' then Transaction.SignatureS := StringOfChar('f', 64);
  if AField = 'parity' then Transaction.Parity := 2;
  Assert.WillRaise(procedure begin Transaction.Validate(TDidacticPolicy.Create); end, EDidacticValidation);
end;

procedure TDidacticCoreTests.JsonIsTransportNotHashRepresentation;
var Transaction, Parsed: TDocumentTransaction; Original, Reordered: TJSONObject; Index: Integer;
begin
  Transaction := Tx('a');
  Original := Transaction.ToJson;
  Reordered := TJSONObject.Create;
  try
    for Index := Original.Count - 1 downto 0 do
      Reordered.AddPair(Original.Pairs[Index].JsonString.Value, Original.Pairs[Index].JsonValue.Clone as TJSONValue);
    Parsed := TDocumentTransaction.FromJson(Reordered);
    Assert.AreEqual(Transaction.Id, Parsed.Id);
    Assert.AreNotEqual(Original.ToJSON, Reordered.ToJSON);
  finally Reordered.Free; Original.Free; end;
end;

procedure TDidacticCoreTests.JsonRejectsUnknownAndDuplicateFields;
var Document: TJSONObject; Transaction: TDocumentTransaction;
begin
  Transaction := Tx('a');
  Document := Transaction.ToJson;
  try
    Document.AddPair('extra', 'ignored?');
    Assert.WillRaise(procedure begin TDocumentTransaction.FromJson(Document); end, EDidacticValidation);
    Document.RemovePair('extra').Free;
    Document.RemovePair('network').Free;
    Document.AddPair('sequence', '1');
    Assert.WillRaise(procedure begin TDocumentTransaction.FromJson(Document); end, EDidacticValidation);
  finally Document.Free; end;
end;

procedure TDidacticCoreTests.PendingInclusionReplayAndAccountIsolation;
var Chain: TDidacticChain; First, Other: TDocumentTransaction; Entry: TDocumentEntry;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    First := Tx('a');
    Other := Tx('a', 1, 2);
    Assert.IsTrue(Chain.Submit(First));
    Assert.IsFalse(Chain.Submit(First));
    Assert.AreEqual(1, Chain.PendingCount);
    Assert.AreEqual('pending', Chain.TransactionState(First.Id));
    Assert.IsFalse(Chain.Lookup(First.Account, First.DocumentHash).Exists);
    Assert.IsTrue(Chain.Submit(Other));
    Seal(Chain, 1);
    Entry := Chain.Lookup(First.Account, First.DocumentHash);
    Assert.IsTrue(Entry.Exists);
    Assert.AreEqual(UInt64(1), Entry.BlockHeight);
    Assert.AreEqual(First.Id, Entry.TransactionId);
    Assert.IsTrue(Chain.Lookup(Other.Account, Other.DocumentHash).Exists);
    Assert.AreEqual('confirmed', Chain.TransactionState(First.Id));
    Assert.IsFalse(Chain.Submit(First));
    Assert.AreEqual(0, Chain.PendingCount);
  finally Chain.Free; end;
end;

procedure TDidacticCoreTests.InvalidSequenceAndBusinessDuplicate;
var Chain: TDidacticChain;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Assert.WillRaise(procedure begin Chain.Submit(Tx('gap', 2)); end, EDidacticValidation);
    Chain.Submit(Tx('a'));
    Assert.WillRaise(procedure begin Chain.Submit(Tx('a', 2)); end, EDidacticValidation);
    Assert.WillRaise(procedure begin Chain.Submit(Tx('different', 1)); end, EDidacticValidation);
    Assert.AreEqual(1, Chain.PendingCount);
    Seal(Chain, 1);
    Assert.WillRaise(procedure begin Chain.Submit(Tx('a', 2)); end, EDidacticValidation);
    Assert.IsTrue(Chain.Submit(Tx('next', 2)));
  finally Chain.Free; end;
end;

procedure TDidacticCoreTests.ChangedBlockAndRecomputedOldLink;
var First, Second: TDidacticBlock; Policy: TDidacticPolicy;
begin
  Policy := TDidacticPolicy.Create;
  First := GenesisBlock(Policy);
  Second := Default(TDidacticBlock);
  Second.Height := 1;
  Second.Timestamp := 1;
  Second.Difficulty := 2;
  Second.PreviousHash := First.Hash;
  Second.Transactions := TArray<TDocumentTransaction>.Create(Tx('a'));
  Second.Hash := Second.CalculateHash(Policy);
  Second.ValidateLink(Policy, First);
  First.Timestamp := 10;
  First.Hash := First.CalculateHash(Policy);
  Assert.WillRaise(procedure begin Second.ValidateLink(Policy, First); end, EDidacticValidation);
  Second.PreviousHash := First.Hash;
  Second.Timestamp := 11;
  Assert.WillRaise(procedure begin Second.ValidateLink(Policy, First); end, EDidacticValidation);
end;

procedure TDidacticCoreTests.InvalidBlockDoesNotMutateChain;
var Chain, Other: TDidacticChain; Block: TDidacticBlock; OldHash: string;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  Other := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Other.Submit(Tx('a'));
    Seal(Other, 1);
    Block := Other.Tip;
    Block.Transactions[0].DocumentHash := Doc('tampered');
    OldHash := Chain.Tip.Hash;
    Assert.WillRaise(procedure begin Chain.AcceptBlock(Block); end, EDidacticValidation);
    Assert.AreEqual(OldHash, Chain.Tip.Hash);
    Assert.AreEqual(1, Chain.BlockCount);
    // Getter nao permite alterar o bloco interno por alias de array.
    Assert.AreNotEqual(Block.Transactions[0].DocumentHash, Other.Tip.Transactions[0].DocumentHash);
  finally Other.Free; Chain.Free; end;
end;

procedure TDidacticCoreTests.PersistenceRestoresPendingAndConfirmed;
var Chain, Restored: TDidacticChain; Path: string; Transaction: TDocumentTransaction;
begin
  Path := PathForTest;
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Transaction := Tx('a');
    Chain.Submit(Transaction);
    Chain.Save(Path);
    Restored := TDidacticChain.Load(Path, TDidacticPolicy.Create);
    try
      Assert.AreEqual(1, Restored.PendingCount);
      Seal(Restored, 1);
      Restored.Save(Path);
    finally Restored.Free; end;
    Restored := TDidacticChain.Load(Path, TDidacticPolicy.Create);
    try
      Assert.AreEqual('confirmed', Restored.TransactionState(Transaction.Id));
      Assert.AreEqual(0, Restored.PendingCount);
      Assert.IsTrue(Restored.Lookup(Transaction.Account, Transaction.DocumentHash).Exists);
    finally Restored.Free; end;
  finally Chain.Free; end;
end;

procedure TDidacticCoreTests.CorruptStorageNeverLoads(const ACase: string);
var Chain, Restored: TDidacticChain; Path, Payload: string; Envelope, Snapshot: TJSONObject;
begin
  Path := PathForTest;
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Chain.Submit(Tx('a'));
    Seal(Chain, 1);
    Chain.Save(Path);
  finally Chain.Free; end;
  Envelope := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    if ACase = 'truncated' then TFile.WriteAllText(Path, '{', TEncoding.UTF8)
    else
    begin
      if ACase = 'checksum' then begin Envelope.RemovePair('sha256').Free; Envelope.AddPair('sha256', StringOfChar('0', 64)); end;
      if ACase = 'schema' then begin Envelope.RemovePair('schema').Free; Envelope.AddPair('schema', '99'); end;
      if ACase = 'chain' then
      begin
        Snapshot := TJSONObject.ParseJSONValue(JsonText(Envelope, 'payload')) as TJSONObject;
        try
          TJSONObject(Snapshot.GetValue<TJSONArray>('blocks').Items[1]).RemovePair('hash').Free;
          TJSONObject(Snapshot.GetValue<TJSONArray>('blocks').Items[1]).AddPair('hash', StringOfChar('f', 64));
          Payload := Snapshot.ToJSON;
        finally Snapshot.Free; end;
        Envelope.RemovePair('payload').Free;
        Envelope.RemovePair('sha256').Free;
        Envelope.AddPair('payload', Payload);
        Envelope.AddPair('sha256', Sha256Bytes(TEncoding.UTF8.GetBytes(Payload)));
      end;
      TFile.WriteAllText(Path, Envelope.ToJSON, TEncoding.UTF8);
    end;
  finally Envelope.Free; end;
  Assert.WillRaise(procedure begin
    Restored := TDidacticChain.Load(Path, TDidacticPolicy.Create);
    Restored.Free;
  end, EDidacticValidation);
end;

procedure TDidacticCoreTests.FailedAtomicReplacementPreservesPreviousFile;
var Chain, Restored: TDidacticChain; Path, Original: string;
begin
  Path := TPath.GetFullPath(PathForTest);
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Chain.Save(Path);
    Original := TFile.ReadAllText(Path, TEncoding.UTF8);
    Chain.Submit(Tx('a'));
    Seal(Chain, 1);
    Assert.IsTrue(SetFileAttributes(PChar(Path), FILE_ATTRIBUTE_READONLY));
    try Assert.WillRaise(procedure begin Chain.Save(Path); end, EOSError);
    finally SetFileAttributes(PChar(Path), FILE_ATTRIBUTE_NORMAL); end;
    Assert.AreEqual(Original, TFile.ReadAllText(Path, TEncoding.UTF8));
    Restored := TDidacticChain.Load(Path, TDidacticPolicy.Create);
    try Assert.AreEqual(1, Restored.BlockCount); finally Restored.Free; end;
  finally Chain.Free; end;
end;

procedure TDidacticCoreTests.FixedGenesisAndDifficultyAreMandatory;
var Chain, Other: TDidacticChain; Snapshot: TJSONObject;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  Other := TDidacticChain.Create(TDidacticPolicy.Create(3));
  try
    Assert.WillRaise(procedure begin Chain.Consider(Other); end, EDidacticValidation);
    Snapshot := Chain.ToJson;
    try
      TJSONObject(Snapshot.GetValue<TJSONArray>('blocks').Items[0]).RemovePair('hash').Free;
      TJSONObject(Snapshot.GetValue<TJSONArray>('blocks').Items[0]).AddPair('hash', StringOfChar('0', 64));
      Assert.WillRaise(procedure var Invalid: TDidacticChain; begin
        Invalid := TDidacticChain.FromJson(Snapshot, TDidacticPolicy.Create); Invalid.Free;
      end, EDidacticValidation);
    finally Snapshot.Free; end;
  finally Other.Free; Chain.Free; end;
end;

procedure TDidacticCoreTests.MiningBoundsAndDifficultyExperiments;
var Block: TDidacticBlock; Mining: TMiningResult; Policy: TDidacticPolicy;
begin
  Policy := TDidacticPolicy.Create(4);
  Block := GenesisBlock(Policy);
  Mining := MineBlock(Block, Policy, 1, 2000);
  Assert.IsFalse(Mining.Found);
  Assert.AreEqual(UInt64(1), Mining.Attempts);
  Assert.AreEqual('', Block.Hash);
  Mining := MineBlock(Block, Policy, 100000, 2000, function: Boolean begin Result := True; end);
  Assert.IsFalse(Mining.Found);
  Assert.AreEqual(UInt64(0), Mining.Attempts);
  Assert.WillRaise(procedure begin MineBlock(Block, Policy, 0, 1); end, EDidacticValidation);
end;

procedure TDidacticCoreTests.ValidEqualForkIsKeptUntilMoreWork;
var First, Second: TDidacticChain; Original: string;
begin
  First := TDidacticChain.Create(TDidacticPolicy.Create);
  Second := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    First.Submit(Tx('a')); Seal(First, 1);
    Second.Submit(Tx('b')); Seal(Second, 1);
    First.Validate; Second.Validate;
    Original := First.Tip.Hash;
    Assert.AreNotEqual(Original, Second.Tip.Hash);
    Assert.IsFalse(First.Consider(Second));
    Assert.AreEqual(Original, First.Tip.Hash);
    Second.Submit(Tx('c', 2)); Seal(Second, 2);
    Assert.IsTrue(First.Consider(Second));
    Assert.AreEqual(Second.Tip.Hash, First.Tip.Hash);
    Assert.AreEqual(UInt64(512), First.TotalWork);
    Assert.AreEqual('absent', First.TransactionState(Tx('a').Id));
  finally Second.Free; First.Free; end;
end;

procedure TDidacticCoreTests.OrphanRequeueAndConflictingSequenceDiscard;
var First, Second: TDidacticChain; Orphan: TDocumentTransaction;
begin
  First := TDidacticChain.Create(TDidacticPolicy.Create);
  Second := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Orphan := Tx('a'); First.Submit(Orphan); Seal(First, 1);
    Second.Submit(Tx('b', 1, 2)); Seal(Second, 1);
    Second.Submit(Tx('c', 2, 2)); Seal(Second, 2);
    Assert.IsTrue(First.Consider(Second));
    Assert.AreEqual('pending', First.TransactionState(Orphan.Id));
    Assert.IsFalse(First.Lookup(Orphan.Account, Orphan.DocumentHash).Exists);
    Seal(First, 3);
    Assert.AreEqual('confirmed', First.TransactionState(Orphan.Id));
    Assert.IsTrue(Second.Consider(First));
    Assert.AreEqual(First.Tip.Hash, Second.Tip.Hash);
  finally Second.Free; First.Free; end;
end;

procedure TDidacticCoreTests.SameTipCanSynchronizePending;
var First, Second: TDidacticChain;
begin
  First := TDidacticChain.Create(TDidacticPolicy.Create);
  Second := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    Second.Submit(Tx('a'));
    Assert.IsTrue(First.Consider(Second));
    Assert.AreEqual(1, First.PendingCount);
    Assert.IsFalse(First.Consider(Second));
  finally Second.Free; First.Free; end;
end;

procedure TDidacticCoreTests.PoolAndSnapshotBounds;
var Chain: TDidacticChain; Index: Integer; Snapshot: TJSONObject; Blocks: TJSONArray;
begin
  Chain := TDidacticChain.Create(TDidacticPolicy.Create);
  try
    for Index := 1 to MaxPendingTransactions do Chain.Submit(Tx(IntToStr(Index), Index));
    Assert.AreEqual(MaxPendingTransactions, Chain.PendingCount);
    Assert.IsFalse(Chain.Submit(Tx('1')));
    Assert.WillRaise(procedure begin Chain.Submit(Tx('overflow', MaxPendingTransactions + 1)); end, EDidacticValidation);
    Seal(Chain, 1);
    Assert.AreEqual(MaxPendingTransactions - MaxBlockTransactions, Chain.PendingCount);
    Snapshot := Chain.ToJson;
    try
      Blocks := Snapshot.GetValue<TJSONArray>('blocks');
      while Blocks.Count <= MaxDidacticBlocks do Blocks.AddElement(GenesisBlock(TDidacticPolicy.Create).ToJson);
      Assert.WillRaise(procedure var Oversized: TDidacticChain; begin
        Oversized := TDidacticChain.FromJson(Snapshot, TDidacticPolicy.Create); Oversized.Free;
      end, EDidacticValidation);
    finally Snapshot.Free; end;
  finally Chain.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDidacticCoreTests);
end.
