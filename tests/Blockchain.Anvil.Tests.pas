unit Blockchain.Anvil.Tests;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TAnvilTests = class
  public
    [Test] procedure SignedTransactionLifecycle;
  end;

implementation

uses System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  Blockchain.LocalRpc, Blockchain.Ethereum, Blockchain.Primitives, ClpBigInteger;

procedure TAnvilTests.SignedTransactionLifecycle;
var
  Rpc: TLocalRpc;
  Transaction: TType2Transaction;
  PrivateKey, Raw: TBytes;
  Sender, Recipient, Hash, ReturnedHash, Rejection: string;
  Value, Receipt, NodeTransaction: TJSONValue;
  Evidence: TJSONObject;
  InitialBalance, FinalBalance, GasCost: TBigInteger;
  function CallString(const AMethod: string; AParameters: TJSONArray): string;
  var Response: TJSONValue;
  begin
    Response := Rpc.Call(AMethod, AParameters);
    try
      Assert.IsTrue(Response is TJSONString, AMethod + ': expected string');
      Result := Response.Value;
    finally Response.Free; end;
  end;
  function Quantity(const AText: string): TBigInteger;
  begin
    Result := TBigInteger.Create(TExactUInt256.FromRpcQuantity(AText).ToDecimal, 10);
  end;
  procedure Reject(const ATransaction: TType2Transaction; const ALabel, AExpectedMessage: string);
  var Encoded: TBytes; WasRejected: Boolean; Response: TJSONValue;
  begin
    Encoded := ATransaction.SignedEnvelope(SignDigest(ATransaction.SigningHash, PrivateKey));
    WasRejected := False;
    try
      Response := Rpc.Call('eth_sendRawTransaction', TJSONArray.Create.Add('0x' + BytesToLowerHex(Encoded)));
      Response.Free;
    except
      on Error: EJsonRpcError do
      begin
        WasRejected := True;
        Rejection := Error.Message;
      end;
    end;
    Assert.IsTrue(WasRejected, ALabel + ' must be rejected by node');
    Assert.IsTrue(Pos(AExpectedMessage, Rejection) > 0, ALabel + ': unexpected rejection: ' + Rejection);
    Evidence.AddPair(ALabel, Rejection);
  end;
begin
  Rpc := TLocalRpc.Create(StrToInt(GetEnvironmentVariable('P04_ANVIL_PORT')));
  Evidence := TJSONObject.Create;
  try
    Assert.AreEqual('0x7a69', CallString('eth_chainId', TJSONArray.Create));
    Assert.AreEqual('0x0', CallString('eth_blockNumber', TJSONArray.Create));
    Evidence.AddPair('client', CallString('web3_clientVersion', TJSONArray.Create));
    // Chave privada publicamente conhecida do exemplo EIP-155. Nunca usar com fundos reais.
    PrivateKey := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
    Sender := '0x' + BytesToLowerHex(AddressFromPublicKey(PublicKeyFromPrivateKey(PrivateKey)));
    Assert.AreEqual('0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f', Sender);
    Recipient := '0x3535353535353535353535353535353535353535';
    Assert.AreEqual('0x0', CallString('eth_getBalance', TJSONArray.Create(Recipient, 'latest')));
    InitialBalance := Quantity(CallString('eth_getBalance', TJSONArray.Create(Sender, 'latest')));
    Assert.AreEqual('100000000000000000000', InitialBalance.ToString(10));
    Transaction.ChainId := TExactUInt256.FromDecimal('31337');
    Transaction.Nonce := TExactUInt256.FromRpcQuantity(CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'pending')));
    Assert.AreEqual('0', Transaction.Nonce.ToDecimal);
    Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('1000000000');
    Transaction.MaxFeePerGas := TExactUInt256.FromDecimal('3000000000');
    Transaction.GasLimit := TExactUInt256.FromDecimal('21000');
    Transaction.Destination := DecodeHex(Recipient);
    Transaction.Amount := TExactUInt256.FromDecimal('1000000000000000000');
    Transaction.Data := nil;
    Transaction.ChainId := TExactUInt256.FromDecimal('1');
    Reject(Transaction, 'wrongChain', 'invalid chain id');
    Transaction.ChainId := TExactUInt256.FromDecimal('31337');
    Transaction.Amount := TExactUInt256.FromDecimal('100000000000000000001');
    Reject(Transaction, 'insufficientFunds', 'Insufficient funds');
    Transaction.Amount := TExactUInt256.FromDecimal('1000000000000000000');
    Assert.AreEqual('0x0', CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'pending')));
    Raw := Transaction.SignedEnvelope(SignDigest(Transaction.SigningHash, PrivateKey));
    Hash := '0x' + BytesToLowerHex(Keccak256(Raw));
    ReturnedHash := CallString('eth_sendRawTransaction', TJSONArray.Create.Add('0x' + BytesToLowerHex(Raw)));
    Assert.AreEqual(Hash, ReturnedHash);
    Value := Rpc.Call('eth_getTransactionReceipt', TJSONArray.Create.Add(Hash));
    try Assert.IsTrue(Value is TJSONNull, 'Accepted transaction must remain pending'); finally Value.Free; end;
    Assert.AreEqual('0x0', CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'latest')));
    Assert.AreEqual('0x1', CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'pending')));
    Value := Rpc.Call('evm_mine', TJSONArray.Create);
    Value.Free;
    Receipt := Rpc.Call('eth_getTransactionReceipt', TJSONArray.Create.Add(Hash));
    try
      Assert.IsTrue(Receipt is TJSONObject, 'Receipt after mining');
      Assert.AreEqual('0x1', Receipt.GetValue<string>('status'));
      Assert.AreEqual(Hash, Receipt.GetValue<string>('transactionHash'));
      Assert.AreEqual(Sender, Receipt.GetValue<string>('from'));
      Assert.AreEqual(Recipient, Receipt.GetValue<string>('to'));
      Assert.AreEqual('0x1', Receipt.GetValue<string>('blockNumber'));
      Assert.AreEqual('0x5208', Receipt.GetValue<string>('gasUsed'));
      GasCost := Quantity(Receipt.GetValue<string>('gasUsed')).Multiply(Quantity(Receipt.GetValue<string>('effectiveGasPrice')));
      FinalBalance := Quantity(CallString('eth_getBalance', TJSONArray.Create(Sender, 'latest')));
      Assert.AreEqual(InitialBalance.Subtract(TBigInteger.Create(Transaction.Amount.ToDecimal, 10)).Subtract(GasCost).ToString(10), FinalBalance.ToString(10));
      Evidence.AddPair('receipt', Receipt.Clone as TJSONValue);
    finally Receipt.Free; end;
    NodeTransaction := Rpc.Call('eth_getTransactionByHash', TJSONArray.Create.Add(Hash));
    try
      Assert.AreEqual(Sender, NodeTransaction.GetValue<string>('from'));
      Assert.AreEqual('0x2', NodeTransaction.GetValue<string>('type'));
      Assert.AreEqual('0x7a69', NodeTransaction.GetValue<string>('chainId'));
      Assert.AreEqual('0x0', NodeTransaction.GetValue<string>('nonce'));
      Evidence.AddPair('transaction', NodeTransaction.Clone as TJSONValue);
    finally NodeTransaction.Free; end;
    Assert.AreEqual(Transaction.Amount.ToRpcQuantity, CallString('eth_getBalance', TJSONArray.Create(Recipient, 'latest')));
    Assert.AreEqual('0x1', CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'latest')));
    Transaction.Nonce := TExactUInt256.FromDecimal('0');
    Reject(Transaction, 'consumedNonce', 'nonce too low');
    Assert.AreEqual('0x1', CallString('eth_blockNumber', TJSONArray.Create));
    Assert.AreEqual('0x1', CallString('eth_getTransactionCount', TJSONArray.Create(Sender, 'pending')));
    Evidence.AddPair('rawTransaction', '0x' + BytesToLowerHex(Raw));
    Evidence.AddPair('localHash', Hash);
    Evidence.AddPair('senderFinalBalanceWei', FinalBalance.ToString(10));
    Evidence.AddPair('passed', TJSONBool.Create(True));
    TFile.WriteAllText(GetEnvironmentVariable('P04_EVIDENCE'), Evidence.ToJSON, TEncoding.UTF8);
  finally
    Evidence.Free;
    Rpc.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnvilTests);
end.
