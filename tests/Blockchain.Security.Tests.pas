unit Blockchain.Security.Tests;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TLocalProtectionTests = class
  public
    [Test] procedure RoundTripPreservesInput;
    [Test] procedure WrongAccountIsRefused;
    [Test] procedure EmptyKeyIsRefused;
    [Test] procedure ZeroScalarIsRefused;
    [Test] procedure LargeScalarIsRefused;
    [Test] procedure WrongHeaderIsRefused;
    [Test] procedure TruncatedBlobIsRefused;
    [Test] procedure AlteredBlobIsRefused;
    [Test] procedure InvalidExpectedAccountIsRefused;
    [Test] procedure SaveNewCannotOverwrite;
    [Test] procedure OversizedFileIsRefused;
    [Test] procedure MissingFileIsNotEmptyKey;
    [Test] procedure ClearOwnDoesNotEraseIndependentCopy;
  end;

  [TestFixture]
  TTrackingAuditTests = class
  public
    [Test] procedure OnlyAllowedFieldsAreExported;
    [Test] procedure InvalidStateIsRefused;
    [Test] procedure ExportDoesNotMutateCheckpoint;
    [Test] procedure ClientFailureDoesNotReuseHistoricalSuccess;
    [Test] procedure SmallDictionaryCanIdentifyHash;
  end;

implementation

uses System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  Blockchain.LocalKeyProtection, Blockchain.Ethereum, Blockchain.Primitives,
  Blockchain.TransactionJournal, Blockchain.TrackingAudit, Blockchain.RegistryWorkflow;

function PublishedKey: TBytes;
begin
  Result := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
end;

function PublishedAccount: TBytes;
begin
  Result := AddressFromPublicKey(PublicKeyFromPrivateKey(PublishedKey));
end;

function OwnedPath: string;
var Identifier: TGUID;
begin
  CreateGUID(Identifier);
  Result := TPath.GetFullPath(TPath.Combine('build\Security', GUIDToString(Identifier) + '.dpapi'));
end;

function ExampleCheckpoint: TTransactionCheckpoint;
var Transaction: TType2Transaction; Raw: TBytes;
begin
  Transaction := Default(TType2Transaction);
  Transaction.ChainId := TExactUInt256.FromDecimal('31337');
  Transaction.Nonce := TExactUInt256.FromDecimal('0');
  Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('1000000000');
  Transaction.MaxFeePerGas := TExactUInt256.FromDecimal('3000000000');
  Transaction.GasLimit := TExactUInt256.FromDecimal('21000');
  Transaction.Destination := DecodeHex(StringOfChar('0', 40));
  Transaction.Amount := TExactUInt256.FromDecimal('0');
  Raw := Transaction.SignedEnvelope(SignDigest(Transaction.SigningHash, PublishedKey));
  Result := Default(TTransactionCheckpoint);
  Result.Port := 19345;
  Result.ChainId := '31337';
  Result.RuntimeHex := '0x00';
  Result.Account := '0x' + BytesToLowerHex(PublishedAccount);
  Result.DocumentHash := Sha256Bytes(TEncoding.UTF8.GetBytes('sensitive document marker'));
  Result.Hash := '0x' + BytesToLowerHex(Keccak256(Raw));
  Result.RawHex := '0x' + BytesToLowerHex(Raw);
  Result.State := 'unknown';
  Result.Diagnostic := 'DO-NOT-LOG-NODE-MESSAGE ' + BytesToLowerHex(PublishedKey);
end;

procedure TLocalProtectionTests.RoundTripPreservesInput;
var Key, Before, ProtectedBytes, Recovered: TBytes;
begin
  Key := PublishedKey;
  Before := Copy(Key);
  ProtectedBytes := TLocalKeyProtection.Protect(Key);
  Recovered := TLocalKeyProtection.Unprotect(ProtectedBytes, PublishedAccount);
  try
    Assert.AreEqual(BytesToLowerHex(Before), BytesToLowerHex(Recovered));
    Assert.AreEqual(BytesToLowerHex(Before), BytesToLowerHex(Key));
    Assert.IsTrue(Length(ProtectedBytes) > 32);
  finally TLocalKeyProtection.ClearOwned(Recovered); end;
end;

procedure TLocalProtectionTests.WrongAccountIsRefused;
var ProtectedBytes, OtherAccount: TBytes;
begin
  ProtectedBytes := TLocalKeyProtection.Protect(PublishedKey);
  OtherAccount := AddressFromPublicKey(PublicKeyFromPrivateKey(DecodeHex(StringOfChar('0', 63) + '1')));
  Assert.WillRaise(procedure begin TLocalKeyProtection.Unprotect(ProtectedBytes, OtherAccount); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.EmptyKeyIsRefused;
begin
  Assert.WillRaise(procedure begin TLocalKeyProtection.Protect(nil); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.ZeroScalarIsRefused;
begin
  Assert.WillRaise(procedure begin TLocalKeyProtection.Protect(DecodeHex(StringOfChar('0', 64))); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.LargeScalarIsRefused;
begin
  Assert.WillRaise(procedure begin TLocalKeyProtection.Protect(DecodeHex(StringOfChar('f', 64))); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.WrongHeaderIsRefused;
var ProtectedBytes: TBytes;
begin
  ProtectedBytes := TLocalKeyProtection.Protect(PublishedKey);
  ProtectedBytes[3] := Ord('2');
  Assert.WillRaise(procedure begin TLocalKeyProtection.Unprotect(ProtectedBytes, PublishedAccount); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.TruncatedBlobIsRefused;
begin
  Assert.WillRaise(procedure begin
    TLocalKeyProtection.Unprotect(TBytes.Create($44, $50, $4B, $31, 1, 2, 3), PublishedAccount);
  end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.AlteredBlobIsRefused;
var ProtectedBytes: TBytes;
begin
  ProtectedBytes := TLocalKeyProtection.Protect(PublishedKey);
  ProtectedBytes[High(ProtectedBytes)] := ProtectedBytes[High(ProtectedBytes)] xor 1;
  Assert.WillRaise(procedure begin TLocalKeyProtection.Unprotect(ProtectedBytes, PublishedAccount); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.InvalidExpectedAccountIsRefused;
var ProtectedBytes: TBytes;
begin
  ProtectedBytes := TLocalKeyProtection.Protect(PublishedKey);
  Assert.WillRaise(procedure begin TLocalKeyProtection.Unprotect(ProtectedBytes, nil); end, ELocalKeyProtection);
end;

procedure TLocalProtectionTests.SaveNewCannotOverwrite;
var Path, Before: string; ProtectedBytes: TBytes;
begin
  Path := OwnedPath;
  ProtectedBytes := TLocalKeyProtection.Protect(PublishedKey);
  TLocalKeyProtection.SaveNew(Path, ProtectedBytes);
  try
    Before := Sha256File(Path);
    Assert.WillRaise(procedure begin TLocalKeyProtection.SaveNew(Path, ProtectedBytes); end, ELocalKeyProtection);
    Assert.AreEqual(Before, Sha256File(Path));
  finally TFile.Delete(Path); end;
end;

procedure TLocalProtectionTests.OversizedFileIsRefused;
var Path: string; Data: TBytes;
begin
  Path := OwnedPath;
  SetLength(Data, 65537);
  TFile.WriteAllBytes(Path, Data);
  try Assert.WillRaise(procedure begin TLocalKeyProtection.Load(Path, PublishedAccount); end, ELocalKeyProtection);
  finally TFile.Delete(Path); end;
end;

procedure TLocalProtectionTests.MissingFileIsNotEmptyKey;
var Path: string;
begin
  Path := OwnedPath;
  Assert.WillRaise(procedure begin TLocalKeyProtection.Load(Path, PublishedAccount); end, EFOpenError);
end;

procedure TLocalProtectionTests.ClearOwnDoesNotEraseIndependentCopy;
var Key, Alias, Separate: TBytes;
begin
  Key := PublishedKey;
  Alias := Key;
  Separate := Copy(Key);
  TLocalKeyProtection.ClearOwned(Key);
  try
    Assert.AreEqual(0, Length(Key));
    Assert.AreEqual(StringOfChar('0', 64), BytesToLowerHex(Alias));
    Assert.AreEqual(BytesToLowerHex(PublishedKey), BytesToLowerHex(Separate));
  finally TLocalKeyProtection.ClearOwned(Alias); TLocalKeyProtection.ClearOwned(Separate); end;
end;

procedure TTrackingAuditTests.OnlyAllowedFieldsAreExported;
var Checkpoint: TTransactionCheckpoint; Document: TJSONObject; Text: string;
begin
  Checkpoint := ExampleCheckpoint;
  Document := MinimalTrackingAudit(Checkpoint);
  try
    Assert.AreEqual(4, Document.Count);
    Assert.AreEqual(Checkpoint.Hash, Document.GetValue<string>('transactionHash'));
    Text := Document.ToJSON;
    Assert.IsFalse(Text.Contains('DO-NOT-LOG-NODE-MESSAGE'));
    Assert.IsFalse(Text.Contains(BytesToLowerHex(PublishedKey)));
    Assert.IsFalse(Text.Contains(Checkpoint.RawHex));
    Assert.IsFalse(Text.Contains(Checkpoint.DocumentHash));
    Assert.IsFalse(Text.Contains(Checkpoint.Account));
    Checkpoint.State := 'succeeded'; Checkpoint.BlockNumber := '2';
    Document.Free;
    Document := nil;
    Document := MinimalTrackingAudit(Checkpoint);
    Assert.AreEqual('2', Document.GetValue<string>('blockNumber'));
    Assert.AreEqual(5, Document.Count);
  finally Document.Free; end;
end;

procedure TTrackingAuditTests.InvalidStateIsRefused;
var Checkpoint: TTransactionCheckpoint;
begin
  Checkpoint := ExampleCheckpoint;
  Checkpoint.State := '''
    success
    injected log
    ''';
  Assert.WillRaise(procedure
    var Document: TJSONObject;
    begin
      Document := MinimalTrackingAudit(Checkpoint);
      Document.Free;
    end, EArgumentException);
end;

procedure TTrackingAuditTests.ExportDoesNotMutateCheckpoint;
var Checkpoint, Before: TTransactionCheckpoint; Document: TJSONObject;
begin
  Checkpoint := ExampleCheckpoint;
  Before := Checkpoint;
  Document := MinimalTrackingAudit(Checkpoint);
  Document.Free;
  Assert.AreEqual(Before.RawHex, Checkpoint.RawHex);
  Assert.AreEqual(Before.Diagnostic, Checkpoint.Diagnostic);
  Assert.AreEqual(Before.Hash, Checkpoint.Hash);
  Assert.AreEqual(Before.State, Checkpoint.State);
end;


procedure TTrackingAuditTests.ClientFailureDoesNotReuseHistoricalSuccess;
var Checkpoint: TTransactionCheckpoint; Request: TRegistryRequest;
  Result: TRegistryResult; Path: string;
begin
  Checkpoint := ExampleCheckpoint;
  Checkpoint.State := 'succeeded';
  Checkpoint.BlockNumber := '2';
  Path := OwnedPath;
  Checkpoint.Save(Path);
  try
    Request := Default(TRegistryRequest);
    Request.Action := raTrackRegistration;
    Request.CheckpointPath := Path;
    Result := TRegistryWorkflow.Failure(Request, 'transport failure');
    Assert.AreEqual('unknown', Result.State);
    Assert.AreEqual('succeeded', Result.StoredState);
    Assert.AreEqual(Checkpoint.Hash, Result.TransactionHash);
    Assert.AreEqual('succeeded', TTransactionCheckpoint.Load(Path).State);
  finally TFile.Delete(Path); end;
end;

procedure TTrackingAuditTests.SmallDictionaryCanIdentifyHash;
var Candidates: TArray<string>; Candidate, RegisteredHash, Match: string;
  Count: Integer;
begin
  Candidates := TArray<string>.Create('certificado:aprovado',
    'certificado:pendente', 'certificado:cancelado');
  RegisteredHash := Sha256Bytes(TEncoding.UTF8.GetBytes('certificado:pendente'));
  Match := '';
  Count := 0;
  for Candidate in Candidates do
    if Sha256Bytes(TEncoding.UTF8.GetBytes(Candidate)) = RegisteredHash then
    begin
      Match := Candidate;
      Inc(Count);
    end;
  Assert.AreEqual(1, Count);
  Assert.AreEqual('certificado:pendente', Match);
end;

initialization
  TDUnitX.RegisterTestFixture(TLocalProtectionTests);
  TDUnitX.RegisterTestFixture(TTrackingAuditTests);

end.
