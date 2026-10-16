unit Blockchain.DocumentRegistry.Tests;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TDocumentRegistryTests = class
  public
    [Test] procedure DeployRegisterQueryAndReject;
  end;

implementation

uses System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  Blockchain.Primitives, Blockchain.Ethereum, Blockchain.LocalRpc,
  Blockchain.DocumentRegistry;

procedure TDocumentRegistryTests.DeployRegisterQueryAndReject;
var
  Rpc: TLocalRpc;
  Registry, WrongNetwork, WrongRuntime: TDocumentRegistry;
  Artifact, Evidence: TJSONObject;
  Snapshot, NonceBefore, SenderA, SenderB, ContractAddress, RegisteredBlock: string;
  PrivateA, PrivateB, AccountA, AccountB, HashA, HashB, Creation, Runtime: TBytes;
  Submission: TLocalSubmission;
  Receipt, Log: TJSONObject;
  Value: TJSONValue;
  Topics, Logs, Parameters: TJSONArray;
  Found: TDocumentRecord;
  Port: Word;
  function RpcString(const AMethod: string; AParameters: TJSONArray): string;
  var Response: TJSONValue;
  begin
    Response := Rpc.Call(AMethod, AParameters);
    try
      Assert.IsTrue(Response is TJSONString, AMethod);
      Result := Response.Value;
    finally Response.Free; end;
  end;
  function Finish(const AName: string; const ASubmission: TLocalSubmission;
    const AStatus: string): TJSONObject;
  var Entry: TJSONObject; Pending: TJSONValue;
  begin
    Pending := Rpc.Call('eth_getTransactionReceipt', TJSONArray.Create.Add(ASubmission.Hash));
    try Assert.IsTrue(Pending is TJSONNull, 'Receipt must be pending'); finally Pending.Free; end;
    Result := Registry.MineReceipt(ASubmission.Hash);
    try
      Assert.AreEqual(ASubmission.Hash, Result.GetValue<string>('transactionHash'));
      Assert.AreEqual(AStatus, Result.GetValue<string>('status'));
      Entry := TJSONObject.Create;
      Entry.AddPair('hash', ASubmission.Hash);
      Entry.AddPair('rawTransaction', ASubmission.RawHex);
      Entry.AddPair('receipt', Result.Clone as TJSONValue);
      Evidence.AddPair(AName, Entry);
    except Result.Free; raise; end;
  end;
  procedure AssertRejected(const AAction: TProc; const AMessage: string);
  var Rejected: Boolean;
  begin
    Rejected := False;
    try AAction(); except
      on Error: EArgumentException do
      begin
        Rejected := True;
        Assert.IsTrue(Pos(AMessage, Error.Message) > 0, Error.Message);
      end;
    end;
    Assert.IsTrue(Rejected, 'Expected local validation error');
  end;
begin
  Port := StrToInt(GetEnvironmentVariable('P04_ANVIL_PORT'));
  Rpc := TLocalRpc.Create(Port);
  Registry := nil;
  WrongNetwork := nil;
  WrongRuntime := nil;
  Artifact := nil;
  Evidence := TJSONObject.Create;
  Snapshot := RpcString('evm_snapshot', TJSONArray.Create);
  try
    Artifact := TJSONObject.ParseJSONValue(TFile.ReadAllText('build\contract\DocumentRegistry.json', TEncoding.UTF8)) as TJSONObject;
    Assert.IsNotNull(Artifact);
    Creation := DecodeHex(Artifact.GetValue<string>('creationBytecode'));
    Runtime := DecodeHex(Artifact.GetValue<string>('runtimeBytecode'));
    Evidence.AddPair('artifactManifest', Artifact.GetValue('manifest').Clone as TJSONValue);
    PrivateA := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
    PrivateB := DecodeHex(StringOfChar('0', 63) + '1'); // Outra chave publicamente conhecida de teste.
    AccountA := AddressFromPublicKey(PublicKeyFromPrivateKey(PrivateA));
    AccountB := AddressFromPublicKey(PublicKeyFromPrivateKey(PrivateB));
    SenderA := '0x' + BytesToLowerHex(AccountA);
    SenderB := '0x' + BytesToLowerHex(AccountB);
    Assert.AreEqual('0x7e5f4552091a69125d5dfcb7b8c2659029395bdf', SenderB);
    Registry := TDocumentRegistry.Create(Port, TExactUInt256.FromDecimal('31337'), Runtime);
    Submission := Registry.Deploy(Creation, PrivateA);
    Receipt := Finish('deployment', Submission, '0x1');
    try
      Assert.AreEqual(SenderA, Receipt.GetValue<string>('from'));
      Assert.IsTrue(Receipt.GetValue('to') is TJSONNull);
      ContractAddress := Receipt.GetValue<string>('contractAddress');
      Assert.AreEqual(20, Length(DecodeHex(ContractAddress)));
    finally Receipt.Free; end;
    Assert.AreEqual('0x' + BytesToLowerHex(Runtime), RpcString('eth_getCode', TJSONArray.Create(ContractAddress, 'latest')));
    Registry.Attach(ContractAddress);
    Evidence.AddPair('contractAddress', ContractAddress);
    Evidence.AddPair('runtimeBytecode', '0x' + BytesToLowerHex(Runtime));
    HashA := ParseDocumentHash(Sha256File('fixtures\p02\document-a.txt'));
    HashB := ParseDocumentHash(Sha256File('fixtures\p02\document-b.txt'));
    Assert.AreEqual(BytesToLowerHex(HashA), Sha256File('fixtures\p02\document-a-copy.txt'));
    Assert.AreNotEqual(BytesToLowerHex(HashA), BytesToLowerHex(HashB));
    Found := Registry.Lookup(AccountA, HashA);
    Assert.IsFalse(Found.Exists);
    Assert.AreEqual('0', Found.BlockNumber.ToDecimal);
    Submission := Registry.RegisterFile('fixtures\p02\document-a.txt', PrivateA);
    Receipt := Finish('registrationA', Submission, '0x1');
    try
      Assert.AreEqual(SenderA, Receipt.GetValue<string>('from'));
      RegisteredBlock := TExactUInt256.FromRpcQuantity(Receipt.GetValue<string>('blockNumber')).ToDecimal;
      Logs := Receipt.GetValue<TJSONArray>('logs');
      Assert.AreEqual(1, Logs.Count);
      Log := Logs.Items[0] as TJSONObject;
      Assert.AreEqual(ContractAddress, Log.GetValue<string>('address'));
      Topics := Log.GetValue<TJSONArray>('topics');
      Assert.AreEqual(3, Topics.Count);
      Assert.AreEqual('0x' + BytesToLowerHex(Keccak256(TEncoding.ASCII.GetBytes('DocumentRegistered(address,bytes32,uint256)'))), Topics.Items[0].Value);
      Assert.AreEqual('0x' + BytesToLowerHex(AbiAddress(AccountA)), Topics.Items[1].Value);
      Assert.AreEqual('0x' + BytesToLowerHex(HashA), Topics.Items[2].Value);
      Assert.AreEqual(RegisteredBlock, TExactUInt256.FromBigEndianBytes(DecodeHex(Log.GetValue<string>('data'))).ToDecimal);
    finally Receipt.Free; end;
    Found := Registry.Lookup(AccountA, HashA);
    Assert.IsTrue(Found.Exists);
    Assert.AreEqual(RegisteredBlock, Found.BlockNumber.ToDecimal);
    Found := Registry.Lookup(AccountA, HashB);
    Assert.IsFalse(Found.Exists);
    // Simulacao de duplicidade: exigir erro customizado com conta e hash exatos.
    Value := nil;
    try
      Receipt := TJSONObject.Create;
      Receipt.AddPair('to', ContractAddress);
      Receipt.AddPair('from', SenderA);
      Receipt.AddPair('data', '0x' + BytesToLowerHex(AbiCall('register(bytes32)', [HashA])));
      try
        Parameters := TJSONArray.Create;
        Parameters.AddElement(Receipt);
        Parameters.Add('latest');
        Value := Rpc.Call('eth_call', Parameters);
        Assert.Fail('Duplicate simulation must revert');
      except
        on Error: EJsonRpcError do
        begin
          Assert.IsTrue(Pos('0x' + BytesToLowerHex(AbiCall('AlreadyRegistered(address,bytes32)', [AbiAddress(AccountA), HashA])), LowerCase(Error.Message)) > 0, Error.Message);
          Evidence.AddPair('duplicateSimulationError', Error.Message);
        end;
      end;
    finally Value.Free; end;
    // Nova transacao assinada com novo nonce: testar a regra no contrato, sem bloqueio do cliente.
    Submission := Registry.RegisterHash(HashA, PrivateA);
    Receipt := Finish('duplicateReverted', Submission, '0x0');
    try Assert.AreEqual(0, Receipt.GetValue<TJSONArray>('logs').Count); finally Receipt.Free; end;
    Found := Registry.Lookup(AccountA, HashA);
    Assert.AreEqual(RegisteredBlock, Found.BlockNumber.ToDecimal);
    Found := Registry.Lookup(AccountB, HashA);
    Assert.IsFalse(Found.Exists);
    Submission := Registry.RegisterHash(HashA, PrivateB);
    Receipt := Finish('registrationB', Submission, '0x1');
    try
      Assert.AreEqual(SenderB, Receipt.GetValue<string>('from'));
      Found := Registry.Lookup(AccountB, HashA);
      Assert.IsTrue(Found.Exists);
      Assert.AreEqual(TExactUInt256.FromRpcQuantity(Receipt.GetValue<string>('blockNumber')).ToDecimal, Found.BlockNumber.ToDecimal);
    finally Receipt.Free; end;
    // Somente o seletor: argumento bytes32 ausente, rejeitado pelo decodificador do contrato.
    Submission := Registry.SubmitCall(AbiSelector('register(bytes32)'), PrivateA);
    Receipt := Finish('malformedCallReverted', Submission, '0x0');
    try Assert.AreEqual(0, Receipt.GetValue<TJSONArray>('logs').Count); finally Receipt.Free; end;
    Found := Registry.Lookup(AccountA, HashA);
    Assert.AreEqual(RegisteredBlock, Found.BlockNumber.ToDecimal);
    Found := Registry.Lookup(AccountA, HashB);
    Assert.IsFalse(Found.Exists);
    NonceBefore := RpcString('eth_getTransactionCount', TJSONArray.Create(SenderA, 'pending'));
    WrongNetwork := TDocumentRegistry.Create(Port, TExactUInt256.FromDecimal('1'), Runtime);
    // Chave invalida demonstra que a rede e conferida antes de tentar assinar.
    AssertRejected(procedure begin WrongNetwork.Deploy(Creation, nil); end, 'chain id');
    AssertRejected(procedure begin Registry.Attach(SenderA); end, 'runtime');
    WrongRuntime := TDocumentRegistry.Create(Port, TExactUInt256.FromDecimal('31337'), TBytes.Create(0));
    AssertRejected(procedure begin WrongRuntime.Attach(ContractAddress); end, 'runtime');
    AssertRejected(procedure begin Registry.RegisterHash(TBytes.Create(1), PrivateA); end, '32');
    Assert.WillRaise(procedure begin Registry.RegisterFile('fixtures\p02\does-not-exist-p04.txt', PrivateA); end, EFOpenError);
    Assert.AreEqual(NonceBefore, RpcString('eth_getTransactionCount', TJSONArray.Create(SenderA, 'pending')));
    Evidence.AddPair('documentHash', BytesToLowerHex(HashA));
    Evidence.AddPair('registeredBlockA', RegisteredBlock);
    Evidence.AddPair('localGuardsPreservedNonce', TJSONBool.Create(True));
    Evidence.AddPair('passed', TJSONBool.Create(True));
    TFile.WriteAllText('build\Anvil\contract-acceptance.json', Evidence.ToJSON, TEncoding.UTF8);
  finally
    Value := Rpc.Call('evm_revert', TJSONArray.Create.Add(Snapshot));
    try Assert.IsTrue(Value is TJSONTrue, 'Restore snapshot'); finally Value.Free; end;
    WrongRuntime.Free;
    WrongNetwork.Free;
    Registry.Free;
    Artifact.Free;
    Evidence.Free;
    Rpc.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentRegistryTests);
end.
