unit Didactic.Transaction;

interface

uses System.SysUtils, System.JSON, Didactic.Codec;

type
  TDocumentTransaction = record
    Network: string;
    PublicKey: string;
    DocumentHash: string;
    Sequence: UInt64;
    SignatureR: string;
    SignatureS: string;
    Parity: Byte;
    class function Sign(const APolicy: TDidacticPolicy; const APrivateKey: TBytes;
      const ADocumentHash: string; const ASequence: UInt64): TDocumentTransaction; static;
    function Payload: TBytes;
    function SignedBytes: TBytes;
    function Id: string;
    function Account: string;
    procedure Validate(const APolicy: TDidacticPolicy);
    function ToJson: TJSONObject;
    class function FromJson(const AObject: TJSONObject): TDocumentTransaction; static;
  end;

implementation

uses Blockchain.Primitives, Blockchain.Ethereum, ClpBigInteger;

function TDocumentTransaction.Payload: TBytes;
begin
  if (Length(Network) = 0) or (Length(Network) > 64) then raise EDidacticValidation.Create('Invalid transaction network.');
  if Sequence = 0 then raise EDidacticValidation.Create('Sequence starts at one.');
  Result := TextBytes('DIDACTIC-TX-1') + TextBytes(Network) + FixedHex(PublicKey, 65) +
    FixedHex(DocumentHash, 32) + UIntBytes(Sequence, 8);
end;

function TDocumentTransaction.SignedBytes: TBytes;
begin
  if Parity > 1 then raise EDidacticValidation.Create('Invalid signature parity.');
  Result := Payload + FixedHex(SignatureR, 32) + FixedHex(SignatureS, 32) + UIntBytes(Parity, 1);
end;

function TDocumentTransaction.Id: string;
begin
  Result := Sha256Bytes(SignedBytes);
end;

function TDocumentTransaction.Account: string;
begin
  Result := Sha256Bytes(FixedHex(PublicKey, 65));
end;

class function TDocumentTransaction.Sign(const APolicy: TDidacticPolicy;
  const APrivateKey: TBytes; const ADocumentHash: string;
  const ASequence: UInt64): TDocumentTransaction;
var Signature: TEthereumSignature;
begin
  Result := Default(TDocumentTransaction);
  Result.Network := APolicy.NetworkId;
  Result.PublicKey := BytesToLowerHex(PublicKeyFromPrivateKey(APrivateKey));
  Result.DocumentHash := ADocumentHash;
  Result.Sequence := ASequence;
  // Reuso das primitivas secp256k1 Pascal: formato/digest deste protocolo NAO sao Ethereum.
  Signature := SignDigest(FixedHex(Sha256Bytes(Result.Payload), 32), APrivateKey);
  Result.SignatureR := BytesToLowerHex(TExactUInt256.FromDecimal(Signature.R.ToString(10)).ToBigEndianBytes);
  Result.SignatureS := BytesToLowerHex(TExactUInt256.FromDecimal(Signature.S.ToString(10)).ToBigEndianBytes);
  Result.Parity := Signature.YParity;
  Result.Validate(APolicy);
end;

procedure TDocumentTransaction.Validate(const APolicy: TDidacticPolicy);
var Signature: TEthereumSignature;
begin
  if Network <> APolicy.NetworkId then raise EDidacticValidation.Create('Transaction belongs to another network.');
  try
    FixedHex(SignatureR, 32);
    FixedHex(SignatureS, 32);
    Signature.R := TBigInteger.Create(SignatureR, 16);
    Signature.S := TBigInteger.Create(SignatureS, 16);
    Signature.YParity := Parity;
    if not VerifyDigest(FixedHex(Sha256Bytes(Payload), 32), FixedHex(PublicKey, 65), Signature) then
      raise EDidacticValidation.Create('Signature does not match transaction.');
  except
    on Error: EDidacticValidation do raise;
    on Error: Exception do raise EDidacticValidation.Create('Invalid transaction: ' + Error.Message);
  end;
end;

function TDocumentTransaction.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('network', Network);
  Result.AddPair('publicKey', PublicKey);
  Result.AddPair('documentHash', DocumentHash);
  Result.AddPair('sequence', UIntToStr(Sequence));
  Result.AddPair('r', SignatureR);
  Result.AddPair('s', SignatureS);
  Result.AddPair('parity', UIntToStr(Parity));
end;

class function TDocumentTransaction.FromJson(const AObject: TJSONObject): TDocumentTransaction;
var ParityValue: UInt64;
begin
  RequireFields(AObject, ['network','publicKey','documentHash','sequence','r','s','parity']);
  Result.Network := JsonText(AObject, 'network');
  Result.PublicKey := JsonText(AObject, 'publicKey');
  Result.DocumentHash := JsonText(AObject, 'documentHash');
  Result.Sequence := JsonUInt(AObject, 'sequence');
  Result.SignatureR := JsonText(AObject, 'r');
  Result.SignatureS := JsonText(AObject, 's');
  ParityValue := JsonUInt(AObject, 'parity');
  if ParityValue > 1 then raise EDidacticValidation.Create('Invalid signature parity.');
  Result.Parity := ParityValue;
  Result.SignedBytes;
end;

end.
