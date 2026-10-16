program Chapter06.Signatures;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Blockchain.Primitives,
  Blockchain.Ethereum;

procedure Run;
const
  // Chave publicamente conhecida do vetor EIP-155. Somente laboratorio.
  TestPrivateKeyHex =
    '4646464646464646464646464646464646464646464646464646464646464646';
var
  ChavePrivada, ChavePublica, OutraChavePublica: TBytes;
  ResumoOriginal, ResumoAlterado: TBytes;
  AssinaturaOriginal, AssinaturaAlterada: TEthereumSignature;
begin
  if ParamCount <> 2 then
    raise EArgumentException.Create(
      'Uso: Chapter06.Signatures arquivo-original arquivo-alterado');

  ChavePrivada := DecodeHex(TestPrivateKeyHex);
  ChavePublica := PublicKeyFromPrivateKey(ChavePrivada);
  ResumoOriginal := DecodeHex(Sha256File(ParamStr(1)));
  ResumoAlterado := DecodeHex(Sha256File(ParamStr(2)));
  AssinaturaOriginal := SignDigest(ResumoOriginal, ChavePrivada);

  Writeln('original=', BoolToStr(
    VerifyDigest(ResumoOriginal, ChavePublica, AssinaturaOriginal), True));
  Writeln('mensagem_alterada=', BoolToStr(
    VerifyDigest(ResumoAlterado, ChavePublica, AssinaturaOriginal), True));

  // Segunda chave conhecida de teste: inteiro 1 em 32 bytes.
  OutraChavePublica := PublicKeyFromPrivateKey(
    DecodeHex(StringOfChar('0', 63) + '1'));
  Writeln('outra_chave=', BoolToStr(
    VerifyDigest(ResumoOriginal, OutraChavePublica, AssinaturaOriginal), True));

  AssinaturaAlterada := SignDigest(ResumoAlterado, ChavePrivada);
  Writeln('assinatura_de_outra_mensagem=', BoolToStr(
    VerifyDigest(ResumoOriginal, ChavePublica, AssinaturaAlterada), True));
  Writeln('alterada_assinada_novamente=', BoolToStr(
    VerifyDigest(ResumoAlterado, ChavePublica, AssinaturaAlterada), True));
end;

begin
  try
    Run;
  except
    on Error: Exception do
    begin
      Writeln(ErrOutput, Error.ClassName, ': ', Error.Message);
      ExitCode := 1;
    end;
  end;
end.
