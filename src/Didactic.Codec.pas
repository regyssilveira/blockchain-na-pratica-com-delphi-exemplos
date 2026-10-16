unit Didactic.Codec;

interface

uses System.SysUtils, System.JSON;

const
  MaxDidacticBlocks = 128;
  MaxBlockTransactions = 8;
  MaxPendingTransactions = 64;
  MaxSnapshotBytes = 2097152;

type
  EDidacticValidation = class(Exception);
  ENeedDidacticSync = class(EDidacticValidation);
  TDidacticPolicy = record
    Difficulty: Byte;
    class function Create(const ADifficulty: Byte = 2): TDidacticPolicy; static;
    function NetworkId: string;
  end;

function CanonicalUInt(const AText: string): UInt64;
function JsonText(const AObject: TJSONObject; const AName: string): string;
function JsonUInt(const AObject: TJSONObject; const AName: string): UInt64;
procedure RequireFields(const AObject: TJSONObject; const ANames: array of string);
function FixedHex(const AText: string; const ABytes: Integer): TBytes;
function UIntBytes(const AValue: UInt64; const ASize: Integer): TBytes;
function TextBytes(const AText: string): TBytes;
procedure SaveAtomicUtf8(const APath, AText: string);

implementation

uses System.IOUtils, System.Classes, Winapi.Windows,
  Blockchain.Primitives, Blockchain.Ethereum;

class function TDidacticPolicy.Create(const ADifficulty: Byte): TDidacticPolicy;
begin
  if (ADifficulty < 2) or (ADifficulty > 4) then
    raise EDidacticValidation.Create('Difficulty must be 2, 3 or 4 hexadecimal zeros.');
  Result.Difficulty := ADifficulty;
end;

function TDidacticPolicy.NetworkId: string;
begin
  TDidacticPolicy.Create(Difficulty);
  Result := 'delphi-didactic-v1-d' + UIntToStr(Difficulty);
end;

function CanonicalUInt(const AText: string): UInt64;
var Character: Char;
begin
  if (AText = '') or ((Length(AText) > 1) and (AText[1] = '0')) then
    raise EDidacticValidation.Create('Noncanonical unsigned integer.');
  for Character in AText do
    if not CharInSet(Character, ['0'..'9']) then
      raise EDidacticValidation.Create('Unsigned integer requires decimal digits.');
  if not TryStrToUInt64(AText, Result) then raise EDidacticValidation.Create('Unsigned integer overflow.');
end;

function JsonText(const AObject: TJSONObject; const AName: string): string;
var Value: TJSONValue;
begin
  if not Assigned(AObject) then raise EDidacticValidation.Create('JSON object required.');
  Value := AObject.GetValue(AName);
  if not (Value is TJSONString) then raise EDidacticValidation.Create('String required: ' + AName);
  Result := Value.Value;
end;

function JsonUInt(const AObject: TJSONObject; const AName: string): UInt64;
begin
  Result := CanonicalUInt(JsonText(AObject, AName));
end;

procedure RequireFields(const AObject: TJSONObject; const ANames: array of string);
var Name: string; Pair: TJSONPair; Count: Integer;
begin
  if not Assigned(AObject) or (AObject.Count <> Length(ANames)) then
    raise EDidacticValidation.Create('Unexpected JSON fields.');
  for Name in ANames do
  begin
    Count := 0;
    for Pair in AObject do if Pair.JsonString.Value = Name then Inc(Count);
    if Count <> 1 then raise EDidacticValidation.Create('Missing or duplicate JSON field: ' + Name);
  end;
end;

function FixedHex(const AText: string; const ABytes: Integer): TBytes;
begin
  if Length(AText) <> ABytes * 2 then raise EDidacticValidation.Create('Invalid hexadecimal length.');
  try Result := DecodeHex(AText); except
    on Error: Exception do raise EDidacticValidation.Create(Error.Message);
  end;
  if BytesToLowerHex(Result) <> AText then raise EDidacticValidation.Create('Hexadecimal must be lowercase without prefix.');
end;

function UIntBytes(const AValue: UInt64; const ASize: Integer): TBytes;
var Index: Integer; Remaining: UInt64;
begin
  if (ASize < 1) or (ASize > 8) then raise EDidacticValidation.Create('Invalid integer width.');
  SetLength(Result, ASize);
  Remaining := AValue;
  for Index := ASize - 1 downto 0 do
  begin
    Result[Index] := Byte(Remaining and $FF);
    Remaining := Remaining shr 8;
  end;
  if Remaining <> 0 then raise EDidacticValidation.Create('Integer does not fit binary field.');
end;

function TextBytes(const AText: string): TBytes;
var Encoded: TBytes;
begin
  Encoded := TEncoding.UTF8.GetBytes(AText);
  Result := UIntBytes(Length(Encoded), 4) + Encoded;
end;

procedure SaveAtomicUtf8(const APath, AText: string);
var Path, Temporary: string; Identifier: TGUID; Bytes: TBytes; Stream: TFileStream;
begin
  Path := TPath.GetFullPath(APath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
  CreateGUID(Identifier);
  Temporary := Path + '.' + GUIDToString(Identifier) + '.tmp';
  try
    Bytes := TEncoding.UTF8.GetBytes(AText);
    Stream := TFileStream.Create(Temporary, fmCreate or fmShareExclusive);
    try
      if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
      if not FlushFileBuffers(Stream.Handle) then RaiseLastOSError;
    finally Stream.Free; end;
    if not MoveFileEx(PChar(Temporary), PChar(Path), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  finally if TFile.Exists(Temporary) then TFile.Delete(Temporary); end;
end;

end.
