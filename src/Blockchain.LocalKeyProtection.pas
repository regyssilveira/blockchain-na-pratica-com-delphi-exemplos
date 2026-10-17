unit Blockchain.LocalKeyProtection;

interface

uses System.SysUtils;

type
  ELocalKeyProtection = class(Exception);

  // Exercicio Windows/usuario atual. Nao e cofre, backup ou carteira de producao.
  TLocalKeyProtection = class
  public
    class function Protect(const APrivateKey: TBytes): TBytes; static;
    class function Unprotect(const AProtected, AExpectedAccount: TBytes): TBytes; static;
    class procedure SaveNew(const APath: string; const AProtected: TBytes); static;
    class function Load(const APath: string; const AExpectedAccount: TBytes): TBytes; static;
    class procedure ClearOwned(var ABytes: TBytes); static;
  end;

implementation

uses System.Classes, Winapi.Windows, Blockchain.Ethereum;

const
  ProtectionWithoutUserInterface = $00000001;
  MaximumProtectedSize = 65536;

function CryptProtectData(var AInput: DATA_BLOB; ADescription: PWideChar;
  AEntropy, AReserved, APrompt: Pointer; AFlags: DWORD;
  out AOutput: DATA_BLOB): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';
function CryptUnprotectData(var AInput: DATA_BLOB; ADescription,
  AEntropy, AReserved, APrompt: Pointer; AFlags: DWORD;
  out AOutput: DATA_BLOB): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';

function Header: TBytes;
begin
  // DPK1 identifica somente o formato deste exercicio, nao autentica a origem.
  Result := TBytes.Create($44, $50, $4B, $31);
end;

procedure CheckProtected(const AProtected: TBytes);
var ExpectedHeader: TBytes;
begin
  ExpectedHeader := Header;
  if (Length(AProtected) <= 4) or (Length(AProtected) > MaximumProtectedSize) then
    raise ELocalKeyProtection.Create('Invalid protected file size.');
  if not CompareMem(@AProtected[0], @ExpectedHeader[0], 4) then
    raise ELocalKeyProtection.Create('Unsupported protected file format.');
end;

class procedure TLocalKeyProtection.ClearOwned(var ABytes: TBytes);
begin
  // Limpeza do buffer controlado. Nao promete apagar copias, swap ou dumps.
  if Length(ABytes) > 0 then FillChar(ABytes[0], Length(ABytes), 0);
  ABytes := nil;
end;

class function TLocalKeyProtection.Protect(const APrivateKey: TBytes): TBytes;
var Input, Output: DATA_BLOB; PublicKey: TBytes;
begin
  Result := nil;
  // Valida comprimento e intervalo sem aceitar o zero como chave privada.
  try PublicKey := PublicKeyFromPrivateKey(APrivateKey);
  except on Error: EArgumentException do
    raise ELocalKeyProtection.Create('Invalid private key for protection.'); end;
  PublicKey := nil;
  Input := Default(DATA_BLOB);
  Output := Default(DATA_BLOB);
  Input.cbData := Length(APrivateKey);
  Input.pbData := @APrivateKey[0];
  try
    // Nao usar CRYPTPROTECT_LOCAL_MACHINE: manter o escopo do usuario atual.
    if not CryptProtectData(Input, 'Document registry lab v1', nil, nil, nil,
      ProtectionWithoutUserInterface, Output) then
      raise ELocalKeyProtection.Create('Windows could not protect the test key.');
    if (Output.cbData = 0) or (Output.cbData > MaximumProtectedSize - 4) then
      raise ELocalKeyProtection.Create('Unexpected protected data size.');
    Result := Header;
    SetLength(Result, 4 + Output.cbData);
    Move(Output.pbData^, Result[4], Output.cbData);
  finally
    if Assigned(Output.pbData) then LocalFree(HLOCAL(Output.pbData));
  end;
end;

class function TLocalKeyProtection.Unprotect(const AProtected,
  AExpectedAccount: TBytes): TBytes;
var Input, Output: DATA_BLOB; Account: TBytes;
begin
  Result := nil;
  CheckProtected(AProtected);
  if Length(AExpectedAccount) <> 20 then
    raise ELocalKeyProtection.Create('Expected account must contain 20 bytes.');
  Input := Default(DATA_BLOB);
  Output := Default(DATA_BLOB);
  Input.cbData := Length(AProtected) - 4;
  Input.pbData := @AProtected[4];
  try
    if not CryptUnprotectData(Input, nil, nil, nil, nil,
      ProtectionWithoutUserInterface, Output) then
      raise ELocalKeyProtection.Create('Windows could not recover the protected test key.');
    if Output.cbData <> 32 then
      raise ELocalKeyProtection.Create('Recovered value is not a 32-byte key.');
    SetLength(Result, 32);
    Move(Output.pbData^, Result[0], 32);
    try
      Account := AddressFromPublicKey(PublicKeyFromPrivateKey(Result));
      if not CompareMem(@Account[0], @AExpectedAccount[0], 20) then
        raise ELocalKeyProtection.Create('Recovered key differs from expected account.');
    except
      on Error: Exception do
      begin
        ClearOwned(Result);
        raise ELocalKeyProtection.Create('Recovered key differs from expected account or key format.');
      end;
    end;
  finally
    if Assigned(Output.pbData) then
    begin
      FillChar(Output.pbData^, Output.cbData, 0);
      LocalFree(HLOCAL(Output.pbData));
    end;
  end;
end;

class procedure TLocalKeyProtection.SaveNew(const APath: string;
  const AProtected: TBytes);
var Handle: THandle; Written: DWORD;
begin
  CheckProtected(AProtected);
  Handle := CreateFile(PChar(APath), GENERIC_WRITE, 0, nil, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then
    raise ELocalKeyProtection.Create('Cannot create a new protected file.');
  try
    if not WriteFile(Handle, AProtected[0], Length(AProtected), Written, nil) or
      (Written <> DWORD(Length(AProtected))) or not FlushFileBuffers(Handle) then
      raise ELocalKeyProtection.Create('Could not finish writing the protected file.');
  finally CloseHandle(Handle); end;
end;

class function TLocalKeyProtection.Load(const APath: string;
  const AExpectedAccount: TBytes): TBytes;
var Stream: TFileStream; ProtectedBytes: TBytes;
begin
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size <= 4) or (Stream.Size > MaximumProtectedSize) then
      raise ELocalKeyProtection.Create('Invalid protected file size.');
    SetLength(ProtectedBytes, Stream.Size);
    Stream.ReadBuffer(ProtectedBytes[0], Length(ProtectedBytes));
  finally Stream.Free; end;
  Result := Unprotect(ProtectedBytes, AExpectedAccount);
end;

end.
