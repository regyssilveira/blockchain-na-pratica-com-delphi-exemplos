unit Blockchain.Reliability.Tests;

interface

uses DUnitX.TestFramework, System.JSON, Blockchain.LocalRpc;

type
  [TestFixture]
  TRpcFailureTests = class
  public
    [Test]
    [TestCase('MalformedJson', 'malformed')]
    [TestCase('ArrayRoot', 'array')]
    [TestCase('WrongVersion', 'version')]
    [TestCase('WrongId', 'id')]
    [TestCase('StringId', 'stringid')]
    [TestCase('FractionId', 'fractionid')]
    [TestCase('NullId', 'nullid')]
    [TestCase('MissingId', 'missingid')]
    [TestCase('ResultAndError', 'both')]
    [TestCase('MissingResult', 'missing')]
    [TestCase('ErrorString', 'errorstring')]
    [TestCase('FractionErrorCode', 'fractioncode')]
    [TestCase('InvalidErrorMessage', 'message')]
    procedure InvalidProtocolNeverSucceeds(const ACase: string);
    [Test] procedure StructuredRpcErrorIsDistinct;
    [Test] procedure HttpFailureIsNotRpcRejection;
    [Test] procedure SlowHttpCannotExtendTrackingDeadline;
    [Test]
    [TestCase('WrongReceiptType', 'type')]
    [TestCase('InvalidStatus', 'status')]
    [TestCase('WrongHash', 'hash')]
    [TestCase('MissingFields', 'fields')]
    procedure InvalidReceiptNeverSucceeds(const ACase: string);
  end;

  [TestFixture]
  TRealRecoveryTests = class
  private
    FRpc: TLocalRpc;
    FSnapshot: string;
    FArtifact: TJSONObject;
    FPort: Word;
    function RpcString(const AMethod: string; AParameters: TJSONArray): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PendingExpiresAndResumesWithoutResend;
    [Test] procedure LostResponsePreservesAcceptedHash;
    [Test] procedure JournalFailurePreventsSending;
    [Test] procedure EmptyFileIsARealDocumentInput;
    [Test] procedure NodeRejectionRemainsDifferentFromPending;
    [Test]
    [TestCase('WrongHash', 'hash')]
    [TestCase('UnknownSchema', 'schema')]
    [TestCase('ZeroPort', 'port')]
    [TestCase('UnknownState', 'state')]
    [TestCase('TruncatedJson', 'json')]
    procedure CheckpointTamperingIsRejected(const ACase: string);
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Diagnostics,
  Blockchain.HttpStub, Blockchain.DocumentRegistry, Blockchain.TransactionJournal,
  Blockchain.Ethereum, Blockchain.Primitives;

type
  TObservedRpc = class(TLocalRpc)
  public
    Sends: Integer;
    DropSendResponse: Boolean;
    JournalAtSendPath: string;
    PreparedObserved: Boolean;
    function Call(const AMethod: string; AParameters: TJSONArray;
      const ABudgetMs: Cardinal = 8000): TJSONValue; override;
  end;

function TObservedRpc.Call(const AMethod: string; AParameters: TJSONArray;
  const ABudgetMs: Cardinal): TJSONValue;
var Checkpoint: TTransactionCheckpoint;
begin
  if AMethod = 'eth_sendRawTransaction' then
  begin
    Inc(Sends);
    if JournalAtSendPath <> '' then
    begin
      Checkpoint := TTransactionCheckpoint.Load(JournalAtSendPath);
      Assert.AreEqual('unknown', Checkpoint.State, 'Persist before touching HTTP');
      Assert.AreEqual(AParameters.Items[0].Value, Checkpoint.RawHex);
      PreparedObserved := True;
    end;
  end;
  Result := inherited;
  if (AMethod = 'eth_sendRawTransaction') and DropSendResponse then
  begin
    Result.Free;
    Result := nil;
    raise ELocalRpcError.Create('SIMULATED response loss AFTER actual node acceptance.');
  end;
end;

function KnownKey: TBytes;
begin
  Result := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
end;

function JournalPath: string;
var Identifier: TGUID;
begin
  CreateGUID(Identifier);
  Result := 'build\Anvil\journals\' + GUIDToString(Identifier) + '.json';
end;

function RpcError: string;
begin
  Result := '{"code":-32601,"message":"simulated missing method"}';
end;

procedure TRpcFailureTests.InvalidProtocolNeverSucceeds(const ACase: string);
var Body: string; Server: TLocalHttpStub; Rpc: TLocalRpc;
begin
  Body := '';
  if ACase = 'malformed' then Body := '{';
  if ACase = 'array' then Body := '[]';
  if ACase = 'version' then Body := '{"jsonrpc":"1.0","id":$id,"result":null}';
  if ACase = 'id' then Body := '{"jsonrpc":"2.0","id":999,"result":null}';
  if ACase = 'stringid' then Body := '{"jsonrpc":"2.0","id":"1","result":null}';
  if ACase = 'fractionid' then Body := '{"jsonrpc":"2.0","id":1.1,"result":null}';
  if ACase = 'nullid' then Body := '{"jsonrpc":"2.0","id":null,"result":null}';
  if ACase = 'missingid' then Body := '{"jsonrpc":"2.0","result":null}';
  if ACase = 'both' then Body := '{"jsonrpc":"2.0","id":$id,"result":null,"error":' + RpcError + '}';
  if ACase = 'missing' then Body := '{"jsonrpc":"2.0","id":$id}';
  if ACase = 'errorstring' then Body := '{"jsonrpc":"2.0","id":$id,"error":"bad"}';
  if ACase = 'fractioncode' then Body := '{"jsonrpc":"2.0","id":$id,"error":{"code":1.2,"message":"bad"}}';
  if ACase = 'message' then Body := '{"jsonrpc":"2.0","id":$id,"error":{"code":1,"message":true}}';
  Assert.IsNotEmpty(Body);
  Server := TLocalHttpStub.Create(Body);
  Rpc := TLocalRpc.Create(Server.Port);
  try
    Assert.WillRaise(procedure var Value: TJSONValue; begin
      Value := Rpc.Call('simulated_test', TJSONArray.Create);
      Value.Free;
    end, ELocalRpcError);
    Assert.AreEqual(1, Server.Requests, 'No automatic retry');
    Assert.AreEqual('', Server.Failure);
  finally Rpc.Free; Server.Free; end;
end;

procedure TRpcFailureTests.StructuredRpcErrorIsDistinct;
var Server: TLocalHttpStub; Rpc: TLocalRpc;
begin
  Server := TLocalHttpStub.Create('{"jsonrpc":"2.0","id":$id,"error":' + RpcError + '}');
  Rpc := TLocalRpc.Create(Server.Port);
  try
    Assert.WillRaise(procedure var Value: TJSONValue; begin
      Value := Rpc.Call('simulated_error', TJSONArray.Create);
      Value.Free;
    end, EJsonRpcError);
    Assert.AreEqual(1, Server.Requests);
  finally Rpc.Free; Server.Free; end;
end;

procedure TRpcFailureTests.HttpFailureIsNotRpcRejection;
var Server: TLocalHttpStub; Rpc: TLocalRpc; Failed: Boolean;
begin
  Server := TLocalHttpStub.Create('{"jsonrpc":"2.0","id":$id,"result":"success"}', 0, 503);
  Rpc := TLocalRpc.Create(Server.Port);
  try
    Failed := False;
    try Rpc.Call('simulated_http_error', TJSONArray.Create).Free; except
      on Error: ELocalRpcError do
      begin
        Failed := True;
        Assert.IsFalse(Error is EJsonRpcError);
        Assert.IsTrue(Pos('503', Error.Message) > 0);
      end;
    end;
    Assert.IsTrue(Failed);
    Assert.AreEqual(1, Server.Requests);
  finally Rpc.Free; Server.Free; end;
end;

procedure TRpcFailureTests.SlowHttpCannotExtendTrackingDeadline;
var Server: TLocalHttpStub; Registry: TDocumentRegistry; Clock: TStopwatch;
  Receipt: TJSONObject; Elapsed: Int64; Evidence: TJSONObject;
begin
  Server := TLocalHttpStub.Create('{"jsonrpc":"2.0","id":$id,"result":null}', 2000);
  Registry := TDocumentRegistry.Create(Server.Port, TExactUInt256.FromDecimal('31337'), TBytes.Create(0));
  try
    Clock := TStopwatch.StartNew;
    Receipt := Registry.AwaitReceipt('0x' + StringOfChar('1', 64), 300, 100);
    Elapsed := Clock.ElapsedMilliseconds;
    try Assert.IsNull(Receipt); finally Receipt.Free; end;
    Assert.IsTrue(Elapsed >= 250, IntToStr(Elapsed));
    Assert.IsTrue(Elapsed < 1500, 'Total deadline includes in-flight HTTP: ' + IntToStr(Elapsed));
    Assert.AreEqual(2, Server.Requests, 'Chain query plus one receipt query, no retries');
    Evidence := TJSONObject.Create;
    try
      Evidence.AddPair('simulated', TJSONBool.Create(True));
      Evidence.AddPair('deadlineMs', TJSONNumber.Create(300));
      Evidence.AddPair('serverDelayMs', TJSONNumber.Create(2000));
      Evidence.AddPair('observedMs', TJSONNumber.Create(Elapsed));
      Evidence.AddPair('requests', TJSONNumber.Create(Server.Requests));
      TFile.WriteAllText('build\Anvil\p07-slow-http.json', Evidence.ToJSON, TEncoding.UTF8);
    finally Evidence.Free; end;
  finally Registry.Free; Server.Free; end;
end;

procedure TRpcFailureTests.InvalidReceiptNeverSucceeds(const ACase: string);
var Body: string; Server: TLocalHttpStub; Registry: TDocumentRegistry;
begin
  Body := '"bad"';
  if ACase = 'status' then Body := '{"transactionHash":"0x' + StringOfChar('1', 64) + '","status":"0x2"}';
  if ACase = 'hash' then Body := '{"transactionHash":"0x' + StringOfChar('2', 64) + '","status":"0x1"}';
  if ACase = 'fields' then Body := '{"transactionHash":"0x' + StringOfChar('1', 64) + '","status":"0x1"}';
  Server := TLocalHttpStub.Create('{"jsonrpc":"2.0","id":$id,"result":' + Body + '}');
  Registry := TDocumentRegistry.Create(Server.Port, TExactUInt256.FromDecimal('31337'), TBytes.Create(0));
  try
    Assert.WillRaise(procedure var Receipt: TJSONObject; begin
      Receipt := Registry.AwaitReceipt('0x' + StringOfChar('1', 64), 2000, 100);
      Receipt.Free;
    end, ELocalRpcError);
    Assert.AreEqual(2, Server.Requests);
  finally Registry.Free; Server.Free; end;
end;

function TRealRecoveryTests.RpcString(const AMethod: string; AParameters: TJSONArray): string;
var Value: TJSONValue;
begin
  Value := FRpc.Call(AMethod, AParameters);
  try
    Assert.IsTrue(Value is TJSONString);
    Result := Value.Value;
  finally Value.Free; end;
end;

procedure TRealRecoveryTests.Setup;
begin
  FPort := StrToInt(GetEnvironmentVariable('P04_ANVIL_PORT'));
  FRpc := TLocalRpc.Create(FPort);
  FSnapshot := RpcString('evm_snapshot', TJSONArray.Create);
  FArtifact := TJSONObject.ParseJSONValue(TFile.ReadAllText('build\contract\DocumentRegistry.json', TEncoding.UTF8)) as TJSONObject;
  Assert.IsNotNull(FArtifact);
end;

procedure TRealRecoveryTests.TearDown;
var Value: TJSONValue;
begin
  try
    Value := FRpc.Call('evm_revert', TJSONArray.Create.Add(FSnapshot));
    try Assert.IsTrue(Value is TJSONTrue); finally Value.Free; end;
  finally FArtifact.Free; FRpc.Free; end;
end;

procedure TRealRecoveryTests.PendingExpiresAndResumesWithoutResend;
var Observed: TObservedRpc; Registry: TDocumentRegistry; Submission: TLocalSubmission;
  Receipt: TJSONObject; Checkpoint: TTransactionCheckpoint; Path, Nonce: string;
  Clock: TStopwatch; Elapsed: Int64; Evidence: TJSONObject;
begin
  Observed := TObservedRpc.Create(FPort);
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')), Observed);
  Path := JournalPath;
  Observed.JournalAtSendPath := Path;
  Registry.JournalPath := Path;
  try
    Submission := Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey);
    Checkpoint := TTransactionCheckpoint.Load(Path);
    Assert.AreEqual('submitted', Checkpoint.State);
    Nonce := RpcString('eth_getTransactionCount', TJSONArray.Create(Checkpoint.Account, 'pending'));
    Clock := TStopwatch.StartNew;
    Receipt := Registry.AwaitReceipt(Submission.Hash, 30000, 1000);
    Elapsed := Clock.ElapsedMilliseconds;
    try Assert.IsNull(Receipt); finally Receipt.Free; end;
    Assert.IsTrue((Elapsed >= 29000) and (Elapsed < 32000), IntToStr(Elapsed));
    Checkpoint := TTransactionCheckpoint.Load(Path);
    Assert.AreEqual('pending', Checkpoint.State);
    Assert.AreEqual(Submission.Hash, Checkpoint.Hash);
    Assert.AreEqual(1, Observed.Sends);
    Assert.IsTrue(Observed.PreparedObserved);
    FRpc.Call('evm_mine', TJSONArray.Create).Free;
    Receipt := Registry.AwaitReceipt(Submission.Hash, 2000, 100);
    try Assert.IsNotNull(Receipt); Assert.AreEqual('0x1', Receipt.GetValue<string>('status')); finally Receipt.Free; end;
    Assert.AreEqual(1, Observed.Sends);
    Assert.AreEqual(Nonce, RpcString('eth_getTransactionCount', TJSONArray.Create(Checkpoint.Account, 'pending')));
    Evidence := TJSONObject.Create;
    try
      Evidence.AddPair('simulated', TJSONBool.Create(False));
      Evidence.AddPair('hash', Submission.Hash);
      Evidence.AddPair('deadlineMs', TJSONNumber.Create(30000));
      Evidence.AddPair('pollMs', TJSONNumber.Create(1000));
      Evidence.AddPair('observedMs', TJSONNumber.Create(Elapsed));
      Evidence.AddPair('sendCount', TJSONNumber.Create(Observed.Sends));
      Evidence.AddPair('resumedState', TTransactionCheckpoint.Load(Path).State);
      TFile.WriteAllText('build\Anvil\p07-real-pending.json', Evidence.ToJSON, TEncoding.UTF8);
    finally Evidence.Free; end;
  finally Registry.Free; end;
end;

procedure TRealRecoveryTests.LostResponsePreservesAcceptedHash;
var Observed: TObservedRpc; Registry: TDocumentRegistry; Checkpoint: TTransactionCheckpoint;
  Path: string; Value: TJSONValue; Receipt, Evidence: TJSONObject;
begin
  Observed := TObservedRpc.Create(FPort);
  Observed.DropSendResponse := True;
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')), Observed);
  Path := JournalPath;
  Observed.JournalAtSendPath := Path;
  Registry.JournalPath := Path;
  try
    Assert.WillRaise(procedure begin Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey); end, ELocalRpcError);
    Checkpoint := TTransactionCheckpoint.Load(Path);
    Assert.AreEqual('unknown', Checkpoint.State);
    Assert.IsTrue(Pos('SIMULATED', Checkpoint.Diagnostic) > 0);
    Value := FRpc.Call('eth_getTransactionByHash', TJSONArray.Create.Add(Checkpoint.Hash));
    try Assert.IsTrue(Value is TJSONObject); finally Value.Free; end;
    Assert.IsTrue(Pos(BytesToLowerHex(KnownKey), TFile.ReadAllText(Path, TEncoding.UTF8)) = 0, 'No private key in checkpoint');
    Assert.WillRaise(procedure begin Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey); end, EArgumentException);
    FRpc.Call('evm_mine', TJSONArray.Create).Free;
    Receipt := Registry.AwaitReceipt(Checkpoint.Hash, 2000, 100);
    try Assert.AreEqual('0x1', Receipt.GetValue<string>('status')); finally Receipt.Free; end;
    Assert.AreEqual(1, Observed.Sends);
    Evidence := TJSONObject.Create;
    try
      Evidence.AddPair('simulation', 'Response discarded by Delphi wrapper AFTER real Anvil acceptance');
      Evidence.AddPair('hash', Checkpoint.Hash);
      Evidence.AddPair('stateAfterLoss', Checkpoint.State);
      Evidence.AddPair('resumedState', TTransactionCheckpoint.Load(Path).State);
      Evidence.AddPair('sendCount', TJSONNumber.Create(Observed.Sends));
      Evidence.AddPair('checkpointObservedBeforeHttp', TJSONBool.Create(Observed.PreparedObserved));
      TFile.WriteAllText('build\Anvil\p07-lost-response.json', Evidence.ToJSON, TEncoding.UTF8);
    finally Evidence.Free; end;
  finally Registry.Free; end;
end;

procedure TRealRecoveryTests.JournalFailurePreventsSending;
var Observed: TObservedRpc; Registry: TDocumentRegistry;
begin
  Observed := TObservedRpc.Create(FPort);
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')), Observed);
  try
    Registry.JournalPath := TPath.Combine(GetCurrentDir, 'build'); // Diretorio, nao arquivo substituivel.
    Assert.WillRaise(procedure begin Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey); end, EOSError);
    Assert.AreEqual(0, Observed.Sends);
  finally Registry.Free; end;
end;

procedure TRealRecoveryTests.EmptyFileIsARealDocumentInput;
var Registry: TDocumentRegistry; Submission: TLocalSubmission;
  Receipt: TJSONObject; Address: string; Found: TDocumentRecord;
begin
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')));
  try
    Submission := Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey);
    Receipt := Registry.MineReceipt(Submission.Hash);
    try Address := Receipt.GetValue<string>('contractAddress'); finally Receipt.Free; end;
    Registry.Attach(Address);
    Submission := Registry.RegisterFile('fixtures\p02\empty.bin', KnownKey);
    FRpc.Call('evm_mine', TJSONArray.Create).Free;
    Receipt := Registry.AwaitReceipt(Submission.Hash, 2000, 100);
    try Assert.AreEqual('0x1', Receipt.GetValue<string>('status')); finally Receipt.Free; end;
    Found := Registry.Lookup(AddressFromPublicKey(PublicKeyFromPrivateKey(KnownKey)),
      ParseDocumentHash('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
    Assert.IsTrue(Found.Exists);
  finally Registry.Free; end;
end;

procedure TRealRecoveryTests.NodeRejectionRemainsDifferentFromPending;
var Registry: TDocumentRegistry; Observed: TObservedRpc;
  Path: string; Checkpoint: TTransactionCheckpoint;
begin
  Observed := TObservedRpc.Create(FPort);
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')), Observed);
  Path := JournalPath;
  Registry.JournalPath := Path;
  try
    // Conta derivada do escalar dois: valida, mas sem fundos na genese do roteiro.
    Assert.WillRaise(procedure begin Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')),
      DecodeHex(StringOfChar('0', 63) + '2')); end, EJsonRpcError);
    Checkpoint := TTransactionCheckpoint.Load(Path);
    Assert.AreEqual('rejected', Checkpoint.State);
    Assert.WillRaise(procedure var Receipt: TJSONObject; begin
      Receipt := Registry.AwaitReceipt(Checkpoint.Hash, 100, 50);
      Receipt.Free;
    end, EArgumentException);
    Assert.AreEqual('rejected', TTransactionCheckpoint.Load(Path).State);
    Assert.AreEqual(1, Observed.Sends);
  finally Registry.Free; end;
end;

procedure TRealRecoveryTests.CheckpointTamperingIsRejected(const ACase: string);
var Registry: TDocumentRegistry; Path: string; Document: TJSONObject;
begin
  Registry := TDocumentRegistry.Create(FPort, TExactUInt256.FromDecimal('31337'), DecodeHex(FArtifact.GetValue<string>('runtimeBytecode')));
  Path := JournalPath;
  Registry.JournalPath := Path;
  try
    Registry.Deploy(DecodeHex(FArtifact.GetValue<string>('creationBytecode')), KnownKey);
    Document := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
    try
      if ACase = 'hash' then begin Document.RemovePair('hash').Free; Document.AddPair('hash', '0x' + StringOfChar('0', 64)); end;
      if ACase = 'schema' then begin Document.RemovePair('schema').Free; Document.AddPair('schema', TJSONNumber.Create(2)); end;
      if ACase = 'port' then begin Document.RemovePair('port').Free; Document.AddPair('port', TJSONNumber.Create(0)); end;
      if ACase = 'state' then begin Document.RemovePair('state').Free; Document.AddPair('state', 'invented-success'); end;
      if ACase = 'json' then TFile.WriteAllText(Path, '{', TEncoding.UTF8)
      else TFile.WriteAllText(Path, Document.ToJSON, TEncoding.UTF8);
    finally Document.Free; end;
    Assert.WillRaise(procedure begin TTransactionCheckpoint.Load(Path); end, EArgumentException);
  finally Registry.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRpcFailureTests);
  TDUnitX.RegisterTestFixture(TRealRecoveryTests);
end.
