unit Blockchain.Ethereum.Tests;

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  TEthereumTests = class
  private
    FReference: TJSONObject;
  public
    [Setup] procedure LoadReference;
    [TearDown] procedure ReleaseReference;
    [Test]
    [TestCase('Empty', '0')]
    [TestCase('Abc', '1')]
    [TestCase('ZeroByte', '2')]
    [TestCase('HighBytes', '3')]
    procedure KeccakMatchesReference(const AIndex: Integer);
    [Test] procedure KeccakIsNotSha3;
    [Test]
    [TestCase('EmptyBytes', '0')]
    [TestCase('ZeroByte', '1')]
    [TestCase('SingleByte', '2')]
    [TestCase('HighByte', '3')]
    [TestCase('Dog', '4')]
    [TestCase('EmptyList', '5')]
    [TestCase('CatDog', '6')]
    [TestCase('Nested', '7')]
    [TestCase('Bytes55', '8')]
    [TestCase('Bytes56', '9')]
    [TestCase('List55', '10')]
    [TestCase('List56', '11')]
    procedure RlpMatchesReference(const AIndex: Integer);
    [Test] procedure RlpIntegerZeroIsNotZeroByte;
    [Test]
    [TestCase('OfficialBaz', '0')]
    [TestCase('RecordHash', '1')]
    [TestCase('Lookup', '2')]
    procedure AbiMatchesReference(const AIndex: Integer);
    [Test] procedure AbiStrictPaddingAndSizes;
    [Test] procedure HexAndSelectorRejectMalformedInput;
    [Test] procedure Eip155PublishedDigestSignature;
    [Test]
    [TestCase('Transfer', '0')]
    [TestCase('RecordCall', '1')]
    [TestCase('Creation', '2')]
    procedure Type2MatchesIndependentReference(const AIndex: Integer);
    [Test] procedure SigningIsDeterministicAndTamperingFails;
    [Test] procedure LowSNormalizationUsesLibrarySignature;
    [Test] procedure InvalidKeysDigestsAndSignatures;
    [Test] procedure Type2RejectsInvalidDestinationAndFees;
    [Test] procedure Type2ChainAndFieldsChangeSigningHash;
  end;

implementation

uses
  System.IOUtils,
  Blockchain.Primitives,
  Blockchain.Ethereum,
  ClpBigInteger,
  ClpECUtilities,
  ClpIX9ECAsn1Objects,
  ClpECParameters,
  ClpIECParameters,
  ClpECDsaSigner,
  ClpIECDsaSigner,
  ClpHMacDsaKCalculator,
  ClpDigestUtilities,
  HlpHashFactory;

procedure TEthereumTests.LoadReference;
var
  FileName: string;
begin
  FileName := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\fixtures\p03\reference.json'));
  FReference := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8)) as TJSONObject;
  Assert.IsNotNull(FReference);
end;

procedure TEthereumTests.ReleaseReference;
begin
  FReference.Free;
end;

function Hex(const ABytes: TBytes): string;
begin
  Result := '0x' + BytesToLowerHex(ABytes);
end;

function Entry(const ARoot: TJSONObject; const AName: string; const AIndex: Integer): TJSONObject;
begin
  Result := (ARoot.GetValue(AName) as TJSONArray).Items[AIndex] as TJSONObject;
end;

procedure TEthereumTests.KeccakMatchesReference(const AIndex: Integer);
var
  Vector: TJSONObject;
begin
  Vector := Entry(FReference, 'keccak', AIndex);
  Assert.AreEqual(Vector.GetValue<string>('hash'), Hex(Keccak256(DecodeHex(Vector.GetValue<string>('input')))));
end;

procedure TEthereumTests.KeccakIsNotSha3;
begin
  Assert.AreEqual('c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470', BytesToLowerHex(Keccak256(nil)));
  Assert.AreNotEqual(BytesToLowerHex(Keccak256(nil)), LowerCase(THashFactory.TCrypto.CreateSHA3_256.ComputeBytes(nil).ToString));
end;

function EncodeRlpInput(const AValue: TJSONValue): TBytes;
var
  Items: TArray<TBytes>;
  Index: Integer;
  List: TJSONArray;
begin
  if AValue is TJSONString then Exit(RlpBytes(DecodeHex(AValue.Value)));
  List := AValue as TJSONArray;
  SetLength(Items, List.Count);
  for Index := 0 to List.Count - 1 do Items[Index] := EncodeRlpInput(List.Items[Index]);
  Result := RlpList(Items);
end;

procedure TEthereumTests.RlpMatchesReference(const AIndex: Integer);
var
  Vector: TJSONObject;
begin
  Vector := Entry(FReference, 'rlp', AIndex);
  Assert.AreEqual(Vector.GetValue<string>('encoded'), Hex(EncodeRlpInput(Vector.GetValue('input'))));
end;

procedure TEthereumTests.RlpIntegerZeroIsNotZeroByte;
begin
  Assert.AreEqual('80', BytesToLowerHex(RlpInteger(TExactUInt256.FromDecimal('0'))));
  Assert.AreEqual('00', BytesToLowerHex(RlpBytes(TBytes.Create(0))));
  Assert.AreEqual('c0', BytesToLowerHex(RlpList([])));
  Assert.AreEqual('820400', BytesToLowerHex(RlpInteger(TExactUInt256.FromDecimal('1024'))));
end;

procedure TEthereumTests.AbiMatchesReference(const AIndex: Integer);
var
  Vector: TJSONObject;
  Types, Values: TJSONArray;
  Words: TArray<TBytes>;
  Index: Integer;
  Joined: TBytes;
begin
  Vector := Entry(FReference, 'abi', AIndex);
  Types := Vector.GetValue('types') as TJSONArray;
  Values := Vector.GetValue('values') as TJSONArray;
  SetLength(Words, Types.Count);
  Joined := nil;
  for Index := 0 to Types.Count - 1 do
  begin
    if Types.Items[Index].Value = 'uint256' then
      Words[Index] := TExactUInt256.FromDecimal(Values.Items[Index].Value).ToBigEndianBytes
    else if Types.Items[Index].Value = 'bool' then
    begin
      Words[Index] := AbiBoolean(Values.Items[Index].Value = 'true');
      Assert.IsTrue(DecodeAbiBoolean(Words[Index]));
    end
    else if Types.Items[Index].Value = 'address' then
    begin
      Words[Index] := AbiAddress(DecodeHex(Values.Items[Index].Value));
      Assert.AreEqual(LowerCase(Values.Items[Index].Value), Hex(DecodeAbiAddress(Words[Index])));
    end
    else
      Words[Index] := AbiBytes32(DecodeHex(Values.Items[Index].Value));
    Joined := Joined + Words[Index];
  end;
  Assert.AreEqual(Vector.GetValue<string>('selector'), Hex(AbiSelector(Vector.GetValue<string>('signature'))));
  Assert.AreEqual(Vector.GetValue<string>('words'), Hex(Joined));
  Assert.AreEqual(Vector.GetValue<string>('call'), Hex(AbiCall(Vector.GetValue<string>('signature'), Words)));
end;

procedure TEthereumTests.AbiStrictPaddingAndSizes;
var
  Word: TBytes;
begin
  Assert.IsFalse(DecodeAbiBoolean(AbiBoolean(False)));
  Word := AbiBoolean(True);
  Word[31] := 2;
  Assert.WillRaise(procedure begin DecodeAbiBoolean(Word); end, EArgumentException);
  Word := AbiBoolean(False);
  Word[0] := 1;
  Assert.WillRaise(procedure begin DecodeAbiBoolean(Word); end, EArgumentException);
  Assert.WillRaise(procedure begin DecodeAbiAddress(Word); end, EArgumentException);
  Assert.WillRaise(procedure begin AbiAddress(nil); end, EArgumentException);
  Assert.WillRaise(procedure begin AbiBytes32(nil); end, EArgumentException);
  Assert.WillRaise(procedure begin DecodeAbiBoolean(nil); end, EArgumentException);
  Assert.WillRaise(procedure begin DecodeAbiAddress(nil); end, EArgumentException);
  Assert.WillRaise(procedure begin AbiCall('record(bytes32)', [nil]); end, EArgumentException);
end;

procedure TEthereumTests.HexAndSelectorRejectMalformedInput;
begin
  Assert.WillRaise(procedure begin DecodeHex('0x1'); end, EArgumentException);
  Assert.WillRaise(procedure begin DecodeHex('zz'); end, EArgumentException);
  Assert.WillRaise(procedure begin AbiSelector('record( bytes32)'); end, EArgumentException);
  Assert.WillRaise(procedure begin AbiSelector(''); end, EArgumentException);
end;

function ReadTransaction(const AVector: TJSONObject): TType2Transaction;
var
  Fields: TJSONObject;
begin
  Fields := AVector.GetValue('fields') as TJSONObject;
  Result.ChainId := TExactUInt256.FromDecimal(Fields.GetValue<string>('chainId'));
  Result.Nonce := TExactUInt256.FromDecimal(Fields.GetValue<string>('nonce'));
  Result.MaxPriorityFeePerGas := TExactUInt256.FromDecimal(Fields.GetValue<string>('maxPriorityFeePerGas'));
  Result.MaxFeePerGas := TExactUInt256.FromDecimal(Fields.GetValue<string>('maxFeePerGas'));
  Result.GasLimit := TExactUInt256.FromDecimal(Fields.GetValue<string>('gasLimit'));
  Result.Destination := DecodeHex(Fields.GetValue<string>('to'));
  Result.Amount := TExactUInt256.FromDecimal(Fields.GetValue<string>('value'));
  Result.Data := DecodeHex(Fields.GetValue<string>('data'));
end;

procedure CheckSignatureVector(const AVector: TJSONObject);
var
  Digest, Key, PublicKey: TBytes;
  Signature: TEthereumSignature;
begin
  Digest := DecodeHex(AVector.GetValue<string>('hash'));
  Key := DecodeHex(AVector.GetValue<string>('privateKey'));
  Signature := SignDigest(Digest, Key);
  Assert.AreEqual(AVector.GetValue<string>('r'), Hex(TExactUInt256.FromDecimal(Signature.R.ToString(10)).ToBigEndianBytes));
  Assert.AreEqual(AVector.GetValue<string>('s'), Hex(TExactUInt256.FromDecimal(Signature.S.ToString(10)).ToBigEndianBytes));
  Assert.AreEqual(AVector.GetValue<Integer>('yParity'), Integer(Signature.YParity));
  PublicKey := RecoverPublicKey(Digest, Signature);
  Assert.AreEqual(AVector.GetValue<string>('sender'), Hex(AddressFromPublicKey(PublicKey)));
  Assert.IsTrue(VerifyDigest(Digest, PublicKey, Signature));
end;

procedure TEthereumTests.Eip155PublishedDigestSignature;
begin
  CheckSignatureVector(FReference.GetValue('eip155Digest') as TJSONObject);
end;

procedure TEthereumTests.Type2MatchesIndependentReference(const AIndex: Integer);
var
  Vector: TJSONObject;
  Transaction: TType2Transaction;
  Signature: TEthereumSignature;
  Raw: TBytes;
begin
  Vector := Entry(FReference, 'transactions', AIndex);
  Transaction := ReadTransaction(Vector);
  Assert.AreEqual(Vector.GetValue<string>('unsigned'), Hex(Transaction.UnsignedEnvelope));
  Assert.AreEqual(Vector.GetValue<string>('signingHash'), Hex(Transaction.SigningHash));
  Signature := SignDigest(Transaction.SigningHash, DecodeHex(Vector.GetValue<string>('privateKey')));
  Assert.AreEqual(Vector.GetValue<string>('r'), Hex(TExactUInt256.FromDecimal(Signature.R.ToString(10)).ToBigEndianBytes));
  Assert.AreEqual(Vector.GetValue<string>('s'), Hex(TExactUInt256.FromDecimal(Signature.S.ToString(10)).ToBigEndianBytes));
  Assert.AreEqual(Vector.GetValue<Integer>('yParity'), Integer(Signature.YParity));
  Raw := Transaction.SignedEnvelope(Signature);
  Assert.AreEqual(Vector.GetValue<string>('raw'), Hex(Raw));
  Assert.AreEqual(Vector.GetValue<string>('hash'), Hex(Keccak256(Raw)));
  Assert.AreEqual(Vector.GetValue<string>('sender'), Hex(AddressFromPublicKey(RecoverPublicKey(Transaction.SigningHash, Signature))));
end;

procedure TEthereumTests.SigningIsDeterministicAndTamperingFails;
var
  Vector: TJSONObject;
  Digest, Key, PublicKey, Changed: TBytes;
  Signature, OtherSignature: TEthereumSignature;
begin
  Vector := FReference.GetValue('eip155Digest') as TJSONObject;
  Digest := DecodeHex(Vector.GetValue<string>('hash'));
  Key := DecodeHex(Vector.GetValue<string>('privateKey'));
  PublicKey := PublicKeyFromPrivateKey(Key);
  Signature := SignDigest(Digest, Key);
  OtherSignature := SignDigest(Digest, Key);
  Assert.AreEqual(Signature.R.ToString(16), OtherSignature.R.ToString(16));
  Assert.AreEqual(Signature.S.ToString(16), OtherSignature.S.ToString(16));
  Changed := Copy(Digest);
  Changed[0] := Changed[0] xor 1;
  Assert.IsFalse(VerifyDigest(Changed, PublicKey, Signature));
  Assert.IsFalse(VerifyDigest(Digest,
    PublicKeyFromPrivateKey(DecodeHex(StringOfChar('0', 63) + '1')), Signature));
  Signature.YParity := Signature.YParity xor 1;
  Assert.IsFalse(VerifyDigest(Digest, PublicKey, Signature));
end;

procedure TEthereumTests.LowSNormalizationUsesLibrarySignature;
var
  Parameters: IX9ECParameters;
  CurveDomain: IECDomainParameters;
  LibrarySigner: IECDsaSigner;
  RawSignature: TArray<TBigInteger>;
  Vector: TJSONObject;
  Digest, Key: TBytes;
  Signature: TEthereumSignature;
  HighSCount, Index: Integer;
begin
  Parameters := TECUtilities.FindECCurveByName('secp256k1');
  CurveDomain := TECDomainParameters.Create(Parameters.Curve, Parameters.G, Parameters.N, Parameters.H);
  HighSCount := 0;
  for Index := 0 to 2 do
  begin
    Vector := Entry(FReference, 'transactions', Index);
    Digest := DecodeHex(Vector.GetValue<string>('signingHash'));
    Key := DecodeHex(Vector.GetValue<string>('privateKey'));
    LibrarySigner := TECDsaSigner.Create(THMacDsaKCalculator.Create(TDigestUtilities.GetDigest('SHA-256')));
    LibrarySigner.Init(True, TECPrivateKeyParameters.Create(TBigInteger.Create(1, Key, True), CurveDomain));
    RawSignature := LibrarySigner.GenerateSignature(Digest);
    Signature := SignDigest(Digest, Key);
    Assert.AreEqual(RawSignature[0].ToString(16), Signature.R.ToString(16));
    if RawSignature[1].CompareTo(Parameters.N.ShiftRight(1)) > 0 then
    begin
      Inc(HighSCount);
      Assert.AreEqual(Parameters.N.Subtract(RawSignature[1]).ToString(16), Signature.S.ToString(16));
    end
    else
      Assert.AreEqual(RawSignature[1].ToString(16), Signature.S.ToString(16));
    Assert.IsTrue(VerifyDigest(Digest, PublicKeyFromPrivateKey(Key), Signature));
  end;
  Assert.IsTrue(HighSCount > 0, 'Reference cases must exercise high-s normalization.');
end;

procedure TEthereumTests.InvalidKeysDigestsAndSignatures;
const
  OrderHex = 'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141';
var
  Vector: TJSONObject;
  Digest, Key, ZeroKey: TBytes;
  Signature: TEthereumSignature;
begin
  Vector := FReference.GetValue('eip155Digest') as TJSONObject;
  Digest := DecodeHex(Vector.GetValue<string>('hash'));
  Key := DecodeHex(Vector.GetValue<string>('privateKey'));
  ZeroKey := DecodeHex(StringOfChar('0', 64));
  Assert.WillRaise(procedure begin SignDigest(nil, Key); end, EArgumentException);
  Assert.WillRaise(procedure begin SignDigest(TBytes.Create(1), Key); end, EArgumentException);
  Assert.WillRaise(procedure begin SignDigest(Digest, nil); end, EArgumentException);
  Assert.WillRaise(procedure begin SignDigest(Digest, ZeroKey); end, EArgumentException);
  Assert.WillRaise(procedure begin SignDigest(Digest, DecodeHex(OrderHex)); end, EArgumentException);
  Signature := SignDigest(Digest, Key);
  Signature.S := TBigInteger.Create(OrderHex, 16).Subtract(Signature.S);
  Assert.WillRaise(procedure begin Signature.Validate; end, EArgumentException);
  Signature := SignDigest(Digest, Key);
  Signature.YParity := 2;
  Assert.WillRaise(procedure begin RecoverPublicKey(Digest, Signature); end, EArgumentException);
  Signature := SignDigest(Digest, Key);
  Signature.R := TBigInteger.Create('0');
  Assert.WillRaise(procedure begin Signature.Validate; end, EArgumentException);
  Signature := SignDigest(Digest, Key);
  Signature.S := TBigInteger.Create('0');
  Assert.WillRaise(procedure begin Signature.Validate; end, EArgumentException);
  Signature := SignDigest(Digest, Key);
  Signature.R := TBigInteger.Create(OrderHex, 16);
  Assert.WillRaise(procedure begin Signature.Validate; end, EArgumentException);
end;

procedure TEthereumTests.Type2RejectsInvalidDestinationAndFees;
var
  Transaction: TType2Transaction;
begin
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Transaction.Destination := TBytes.Create(1);
  Assert.WillRaise(procedure begin Transaction.UnsignedEnvelope; end, EArgumentException);
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('3000000000');
  Assert.WillRaise(procedure begin Transaction.UnsignedEnvelope; end, EArgumentException);
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Transaction.ChainId := TExactUInt256.FromDecimal('0');
  Assert.WillRaise(procedure begin Transaction.UnsignedEnvelope; end, EArgumentException);
end;

procedure TEthereumTests.Type2ChainAndFieldsChangeSigningHash;
var
  Transaction: TType2Transaction;
  Original: string;
begin
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Original := Hex(Transaction.SigningHash);
  Transaction.ChainId := TExactUInt256.FromDecimal('31337');
  Assert.AreNotEqual(Original, Hex(Transaction.SigningHash));
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Transaction.Nonce := TExactUInt256.FromDecimal('1');
  Assert.AreNotEqual(Original, Hex(Transaction.SigningHash));
  Transaction := ReadTransaction(Entry(FReference, 'transactions', 0));
  Transaction.Data := TBytes.Create(0);
  Assert.AreNotEqual(Original, Hex(Transaction.SigningHash));
end;

initialization
  TDUnitX.RegisterTestFixture(TEthereumTests);

end.
