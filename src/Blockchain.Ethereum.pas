unit Blockchain.Ethereum;

interface

uses
  System.SysUtils,
  Blockchain.Primitives,
  ClpBigInteger;

function DecodeHex(const AText: string): TBytes;
function Keccak256(const ABytes: TBytes): TBytes;
function AbiSelector(const ASignature: string): TBytes;
function AbiAddress(const AAddress: TBytes): TBytes;
function AbiBoolean(const AValue: Boolean): TBytes;
function DecodeAbiBoolean(const AWord: TBytes): Boolean;
function DecodeAbiAddress(const AWord: TBytes): TBytes;
function AbiBytes32(const AValue: TBytes): TBytes;
function AbiCall(const ASignature: string; const AWords: array of TBytes): TBytes;
function RlpBytes(const ABytes: TBytes): TBytes;
function RlpInteger(const AValue: TExactUInt256): TBytes;
function RlpList(const AEncodedItems: array of TBytes): TBytes;

type
  TEthereumSignature = record
    R: TBigInteger;
    S: TBigInteger;
    YParity: Byte;
    procedure Validate;
  end;

  TType2Transaction = record
    ChainId: TExactUInt256;
    Nonce: TExactUInt256;
    MaxPriorityFeePerGas: TExactUInt256;
    MaxFeePerGas: TExactUInt256;
    GasLimit: TExactUInt256;
    Destination: TBytes;
    Amount: TExactUInt256;
    Data: TBytes;
    // Este laboratorio suporta somente access_list vazia.
    procedure Validate;
    function UnsignedEnvelope: TBytes;
    function SigningHash: TBytes;
    function SignedEnvelope(const ASignature: TEthereumSignature): TBytes;
  end;

function PublicKeyFromPrivateKey(const APrivateKey: TBytes): TBytes;
function AddressFromPublicKey(const APublicKey: TBytes): TBytes;
function SignDigest(const ADigest, APrivateKey: TBytes): TEthereumSignature;
function RecoverPublicKey(const ADigest: TBytes; const ASignature: TEthereumSignature): TBytes;
function VerifyDigest(const ADigest, APublicKey: TBytes; const ASignature: TEthereumSignature): Boolean;

implementation

uses
  HlpHashFactory,
  ClpECUtilities,
  ClpIX9ECAsn1Objects,
  ClpECParameters,
  ClpIECParameters,
  ClpIECCommon,
  ClpECAlgorithms,
  ClpECDsaSigner,
  ClpIECDsaSigner,
  ClpHMacDsaKCalculator,
  ClpDigestUtilities;

function DecodeHex(const AText: string): TBytes;
var
  Text: string;
  Index: Integer;
  function Nibble(const ACharacter: Char): Byte;
  begin
    case ACharacter of
      '0'..'9': Result := Ord(ACharacter) - Ord('0');
      'a'..'f': Result := Ord(ACharacter) - Ord('a') + 10;
      'A'..'F': Result := Ord(ACharacter) - Ord('A') + 10;
    else
      raise EArgumentException.Create('Invalid hexadecimal character.');
    end;
  end;
begin
  Text := AText;
  if Copy(Text, 1, 2) = '0x' then Delete(Text, 1, 2);
  if Odd(Length(Text)) then
    raise EArgumentException.Create('Byte data requires pairs of hexadecimal digits.');
  SetLength(Result, Length(Text) div 2);
  for Index := 0 to High(Result) do
    Result[Index] := (Nibble(Text[Index * 2 + 1]) shl 4) or Nibble(Text[Index * 2 + 2]);
end;

function Keccak256(const ABytes: TBytes): TBytes;
begin
  Result := THashFactory.TCrypto.CreateKeccak_256.ComputeBytes(ABytes).GetBytes;
end;

function AbiSelector(const ASignature: string): TBytes;
var
  Character: Char;
begin
  if (ASignature = '') or (Pos('(', ASignature) <= 1) or
    (ASignature[Length(ASignature)] <> ')') then
    raise EArgumentException.Create('Expected a canonical function signature.');
  for Character in ASignature do
    if (Ord(Character) > 127) or (Ord(Character) <= 32) then
      raise EArgumentException.Create('Signature must use ASCII without whitespace.');
  Result := Copy(Keccak256(TEncoding.ASCII.GetBytes(ASignature)), 0, 4);
end;

function AbiAddress(const AAddress: TBytes): TBytes;
begin
  if Length(AAddress) <> 20 then raise EArgumentException.Create('Address must contain 20 bytes.');
  Result := nil;
  SetLength(Result, 32);
  Move(AAddress[0], Result[12], 20);
end;

function AbiBoolean(const AValue: Boolean): TBytes;
begin
  Result := nil;
  SetLength(Result, 32);
  Result[31] := Ord(AValue);
end;

function DecodeAbiBoolean(const AWord: TBytes): Boolean;
var
  Index: Integer;
begin
  if Length(AWord) <> 32 then raise EArgumentException.Create('ABI word must contain 32 bytes.');
  for Index := 0 to 30 do
    if AWord[Index] <> 0 then raise EArgumentException.Create('Noncanonical ABI boolean.');
  if AWord[31] > 1 then raise EArgumentException.Create('Noncanonical ABI boolean.');
  Result := AWord[31] = 1;
end;

function DecodeAbiAddress(const AWord: TBytes): TBytes;
var
  Index: Integer;
begin
  if Length(AWord) <> 32 then raise EArgumentException.Create('ABI word must contain 32 bytes.');
  for Index := 0 to 11 do
    if AWord[Index] <> 0 then raise EArgumentException.Create('Noncanonical address padding.');
  Result := Copy(AWord, 12, 20);
end;

function AbiBytes32(const AValue: TBytes): TBytes;
begin
  if Length(AValue) <> 32 then raise EArgumentException.Create('bytes32 requires 32 bytes.');
  Result := Copy(AValue);
end;

function AbiCall(const ASignature: string; const AWords: array of TBytes): TBytes;
var
  Word: TBytes;
begin
  Result := AbiSelector(ASignature);
  for Word in AWords do
    Result := Result + AbiBytes32(Word);
end;

function LengthPrefix(const APrefix: Byte; const ALength: Integer): TBytes;
var
  LengthBytes: TBytes;
  Remaining: Integer;
begin
  if ALength <= 55 then Exit(TBytes.Create(APrefix + ALength));
  LengthBytes := nil;
  Remaining := ALength;
  while Remaining > 0 do
  begin
    LengthBytes := TBytes.Create(Byte(Remaining and $FF)) + LengthBytes;
    Remaining := Remaining shr 8;
  end;
  Result := TBytes.Create(APrefix + 55 + Length(LengthBytes)) + LengthBytes;
end;

function RlpBytes(const ABytes: TBytes): TBytes;
begin
  if (Length(ABytes) = 1) and (ABytes[0] < $80) then Exit(Copy(ABytes));
  Result := LengthPrefix($80, Length(ABytes)) + ABytes;
end;

function RlpInteger(const AValue: TExactUInt256): TBytes;
var
  Bytes: TBytes;
  Offset: Integer;
begin
  Bytes := AValue.ToBigEndianBytes;
  Offset := 0;
  while (Offset < Length(Bytes)) and (Bytes[Offset] = 0) do Inc(Offset);
  Result := RlpBytes(Copy(Bytes, Offset, Length(Bytes) - Offset));
end;

function RlpList(const AEncodedItems: array of TBytes): TBytes;
var
  Payload: TBytes;
  Item: TBytes;
begin
  Payload := nil;
  for Item in AEncodedItems do Payload := Payload + Item;
  Result := LengthPrefix($C0, Length(Payload)) + Payload;
end;

function Domain: IECDomainParameters;
var
  Parameters: IX9ECParameters;
begin
  Parameters := TECUtilities.FindECCurveByName('secp256k1');
  Result := TECDomainParameters.Create(Parameters.Curve, Parameters.G,
    Parameters.N, Parameters.H, Parameters.GetSeed);
end;

procedure TEthereumSignature.Validate;
var
  Parameters: IECDomainParameters;
begin
  Parameters := Domain;
  if (YParity > 1) or (R.SignValue <= 0) or (S.SignValue <= 0) or
    (R.CompareTo(Parameters.N) >= 0) or (S.CompareTo(Parameters.N.ShiftRight(1)) > 0) then
    raise EArgumentException.Create('Invalid Ethereum signature or noncanonical high-s.');
end;

function PrivateScalar(const APrivateKey: TBytes): TBigInteger;
begin
  if Length(APrivateKey) <> 32 then raise EArgumentException.Create('Private key must contain 32 bytes.');
  Result := TBigInteger.Create(1, APrivateKey, True);
  if (Result.SignValue <= 0) or (Result.CompareTo(Domain.N) >= 0) then
    raise EArgumentException.Create('Private key outside secp256k1 scalar range.');
end;

function PublicKeyFromPrivateKey(const APrivateKey: TBytes): TBytes;
begin
  Result := Domain.G.Multiply(PrivateScalar(APrivateKey)).Normalize.GetEncoded(False);
end;

function AddressFromPublicKey(const APublicKey: TBytes): TBytes;
var
  Point: IECPoint;
begin
  if (Length(APublicKey) <> 65) or (APublicKey[0] <> 4) then
    raise EArgumentException.Create('Expected uncompressed secp256k1 public key.');
  Point := Domain.Curve.DecodePoint(APublicKey);
  if Point.IsInfinity then raise EArgumentException.Create('Public key is infinity.');
  Result := Copy(Keccak256(Copy(APublicKey, 1, 64)), 12, 20);
end;

function RecoverPublicKey(const ADigest: TBytes; const ASignature: TEthereumSignature): TBytes;
var
  Parameters: IECDomainParameters;
  Point, Recovered: IECPoint;
  InverseR, NegativeDigest: TBigInteger;
  EncodedX: TBytes;
begin
  if Length(ADigest) <> 32 then raise EArgumentException.Create('Digest must contain 32 bytes.');
  ASignature.Validate;
  Parameters := Domain;
  EncodedX := TExactUInt256.FromDecimal(ASignature.R.ToString(10)).ToBigEndianBytes;
  Point := Parameters.Curve.DecodePoint(TBytes.Create(2 + ASignature.YParity) + EncodedX);
  if not Point.Multiply(Parameters.N).IsInfinity then
    raise EArgumentException.Create('Recovery point has invalid order.');
  InverseR := ASignature.R.ModInverse(Parameters.N);
  NegativeDigest := TBigInteger.Create(1, ADigest, True).Negate.&Mod(Parameters.N);
  // Operacoes de curva e inteiros sao fornecidas pela biblioteca, nao reimplementadas.
  Recovered := TECAlgorithms.SumOfTwoMultiplies(Parameters.G,
    NegativeDigest.Multiply(InverseR).&Mod(Parameters.N), Point,
    ASignature.S.Multiply(InverseR).&Mod(Parameters.N));
  if Recovered.IsInfinity then raise EArgumentException.Create('Recovered public key is infinity.');
  Result := Recovered.Normalize.GetEncoded(False);
end;

function VerifyDigest(const ADigest, APublicKey: TBytes; const ASignature: TEthereumSignature): Boolean;
var
  Signer: IECDsaSigner;
  Parameters: IECDomainParameters;
  PublicKey: IECPublicKeyParameters;
begin
  if Length(ADigest) <> 32 then raise EArgumentException.Create('Digest must contain 32 bytes.');
  ASignature.Validate;
  AddressFromPublicKey(APublicKey);
  Parameters := Domain;
  PublicKey := TECPublicKeyParameters.Create('ECDSA', Parameters.Curve.DecodePoint(APublicKey), Parameters);
  Signer := TECDsaSigner.Create;
  Signer.Init(False, PublicKey);
  Result := Signer.VerifySignature(ADigest, ASignature.R, ASignature.S);
  if Result then
    Result := BytesToLowerHex(RecoverPublicKey(ADigest, ASignature)) = BytesToLowerHex(APublicKey);
end;

function SignDigest(const ADigest, APrivateKey: TBytes): TEthereumSignature;
var
  Parameters: IECDomainParameters;
  Signer: IECDsaSigner;
  Components: TArray<TBigInteger>;
  PublicKey: TBytes;
  Parity: Byte;
begin
  if Length(ADigest) <> 32 then raise EArgumentException.Create('Digest must contain 32 bytes.');
  Parameters := Domain;
  Signer := TECDsaSigner.Create(THMacDsaKCalculator.Create(TDigestUtilities.GetDigest('SHA-256')));
  Signer.Init(True, TECPrivateKeyParameters.Create(PrivateScalar(APrivateKey), Parameters));
  // RFC 6979 usa HMAC-SHA256 para o nonce; o digest assinado ja e Keccak-256.
  Components := Signer.GenerateSignature(ADigest);
  Result.R := Components[0];
  Result.S := Components[1];
  if Result.S.CompareTo(Parameters.N.ShiftRight(1)) > 0 then
    Result.S := Parameters.N.Subtract(Result.S);
  PublicKey := PublicKeyFromPrivateKey(APrivateKey);
  for Parity := 0 to 1 do
  begin
    Result.YParity := Parity;
    if BytesToLowerHex(RecoverPublicKey(ADigest, Result)) = BytesToLowerHex(PublicKey) then Exit;
  end;
  // O caso raro x(R)>=n nao cabe no campo de paridade de uma transacao Ethereum.
  raise EArgumentException.Create('Signature recovery cannot be represented by Ethereum yParity.');
end;

procedure TType2Transaction.Validate;
begin
  if ChainId.ToDecimal = '0' then raise EArgumentException.Create('Laboratory requires a positive chain id.');
  if (Length(Destination) <> 0) and (Length(Destination) <> 20) then
    raise EArgumentException.Create('Destination must be empty or contain 20 bytes.');
  if TBigInteger.Create(MaxPriorityFeePerGas.ToDecimal, 10).CompareTo(
    TBigInteger.Create(MaxFeePerGas.ToDecimal, 10)) > 0 then
    raise EArgumentException.Create('Priority fee exceeds maximum fee.');
end;

function TransactionFields(const ATransaction: TType2Transaction): TArray<TBytes>;
begin
  ATransaction.Validate;
  Result := TArray<TBytes>.Create(RlpInteger(ATransaction.ChainId), RlpInteger(ATransaction.Nonce),
    RlpInteger(ATransaction.MaxPriorityFeePerGas), RlpInteger(ATransaction.MaxFeePerGas),
    RlpInteger(ATransaction.GasLimit), RlpBytes(ATransaction.Destination),
    RlpInteger(ATransaction.Amount), RlpBytes(ATransaction.Data), RlpList([]));
end;

function TType2Transaction.UnsignedEnvelope: TBytes;
begin
  Result := TBytes.Create(2) + RlpList(TransactionFields(Self));
end;

function TType2Transaction.SigningHash: TBytes;
begin
  Result := Keccak256(UnsignedEnvelope);
end;

function TType2Transaction.SignedEnvelope(const ASignature: TEthereumSignature): TBytes;
var
  Fields: TArray<TBytes>;
begin
  ASignature.Validate;
  Fields := TransactionFields(Self);
  Fields := Fields + TArray<TBytes>.Create(
    RlpInteger(TExactUInt256.FromDecimal(IntToStr(ASignature.YParity))),
    RlpInteger(TExactUInt256.FromDecimal(ASignature.R.ToString(10))),
    RlpInteger(TExactUInt256.FromDecimal(ASignature.S.ToString(10))));
  Result := TBytes.Create(2) + RlpList(Fields);
end;

end.
