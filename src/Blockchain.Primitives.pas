unit Blockchain.Primitives;

interface

uses
  System.SysUtils,
  ClpBigInteger;

function BytesToLowerHex(const ABytes: TBytes): string;
function ParseDocumentHash(const AHex: string): TBytes;
function Sha256Bytes(const ABytes: TBytes): string;
function Sha256File(const AFileName: string): string;

type
  TExactUInt256 = record
  private
    FValue: TBigInteger;
    class function FromInteger(const AValue: TBigInteger): TExactUInt256; static;
  public
    class function FromDecimal(const AText: string): TExactUInt256; static;
    class function FromRpcQuantity(const AText: string): TExactUInt256; static;
    class function FromBigEndianBytes(const ABytes: TBytes): TExactUInt256; static;
    function ToDecimal: string;
    function ToRpcQuantity: string;
    function ToBigEndianBytes: TBytes;
  end;

implementation

uses
  System.Hash;

function HexNibble(const ACharacter: Char): Byte;
begin
  case ACharacter of
    '0'..'9': Result := Ord(ACharacter) - Ord('0');
    'a'..'f': Result := Ord(ACharacter) - Ord('a') + 10;
    'A'..'F': Result := Ord(ACharacter) - Ord('A') + 10;
  else
    raise EArgumentException.Create('Caractere hexadecimal invalido.');
  end;
end;

function BytesToLowerHex(const ABytes: TBytes): string;
const
  Digits = '0123456789abcdef';
var
  Index: Integer;
begin
  SetLength(Result, Length(ABytes) * 2);
  for Index := 0 to High(ABytes) do
  begin
    Result[Index * 2 + 1] := Digits[(ABytes[Index] shr 4) + 1];
    Result[Index * 2 + 2] := Digits[(ABytes[Index] and $0F) + 1];
  end;
end;

function ParseDocumentHash(const AHex: string): TBytes;
var
  Index: Integer;
begin
  if Length(AHex) <> 64 then
    raise EArgumentException.Create('Hash SHA-256 exige 64 digitos hexadecimais sem prefixo.');
  SetLength(Result, 32);
  for Index := 0 to 31 do
    Result[Index] := (HexNibble(AHex[Index * 2 + 1]) shl 4) or HexNibble(AHex[Index * 2 + 2]);
end;

function Sha256Bytes(const ABytes: TBytes): string;
var
  Hasher: THashSHA2;
begin
  Hasher := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(ABytes) > 0 then
    Hasher.Update(ABytes, Length(ABytes));
  Result := BytesToLowerHex(Hasher.HashAsBytes);
end;

function Sha256File(const AFileName: string): string;
begin
  // A API de arquivo le os bytes, sem decodificar ou normalizar texto.
  Result := BytesToLowerHex(THashSHA2.GetHashBytesFromFile(AFileName, THashSHA2.TSHA2Version.SHA256));
end;

class function TExactUInt256.FromInteger(const AValue: TBigInteger): TExactUInt256;
begin
  if (AValue.SignValue < 0) or (AValue.BitLength > 256) then
    raise ERangeError.Create('Valor fora do intervalo uint256.');
  Result.FValue := AValue;
end;

class function TExactUInt256.FromDecimal(const AText: string): TExactUInt256;
var
  Index: Integer;
begin
  if AText = '' then
    raise EArgumentException.Create('Inteiro decimal vazio.');
  for Index := 1 to Length(AText) do
    if not CharInSet(AText[Index], ['0'..'9']) then
      raise EArgumentException.Create('Use apenas digitos decimais sem sinal ou separadores.');
  if (Length(AText) > 1) and (AText[1] = '0') then
    raise EArgumentException.Create('Representacao decimal nao canonica.');
  if Length(AText) > 78 then
    raise ERangeError.Create('Valor fora do intervalo uint256.');
  Result := FromInteger(TBigInteger.Create(AText, 10));
end;

class function TExactUInt256.FromRpcQuantity(const AText: string): TExactUInt256;
var
  Index: Integer;
begin
  if (Length(AText) < 3) or (Copy(AText, 1, 2) <> '0x') then
    raise EArgumentException.Create('Quantidade exige prefixo 0x e pelo menos um digito.');
  if (Length(AText) > 3) and (AText[3] = '0') then
    raise EArgumentException.Create('Quantidade nao admite zeros a esquerda.');
  for Index := 3 to Length(AText) do
    HexNibble(AText[Index]);
  if Length(AText) > 66 then
    raise ERangeError.Create('Valor fora do intervalo uint256.');
  Result := FromInteger(TBigInteger.Create(Copy(AText, 3, MaxInt), 16));
end;

class function TExactUInt256.FromBigEndianBytes(const ABytes: TBytes): TExactUInt256;
begin
  if Length(ABytes) <> 32 then
    raise EArgumentException.Create('Representacao fixa uint256 exige exatamente 32 bytes.');
  // Sinal positivo explicito: o bit alto de FF nao representa numero negativo.
  Result := FromInteger(TBigInteger.Create(1, ABytes, True));
end;

function TExactUInt256.ToDecimal: string;
begin
  Result := FValue.ToString(10);
end;

function TExactUInt256.ToRpcQuantity: string;
begin
  Result := '0x' + LowerCase(FValue.ToString(16));
end;

function TExactUInt256.ToBigEndianBytes: TBytes;
var
  Magnitude: TBytes;
begin
  Magnitude := FValue.ToByteArrayUnsigned;
  if Length(Magnitude) > 32 then
    raise ERangeError.Create('Magnitude excede 32 bytes.');
  Result := nil;
  SetLength(Result, 32);
  if Length(Magnitude) > 0 then
    Move(Magnitude[0], Result[32 - Length(Magnitude)], Length(Magnitude));
end;

end.
