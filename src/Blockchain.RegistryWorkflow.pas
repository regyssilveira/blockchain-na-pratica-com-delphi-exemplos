unit Blockchain.RegistryWorkflow;

interface

uses System.SysUtils, System.Classes;

type
  TRegistryAction = (raHash, raDeploy, raRegister, raTrackDeployment,
    raTrackRegistration, raVerify);

  TRegistryRequest = record
    Action: TRegistryAction;
    Port: Word;
    ArtifactPath: string;
    DeploymentPath: string;
    CheckpointPath: string;
    DocumentPath: string;
    TrackingMs: Cardinal;
  end;

  TRegistryResult = record
    State: string;
    StoredState: string;
    ReceiptObserved: Boolean;
    TransactionHash: string;
    DocumentHash: string;
    ContractAddress: string;
    Account: string;
    BlockNumber: string;
    HasLookup: Boolean;
    Found: Boolean;
    MatchesDocument: Boolean;
    Diagnostic: string;
    ErrorText: string;
  end;

  TRegistryWorkflow = class
  public
    class function Execute(const ARequest: TRegistryRequest): TRegistryResult; static;
    class function Failure(const ARequest: TRegistryRequest;
      const AMessage: string): TRegistryResult; static;
  end;

  // Um pedido imutavel por thread; controles VCL nunca entram nesta unidade.
  TRegistryWorker = class(TThread)
  private
    FRequest: TRegistryRequest;
    FResult: TRegistryResult;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARequest: TRegistryRequest);
    property Outcome: TRegistryResult read FResult;
  end;

implementation

uses System.JSON, System.IOUtils, Blockchain.Primitives, Blockchain.Ethereum,
  Blockchain.DocumentRegistry, Blockchain.TransactionJournal;

function CheckpointPath(const ARequest: TRegistryRequest): string;
begin
  if ARequest.Action in [raDeploy, raTrackDeployment] then
    Result := ARequest.DeploymentPath
  else Result := ARequest.CheckpointPath;
end;

function Describe(const ACheckpoint: TTransactionCheckpoint): TRegistryResult;
begin
  Result := Default(TRegistryResult);
  Result.State := ACheckpoint.State;
  Result.StoredState := ACheckpoint.State;
  Result.TransactionHash := ACheckpoint.Hash;
  Result.DocumentHash := ACheckpoint.DocumentHash;
  Result.ContractAddress := ACheckpoint.ContractAddress;
  Result.Account := ACheckpoint.Account;
  Result.BlockNumber := ACheckpoint.BlockNumber;
  Result.Diagnostic := ACheckpoint.Diagnostic;
end;

class function TRegistryWorkflow.Failure(const ARequest: TRegistryRequest;
  const AMessage: string): TRegistryResult;
begin
  Result := Default(TRegistryResult);
  Result.State := 'unknown';
  // Ler acompanhamento nunca envia transacao; arquivo ilegivel nao vira rejeicao.
  if ARequest.Action <> raHash then
    try
      if TFile.Exists(CheckpointPath(ARequest)) then
        Result := Describe(TTransactionCheckpoint.Load(CheckpointPath(ARequest)));
    except
      on Error: Exception do Result.State := 'unknown';
    end;
  // A falha atual nao pode ser apresentada como sucesso historico.
  Result.State := 'unknown';
  Result.ErrorText := AMessage;
end;

class function TRegistryWorkflow.Execute(const ARequest: TRegistryRequest): TRegistryResult;
var
  Artifact: TJSONValue;
  Runtime, Creation, PrivateKey, DocumentHash: TBytes;
  Registry: TDocumentRegistry;
  Checkpoint: TTransactionCheckpoint;
  Receipt: TJSONObject;
  Submission: TLocalSubmission;
  Found: TDocumentRecord;
  Path: string;
  function Load(const APath: string; const ARegistration: Boolean): TTransactionCheckpoint;
  begin
    Result := TTransactionCheckpoint.Load(APath);
    if (Result.Port <> ARequest.Port) or (Result.ChainId <> '31337') or
      (Result.RuntimeHex <> '0x' + BytesToLowerHex(Runtime)) then
      raise EArgumentException.Create('Acompanhamento pertence a outra configuracao local.');
    if ARegistration <> (Result.DocumentHash <> '') then
      raise EArgumentException.Create('Tipo de acompanhamento incorreto.');
  end;
begin
  Result := Default(TRegistryResult);
  if ARequest.Action = raHash then
  begin
    Result.DocumentHash := Sha256File(ARequest.DocumentPath);
    Result.State := 'hashed';
    Exit;
  end;
  if ARequest.Port = 0 then raise EArgumentException.Create('Porta local invalida.');
  if (ARequest.Action in [raTrackDeployment, raTrackRegistration]) and
    ((ARequest.TrackingMs = 0) or (ARequest.TrackingMs > 30000)) then
    raise EArgumentException.Create('Prazo deve estar entre 1 e 30000 ms.');
  // Ler o arquivo antes de assinar evita submissao quando a entrada nao abre.
  if ARequest.Action in [raRegister, raVerify] then
    DocumentHash := ParseDocumentHash(Sha256File(ARequest.DocumentPath));
  Artifact := TJSONObject.ParseJSONValue(TFile.ReadAllText(ARequest.ArtifactPath, TEncoding.UTF8));
  Registry := nil;
  try
    if not (Artifact is TJSONObject) then raise EArgumentException.Create('Artefato invalido.');
    Runtime := DecodeHex(TJSONObject(Artifact).GetValue<string>('runtimeBytecode'));
    Registry := TDocumentRegistry.Create(ARequest.Port,
      TExactUInt256.FromDecimal('31337'), Runtime);
    // Valor publicamente conhecido, nunca uma chave ou saldo de producao.
    PrivateKey := DecodeHex(StringReplace(StringOfChar('x', 32), 'x', '46', [rfReplaceAll]));
    Path := CheckpointPath(ARequest);
    case ARequest.Action of
      raDeploy:
        begin
          Creation := DecodeHex(TJSONObject(Artifact).GetValue<string>('creationBytecode'));
          Registry.JournalPath := Path;
          Submission := Registry.Deploy(Creation, PrivateKey);
          Result := Describe(Load(Path, False));
          if Result.TransactionHash <> Submission.Hash then
            raise EArgumentException.Create('Hash preservado divergiu do envio.');
        end;
      raRegister:
        begin
          Checkpoint := Load(ARequest.DeploymentPath, False);
          if Checkpoint.State <> 'succeeded' then
            raise EArgumentException.Create('Acompanhe a implantacao ate o sucesso antes de registrar.');
          Registry.Attach(Checkpoint.ContractAddress);
          Registry.JournalPath := Path;
          Submission := Registry.RegisterHash(DocumentHash, PrivateKey);
          Result := Describe(Load(Path, True));
          if Result.TransactionHash <> Submission.Hash then
            raise EArgumentException.Create('Hash preservado divergiu do envio.');
        end;
      raTrackDeployment, raTrackRegistration:
        begin
          Checkpoint := Load(Path, ARequest.Action = raTrackRegistration);
          Registry.JournalPath := Path;
          Receipt := Registry.AwaitReceipt(Checkpoint.Hash, ARequest.TrackingMs, 100);
          try
            Result := Describe(Load(Path, ARequest.Action = raTrackRegistration));
            Result.ReceiptObserved := Assigned(Receipt);
            if not Result.ReceiptObserved and
              ((Result.StoredState = 'succeeded') or (Result.StoredState = 'reverted')) then
            begin
              Result.State := 'unknown';
              Result.Diagnostic := 'Previously observed receipt is now absent; verify history before another send.';
            end;
            // O arquivo preserva a observacao historica; a tela mostra a consulta atual.
          finally Receipt.Free; end;
        end;
      raVerify:
        begin
          Checkpoint := Load(Path, True);
          Registry.Attach(Checkpoint.ContractAddress);
          Found := Registry.Lookup(DecodeHex(Checkpoint.Account), DocumentHash);
          Result := Describe(Checkpoint);
          Result.HasLookup := True;
          Result.Found := Found.Exists;
          Result.DocumentHash := BytesToLowerHex(DocumentHash);
          Result.MatchesDocument := Result.DocumentHash = Checkpoint.DocumentHash;
          Result.BlockNumber := Found.BlockNumber.ToDecimal;
          if Found.Exists and Result.MatchesDocument and (Checkpoint.BlockNumber <> '') and
            (Result.BlockNumber <> Checkpoint.BlockNumber) then
            raise EArgumentException.Create('Bloco consultado diverge do acompanhamento.');
        end;
    end;
  finally
    Registry.Free;
    Artifact.Free;
  end;
end;

constructor TRegistryWorker.Create(const ARequest: TRegistryRequest);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FRequest := ARequest;
end;

procedure TRegistryWorker.Execute;
begin
  try
    FResult := TRegistryWorkflow.Execute(FRequest);
  except
    on Error: Exception do
      FResult := TRegistryWorkflow.Failure(FRequest, Error.ClassName + ': ' + Error.Message);
  end;
end;

end.
