unit Blockchain.Primitives.Tests;

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  TPrimitivesTests = class
  private
    function FixturePath(const AName: string): string;
  public
    [Test]
    [TestCase('DocumentA', 'document-a.txt')]
    [TestCase('DocumentCopy', 'document-a-copy.txt')]
    [TestCase('DocumentChanged', 'document-b.txt')]
    [TestCase('Empty', 'empty.bin')]
    [TestCase('Utf8', 'utf8.txt')]
    [TestCase('Binary', 'binary.bin')]
    [TestCase('Abc', 'abc.txt')]
    [TestCase('Padding55', 'bytes-55.bin')]
    [TestCase('Padding56', 'bytes-56.bin')]
    [TestCase('Padding63', 'bytes-63.bin')]
    [TestCase('Padding64', 'bytes-64.bin')]
    [TestCase('Padding65', 'bytes-65.bin')]
    [TestCase('MultipleBlocks', 'bytes-4097.bin')]
    procedure HashMatchesIndependentReference(const AName: string);
    [Test] procedure CopiedContentAndChangedByte;
    [Test] procedure Utf8UsesExplicitBytes;
    [Test] procedure NoUnicodeOrLineEndingNormalization;
    [Test] procedure FileDoesNotExist;
    [Test] procedure HashHexRetainsLeadingZerosAndHighBit;
    [Test]
    [TestCase('Short', 'short')]
    [TestCase('Long', 'long')]
    [TestCase('BadCharacter', 'character')]
    [TestCase('Prefix', 'prefix')]
    procedure InvalidDocumentHash(const AKind: string);
    [Test]
    [TestCase('Zero', '0,0')]
    [TestCase('One', '1,1')]
    [TestCase('HighByte', '255,ff')]
    [TestCase('ByteOrder', '256,100')]
    [TestCase('AboveDouble', '9007199254740993,20000000000001')]
    [TestCase('AboveUInt64', '18446744073709551616,10000000000000000')]
    [TestCase('Maximum', '115792089237316195423570985008687907853269984665640564039457584007913129639935,ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')]
    procedure IntegerRepresentationsMatchKnownValues(const ADecimal, AHex: string);
    [Test]
    [TestCase('Empty', '')]
    [TestCase('Negative', '-1')]
    [TestCase('Sign', '+1')]
    [TestCase('Fraction', '1.5')]
    [TestCase('Exponent', '1e3')]
    [TestCase('LeadingZero', '01')]
    [TestCase('Whitespace', ' 1')]
    procedure InvalidDecimal(const AText: string);
    [Test]
    [TestCase('NoDigits', '0x')]
    [TestCase('NoPrefix', 'ff')]
    [TestCase('LeadingZero', '0x01')]
    [TestCase('BadHex', '0xg')]
    [TestCase('ZeroPadded', '0x00')]
    procedure InvalidQuantity(const AText: string);
    [Test] procedure OverflowIsRejected;
    [Test] procedure FixedBytesRequireExactLength;
    [Test] procedure JsonPreservesQuantityAsString;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  Blockchain.Primitives,
  HlpHashFactory;

function TPrimitivesTests.FixturePath(const AName: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\fixtures\p02\' + AName));
end;

procedure TPrimitivesTests.HashMatchesIndependentReference(const AName: string);
var
  Manifest: TJSONObject;
  Entry: TJSONObject;
  Bytes: TBytes;
  Expected: string;
begin
  Manifest := TJSONObject.ParseJSONValue(TFile.ReadAllText(FixturePath('sha256-reference.json'), TEncoding.UTF8)) as TJSONObject;
  try
    Entry := Manifest.GetValue(AName) as TJSONObject;
    Assert.IsNotNull(Entry, AName);
    Expected := Entry.GetValue<string>('sha256');
    Bytes := TFile.ReadAllBytes(FixturePath(AName));
    Assert.AreEqual(Entry.GetValue<Integer>('bytes'), Length(Bytes));
    Assert.AreEqual(Entry.GetValue<string>('hex'), BytesToLowerHex(Bytes));
    Assert.AreEqual(Expected, Sha256File(FixturePath(AName)));
    Assert.AreEqual(Expected, Sha256Bytes(Bytes));
    Assert.AreEqual(Expected, LowerCase(THashFactory.TCrypto.CreateSHA2_256.ComputeBytes(Bytes).ToString));
  finally
    Manifest.Free;
  end;
end;

procedure TPrimitivesTests.CopiedContentAndChangedByte;
begin
  Assert.AreEqual(Sha256File(FixturePath('document-a.txt')), Sha256File(FixturePath('document-a-copy.txt')));
  Assert.AreNotEqual(Sha256File(FixturePath('document-a.txt')), Sha256File(FixturePath('document-b.txt')));
end;

procedure TPrimitivesTests.Utf8UsesExplicitBytes;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes('a' + Char($00E7) + Char($00E3) + 'o');
  Assert.AreEqual('61c3a7c3a36f', BytesToLowerHex(Bytes));
  Assert.AreEqual(Sha256Bytes(Bytes), Sha256File(FixturePath('utf8.txt')));
end;

procedure TPrimitivesTests.NoUnicodeOrLineEndingNormalization;
begin
  Assert.AreNotEqual(Sha256Bytes(TEncoding.UTF8.GetBytes(Char($00E9))),
    Sha256Bytes(TEncoding.UTF8.GetBytes('e' + Char($0301))));
  Assert.AreNotEqual(Sha256Bytes(TBytes.Create($61, $0A)), Sha256Bytes(TBytes.Create($61, $0D, $0A)));
  Assert.AreNotEqual(Sha256Bytes(TBytes.Create($61)), Sha256Bytes(TBytes.Create($EF, $BB, $BF, $61)));
end;

procedure TPrimitivesTests.FileDoesNotExist;
var
  MissingPath: string;
begin
  MissingPath := FixturePath(TPath.GetRandomFileName);
  Assert.WillRaise(procedure begin Sha256File(MissingPath); end, EFOpenError);
end;

procedure TPrimitivesTests.HashHexRetainsLeadingZerosAndHighBit;
var
  Bytes: TBytes;
  Expected: string;
begin
  Expected := '00ff' + StringOfChar('0', 60);
  Bytes := ParseDocumentHash(UpperCase(Expected));
  Assert.AreEqual(32, Length(Bytes));
  Assert.AreEqual(Expected, BytesToLowerHex(Bytes));
  Assert.AreEqual('', BytesToLowerHex(nil));
end;

procedure TPrimitivesTests.InvalidDocumentHash(const AKind: string);
var
  Text: string;
begin
  Text := StringOfChar('a', 64);
  if AKind = 'short' then Delete(Text, 1, 1);
  if AKind = 'long' then Text := Text + 'a';
  if AKind = 'character' then Text[1] := 'g';
  if AKind = 'prefix' then Text := '0x' + Text;
  Assert.WillRaise(procedure begin ParseDocumentHash(Text); end, EArgumentException);
end;

procedure TPrimitivesTests.IntegerRepresentationsMatchKnownValues(const ADecimal, AHex: string);
var
  Value: TExactUInt256;
  Bytes: TBytes;
  ExpectedWord: string;
begin
  Value := TExactUInt256.FromDecimal(ADecimal);
  ExpectedWord := StringOfChar('0', 64 - Length(AHex)) + AHex;
  Bytes := Value.ToBigEndianBytes;
  Assert.AreEqual(32, Length(Bytes));
  Assert.AreEqual(ExpectedWord, BytesToLowerHex(Bytes));
  Assert.AreEqual('0x' + AHex, Value.ToRpcQuantity);
  Assert.AreEqual(ADecimal, TExactUInt256.FromRpcQuantity('0x' + UpperCase(AHex)).ToDecimal);
  Assert.AreEqual(ADecimal, TExactUInt256.FromBigEndianBytes(Bytes).ToDecimal);
end;

procedure TPrimitivesTests.InvalidDecimal(const AText: string);
begin
  Assert.WillRaise(procedure begin TExactUInt256.FromDecimal(AText); end, EArgumentException);
end;

procedure TPrimitivesTests.InvalidQuantity(const AText: string);
begin
  Assert.WillRaise(procedure begin TExactUInt256.FromRpcQuantity(AText); end, EArgumentException);
end;

procedure TPrimitivesTests.OverflowIsRejected;
begin
  Assert.WillRaise(procedure begin
    TExactUInt256.FromDecimal('115792089237316195423570985008687907853269984665640564039457584007913129639936');
  end, ERangeError);
  Assert.WillRaise(procedure begin
    TExactUInt256.FromRpcQuantity('0x1' + StringOfChar('0', 64));
  end, ERangeError);
end;

procedure TPrimitivesTests.FixedBytesRequireExactLength;
var
  Bytes: TBytes;
begin
  SetLength(Bytes, 31);
  Assert.WillRaise(procedure begin TExactUInt256.FromBigEndianBytes(Bytes); end, EArgumentException);
  SetLength(Bytes, 33);
  Assert.WillRaise(procedure begin TExactUInt256.FromBigEndianBytes(Bytes); end, EArgumentException);
end;

procedure TPrimitivesTests.JsonPreservesQuantityAsString;
var
  JsonObject: TJSONObject;
  Parsed: TJSONObject;
  Expected: string;
begin
  Expected := '9007199254740993';
  JsonObject := TJSONObject.Create;
  try
    JsonObject.AddPair('quantity', TExactUInt256.FromDecimal(Expected).ToRpcQuantity);
    Parsed := TJSONObject.ParseJSONValue(JsonObject.ToJSON) as TJSONObject;
    try
      Assert.IsTrue(Parsed.GetValue('quantity') is TJSONString);
      Assert.AreEqual(Expected, TExactUInt256.FromRpcQuantity(Parsed.GetValue<string>('quantity')).ToDecimal);
    finally
      Parsed.Free;
    end;
  finally
    JsonObject.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPrimitivesTests);

end.
