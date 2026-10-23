program Chapter17.Trace;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils,
  Blockchain.Primitives, Blockchain.Ethereum;

procedure Run;
var
  DocumentBytes, DocumentHash, PrivateKey, PublicKey, Raw: TBytes;
  Transaction: TType2Transaction;
  Signature: TEthereumSignature;
  Output: TJSONObject;
begin
  if ParamCount <> 1 then raise EArgumentException.Create('Use Chapter17.Trace <test-file>.');
  DocumentBytes := TFile.ReadAllBytes(ParamStr(1));
  DocumentHash := DecodeHex(Sha256Bytes(DocumentBytes));
  PrivateKey := DecodeHex(StringOfChar('0', 63) + '1'); // chave publicada de teste
  PublicKey := PublicKeyFromPrivateKey(PrivateKey);
  Transaction := Default(TType2Transaction);
  Transaction.ChainId := TExactUInt256.FromDecimal('31337');
  Transaction.Nonce := TExactUInt256.FromDecimal('0');
  Transaction.MaxPriorityFeePerGas := TExactUInt256.FromDecimal('1000000000');
  Transaction.MaxFeePerGas := TExactUInt256.FromDecimal('3000000000');
  Transaction.GasLimit := TExactUInt256.FromDecimal('150000');
  // Destino apenas ilustrativo: nao afirmar que existe contrato nesse endereco.
  Transaction.Destination := DecodeHex(StringOfChar('0', 39) + '1');
  Transaction.Amount := TExactUInt256.FromDecimal('0');
  Transaction.Data := AbiCall('register(bytes32)', [AbiBytes32(DocumentHash)]);
  Signature := SignDigest(Transaction.SigningHash, PrivateKey);
  Raw := Transaction.SignedEnvelope(Signature);
  Output := TJSONObject.Create;
  try
    Output.AddPair('documentBytes', BytesToLowerHex(DocumentBytes));
    Output.AddPair('documentHash', BytesToLowerHex(DocumentHash));
    Output.AddPair('selector', BytesToLowerHex(AbiSelector('register(bytes32)')));
    Output.AddPair('callData', BytesToLowerHex(Transaction.Data));
    Output.AddPair('callBytes', TJSONNumber.Create(Length(Transaction.Data)));
    Output.AddPair('rlpZero', BytesToLowerHex(RlpInteger(Transaction.Nonce)));
    Output.AddPair('unsignedEnvelope', BytesToLowerHex(Transaction.UnsignedEnvelope));
    Output.AddPair('signingHash', BytesToLowerHex(Transaction.SigningHash));
    Output.AddPair('signedEnvelope', BytesToLowerHex(Raw));
    Output.AddPair('transactionHash', BytesToLowerHex(Keccak256(Raw)));
    Output.AddPair('signatureVerified', TJSONBool.Create(VerifyDigest(Transaction.SigningHash, PublicKey, Signature)));
    Output.AddPair('recoveredAccount', BytesToLowerHex(AddressFromPublicKey(RecoverPublicKey(Transaction.SigningHash, Signature))));
    Output.AddPair('sent', TJSONBool.Create(False));
    Output.AddPair('scope', 'Offline trace with illustrative destination; no receipt or deployed contract.');
    Writeln(Output.ToJSON);
  finally
    Output.Free;
    FillChar(PrivateKey[0], Length(PrivateKey), 0);
  end;
end;

begin
  try Run; except on Error: Exception do
  begin Writeln(Error.ClassName, ': ', Error.Message); System.ExitCode := 1; end; end;
end.
