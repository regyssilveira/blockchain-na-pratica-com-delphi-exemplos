program Chapter07.Transactions;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Blockchain.Primitives,
  Blockchain.Ethereum,
  Didactic.Codec,
  Didactic.Transaction,
  Didactic.Chain;

procedure Conferir(const ANome: string; const ACondicao: Boolean);
begin
  Writeln(ANome, '=', BoolToStr(ACondicao, True));
  if not ACondicao then
    raise Exception.Create('Resultado inesperado: ' + ANome);
end;

function ValidacaoRejeitada(const ATransacao: TDocumentTransaction;
  const APolitica: TDidacticPolicy): Boolean;
begin
  try
    ATransacao.Validate(APolitica);
    Result := False;
  except
    on Error: EDidacticValidation do Result := True;
  end;
end;

function AplicacaoRejeitada(const AEstado: TDidacticState;
  const ATransacao: TDocumentTransaction;
  const APolitica: TDidacticPolicy): Boolean;
begin
  try
    AEstado.Apply(ATransacao, 1, APolitica);
    Result := False;
  except
    on Error: EDidacticValidation do Result := True;
  end;
end;

procedure Run;
var
  Politica, OutraPolitica: TDidacticPolicy;
  ChaveA, ChaveB: TBytes;
  HashOriginal, HashOutro, ContaA, ContaB: string;
  TransacaoOriginal, Candidata, Proxima: TDocumentTransaction;
  Historico: TArray<TDocumentTransaction>;
  Estado, Reconstruido, ForaDeOrdem: TDidacticState;
  Registro: TDocumentEntry;
  Transacao: TDocumentTransaction;

  procedure Aplicar(const ATransacao: TDocumentTransaction);
  begin
    // 1 preenche BlockHeight como referencia sintetica; nenhum bloco e criado.
    Estado.Apply(ATransacao, 1, Politica);
    Historico := Historico + TArray<TDocumentTransaction>.Create(ATransacao);
  end;

begin
  if ParamCount <> 2 then
    raise EArgumentException.Create(
      'Uso: Chapter07.Transactions arquivo-original outro-arquivo');
  HashOriginal := Sha256File(ParamStr(1));
  HashOutro := Sha256File(ParamStr(2));
  if HashOriginal = HashOutro then
    raise EArgumentException.Create('O experimento exige conteudos diferentes.');

  Politica := TDidacticPolicy.Create;
  OutraPolitica := TDidacticPolicy.Create(3);
  // Valores privados publicados para teste, nunca para proteger dados reais.
  ChaveA := DecodeHex(StringOfChar('0', 63) + '1');
  ChaveB := DecodeHex(StringOfChar('0', 63) + '2');
  TransacaoOriginal := TDocumentTransaction.Sign(
    Politica, ChaveA, HashOriginal, 1);
  ContaA := TransacaoOriginal.Account;
  Historico := nil;
  Estado := TDidacticState.Create;
  try
    TransacaoOriginal.Validate(Politica);
    Registro := Estado.Lookup(ContaA, HashOriginal);
    Conferir('validacao_sem_aplicacao',
      (Estado.SequenceOf(ContaA) = 0) and not Registro.Exists);

    Aplicar(TransacaoOriginal);
    Registro := Estado.Lookup(ContaA, HashOriginal);
    Conferir('primeiro_registro', Registro.Exists and
      (Registro.TransactionId = TransacaoOriginal.Id));

    Candidata := TransacaoOriginal;
    Candidata.DocumentHash := 'zz';
    Conferir('formato_invalido_rejeitado', ValidacaoRejeitada(Candidata, Politica));
    Candidata := TransacaoOriginal;
    Candidata.DocumentHash := HashOutro;
    Conferir('adulteracao_rejeitada', ValidacaoRejeitada(Candidata, Politica));
    Conferir('reenvio_rejeitado',
      AplicacaoRejeitada(Estado, TransacaoOriginal, Politica));

    Candidata := TDocumentTransaction.Sign(Politica, ChaveA, HashOutro, 1);
    Candidata.Validate(Politica);
    Conferir('sequencia_reutilizada_rejeitada',
      AplicacaoRejeitada(Estado, Candidata, Politica));
    Candidata := TDocumentTransaction.Sign(Politica, ChaveA, HashOutro, 3);
    Conferir('salto_rejeitado', AplicacaoRejeitada(Estado, Candidata, Politica));
    Candidata := TDocumentTransaction.Sign(Politica, ChaveA, HashOriginal, 2);
    Conferir('documento_duplicado_rejeitado',
      (Candidata.Id <> TransacaoOriginal.Id) and
      AplicacaoRejeitada(Estado, Candidata, Politica));
    Candidata := TDocumentTransaction.Sign(OutraPolitica, ChaveA, HashOutro, 2);
    Conferir('outra_rede_rejeitada',
      AplicacaoRejeitada(Estado, Candidata, Politica));

    Registro := Estado.Lookup(ContaA, HashOutro);
    Conferir('estado_apos_rejeicoes_preservado',
      (Estado.SequenceOf(ContaA) = 1) and not Registro.Exists and
      (Length(Historico) = 1));

    Candidata := TDocumentTransaction.Sign(Politica, ChaveB, HashOriginal, 1);
    ContaB := Candidata.Account;
    Aplicar(Candidata);
    Registro := Estado.Lookup(ContaB, HashOriginal);
    Conferir('mesmo_documento_outra_conta', Registro.Exists and
      (Registro.TransactionId = Candidata.Id) and
      (Estado.SequenceOf(ContaA) = 1) and (Estado.SequenceOf(ContaB) = 1));

    Proxima := TDocumentTransaction.Sign(Politica, ChaveA, HashOutro, 2);
    Aplicar(Proxima);
    Registro := Estado.Lookup(ContaA, HashOutro);
    Conferir('proxima_sequencia', Registro.Exists and
      (Registro.TransactionId = Proxima.Id) and (Estado.SequenceOf(ContaA) = 2));

    Reconstruido := TDidacticState.Create;
    try
      for Transacao in Historico do Reconstruido.Apply(Transacao, 1, Politica);
      Registro := Reconstruido.Lookup(ContaA, HashOriginal);
      Conferir('reconstrucao_do_estado', (Length(Historico) = 3) and
        (Reconstruido.SequenceOf(ContaA) = 2) and
        (Reconstruido.SequenceOf(ContaB) = 1) and Registro.Exists and
        (Registro.TransactionId = TransacaoOriginal.Id) and
        Reconstruido.ContainsId(Proxima.Id) and
        Reconstruido.Lookup(ContaA, HashOutro).Exists and
        Reconstruido.Lookup(ContaB, HashOriginal).Exists);
    finally Reconstruido.Free; end;

    ForaDeOrdem := TDidacticState.Create;
    try
      Conferir('ordem_invertida_rejeitada',
        AplicacaoRejeitada(ForaDeOrdem, Proxima, Politica));
    finally ForaDeOrdem.Free; end;
  finally Estado.Free; end;
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
