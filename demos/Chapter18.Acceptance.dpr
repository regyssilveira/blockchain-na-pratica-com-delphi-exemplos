program Chapter18.Acceptance;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, Winapi.Windows,
  Blockchain.RegistryWorkflow in '..\src\Blockchain.RegistryWorkflow.pas',
  Blockchain.TransactionJournal, Blockchain.Primitives, Blockchain.LocalRpc;

var
  Port: Word;
  OutputDirectory: string;
  Checks: TJSONArray;
  Request: TRegistryRequest;

procedure Check(const AName: string; const ACondition: Boolean);
begin
  if not ACondition then raise Exception.Create('Acceptance failed: ' + AName);
  Checks.Add(AName);
  Writeln(AName, '=True');
end;

function Call(const AMethod: string; AParameters: TJSONArray): TJSONValue;
var Rpc: TLocalRpc;
begin
  Rpc := TLocalRpc.Create(Port);
  try Result := Rpc.Call(AMethod, AParameters); finally Rpc.Free; end;
end;

procedure Mine;
var Value: TJSONValue;
begin
  Value := Call('evm_mine', TJSONArray.Create);
  Value.Free;
end;

function Nonce: string;
var Value: TJSONValue;
begin
  Value := Call('eth_getTransactionCount',
    TJSONArray.Create('0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f', 'pending'));
  try Result := Value.Value; finally Value.Free; end;
end;

function RunWorker(const ARequest: TRegistryRequest): TRegistryResult;
var Worker: TRegistryWorker;
begin
  Worker := TRegistryWorker.Create(ARequest);
  try
    Worker.Start;
    if WaitForSingleObject(Worker.Handle, 12000) <> WAIT_OBJECT_0 then
      raise Exception.Create('Worker deadline expired.');
    Worker.WaitFor;
    Result := Worker.Outcome;
  finally Worker.Free; end;
end;

procedure ExpectArgumentError(const AName: string);
var Rejected: Boolean;
begin
  Rejected := False;
  try TRegistryWorkflow.Execute(Request);
  except on Error: EArgumentException do Rejected := True; end;
  Check(AName, Rejected);
end;

procedure Run;
var
  Result, Original, Duplicate: TRegistryResult;
  Document: TJSONValue;
  Summary: TJSONObject;
  OriginalNonce, OriginalText, OriginalHash, CopyPath, ChangedPath, Path: string;
  OriginalCheckpoint: TTransactionCheckpoint;
  PortNumber: Integer;
begin
  if (ParamCount <> 2) and (ParamCount <> 3) then
    raise EArgumentException.Create('Usage: Chapter18.Acceptance port output-directory [check-ui|stopped]');
  PortNumber := StrToInt(ParamStr(1));
  if (PortNumber < 1024) or (PortNumber > 65535) then raise EArgumentException.Create('Invalid port.');
  Port := PortNumber;
  OutputDirectory := TPath.GetFullPath(ParamStr(2));
  TDirectory.CreateDirectory(OutputDirectory);
  Request := Default(TRegistryRequest);
  Request.Port := Port;
  Request.ArtifactPath := TPath.GetFullPath('build\contract\DocumentRegistry.json');
  Request.DeploymentPath := TPath.Combine(OutputDirectory, 'deployment.json');
  Request.CheckpointPath := TPath.Combine(OutputDirectory, 'registration.json');
  Request.DocumentPath := TPath.GetFullPath('fixtures\p02\document-a.txt');
  Request.TrackingMs := 300;
  Checks := TJSONArray.Create;
  try
    if ParamCount = 3 then
    begin
      Request.DeploymentPath := TPath.Combine(OutputDirectory, 'deployment-ui.json');
      Request.Action := raTrackDeployment;
      OriginalCheckpoint := TTransactionCheckpoint.Load(Request.DeploymentPath);
      if ParamStr(3) = 'stopped' then
      begin
        // Orçamento permite observar a recusa TCP local antes do timeout global.
        Request.TrackingMs := 8000;
        Result := RunWorker(Request);
        Check('stopped_node_reports_client_error', Result.ErrorText <> '');
        Check('stopped_node_not_confirmed', Result.State = 'unknown');
        Check('stopped_node_preserves_original_hash', Result.TransactionHash = OriginalCheckpoint.Hash);
        Check('stopped_node_no_lookup_success', not Result.HasLookup);
        Path := 'stopped-ui.json';
      end
      else if ParamStr(3) = 'check-ui' then
      begin
        Document := TJSONObject.ParseJSONValue(TFile.ReadAllText(
          TPath.Combine(OutputDirectory, 'acceptance.json'), TEncoding.UTF8));
        try
          OriginalNonce := TJSONObject(Document).GetValue<string>('nonceBeforeUi');
          Check('ui_tracking_no_additional_send', Nonce = OriginalNonce);
        finally Document.Free; end;
        Result := TRegistryWorkflow.Execute(Request);
        Check('reopened_tracking_keeps_hash', Result.TransactionHash = OriginalCheckpoint.Hash);
        Check('reopened_tracking_still_pending', Result.State = 'pending');
        Path := 'resume-check.json';
      end
      else raise EArgumentException.Create('Unknown acceptance mode.');
      Summary := TJSONObject.Create;
      try
        Summary.AddPair('passed', TJSONBool.Create(True));
        Summary.AddPair('checks', Checks.Clone as TJSONValue);
        TFile.WriteAllText(TPath.Combine(OutputDirectory, Path), Summary.ToJSON, TEncoding.UTF8);
      finally Summary.Free; end;
      Exit;
    end;

    Request.Action := raHash;
    Request.Port := 0;
    Result := TRegistryWorkflow.Execute(Request);
    Check('hash_without_network_configuration', Result.DocumentHash = Sha256File(Request.DocumentPath));
    Check('hash_is_not_signed_submission', (Result.State = 'hashed') and (Result.TransactionHash = ''));
    Request.Port := Port;
    Request.Action := raDeploy;
    Original := TRegistryWorkflow.Execute(Request);
    Check('deployment_submitted_with_checkpoint', (Original.State = 'submitted') and (Original.TransactionHash <> ''));
    OriginalHash := Original.TransactionHash;
    Request.Action := raRegister;
    ExpectArgumentError('registration_requires_confirmed_deployment');
    Check('no_registration_checkpoint_before_deployment', not TFile.Exists(Request.CheckpointPath));
    Request.Action := raTrackDeployment;
    Result := TRegistryWorkflow.Execute(Request);
    Check('pending_is_not_rejection', (Result.State = 'pending') and (Result.TransactionHash = OriginalHash));
    Mine;
    Result := TRegistryWorkflow.Execute(Request);
    Check('deployment_confirmed', (Result.State = 'succeeded') and (Result.ContractAddress <> ''));
    OriginalNonce := Nonce;
    Request.Action := raDeploy;
    ExpectArgumentError('existing_deployment_checkpoint_not_overwritten');
    Check('refused_checkpoint_does_not_send', Nonce = OriginalNonce);
    Request.Action := raTrackRegistration;
    Request.CheckpointPath := Request.DeploymentPath;
    ExpectArgumentError('wrong_checkpoint_kind_rejected');
    Request.CheckpointPath := TPath.Combine(OutputDirectory, 'registration.json');
    Request.Action := raRegister;
    Original := TRegistryWorkflow.Execute(Request);
    Check('registration_submitted', Original.State = 'submitted');
    Request.Action := raVerify;
    Result := TRegistryWorkflow.Execute(Request);
    Check('before_inclusion_not_found_at_latest', Result.HasLookup and not Result.Found);
    Request.Action := raTrackRegistration;
    Result := TRegistryWorkflow.Execute(Request);
    Check('registration_pending', Result.State = 'pending');
    Mine;
    Original := TRegistryWorkflow.Execute(Request);
    Check('registration_receipt_success', (Original.State = 'succeeded') and (Original.BlockNumber <> ''));
    OriginalNonce := Nonce;
    OriginalText := TFile.ReadAllText(Request.CheckpointPath, TEncoding.UTF8);
    Request.Action := raVerify;
    Result := TRegistryWorkflow.Execute(Request);
    Check('registered_file_found', Result.HasLookup and Result.Found and Result.MatchesDocument);
    Check('query_block_matches_receipt', Result.BlockNumber = Original.BlockNumber);
    CopyPath := TPath.Combine(OutputDirectory, 'copy with spaces.txt');
    ChangedPath := TPath.Combine(OutputDirectory, 'changed with spaces.txt');
    TFile.Copy(Request.DocumentPath, CopyPath);
    TFile.Copy('fixtures\p02\document-b.txt', ChangedPath);
    Request.DocumentPath := CopyPath;
    Result := TRegistryWorkflow.Execute(Request);
    Check('copy_with_spaces_found', Result.Found and Result.MatchesDocument);
    Request.DocumentPath := ChangedPath;
    Result := TRegistryWorkflow.Execute(Request);
    Check('changed_file_not_found', Result.HasLookup and not Result.Found and not Result.MatchesDocument);
    Check('queries_do_not_change_checkpoint', TFile.ReadAllText(Request.CheckpointPath, TEncoding.UTF8) = OriginalText);
    Check('queries_do_not_send_transactions', Nonce = OriginalNonce);
    Request.DocumentPath := 'fixtures\p02\document-a.txt';
    Request.CheckpointPath := TPath.Combine(OutputDirectory, 'duplicate.json');
    Request.Action := raRegister;
    Duplicate := TRegistryWorkflow.Execute(Request);
    Check('duplicate_is_distinct_submission', Duplicate.TransactionHash <> Original.TransactionHash);
    Mine;
    Request.Action := raTrackRegistration;
    Duplicate := TRegistryWorkflow.Execute(Request);
    Check('duplicate_reverted_not_success', Duplicate.State = 'reverted');
    Request.Action := raVerify;
    Request.CheckpointPath := TPath.Combine(OutputDirectory, 'registration.json');
    Result := TRegistryWorkflow.Execute(Request);
    Check('duplicate_preserves_first_registration', Result.Found and (Result.BlockNumber = Original.BlockNumber));
    OriginalNonce := Nonce;
    Request.Action := raRegister;
    Request.CheckpointPath := TPath.Combine(OutputDirectory, 'missing-file.json');
    Request.DocumentPath := TPath.Combine(OutputDirectory, 'absent.txt');
    Result := RunWorker(Request);
    Check('worker_reports_missing_file', Result.ErrorText <> '');
    Check('missing_file_does_not_sign_or_send', not TFile.Exists(Request.CheckpointPath) and (Nonce = OriginalNonce));
    Request.Action := raTrackDeployment;
    Inc(Request.Port);
    ExpectArgumentError('other_port_checkpoint_rejected');
    Request.Port := Port;
    Path := TPath.Combine(OutputDirectory, 'corrupt.json');
    TFile.WriteAllText(Path, '{}', TEncoding.UTF8);
    Request.DeploymentPath := Path;
    ExpectArgumentError('corrupt_checkpoint_rejected');
    Request.Action := raDeploy;
    Request.DeploymentPath := TPath.Combine(OutputDirectory, 'deployment-ui.json');
    Result := TRegistryWorkflow.Execute(Request);
    Check('ui_pending_fixture_submitted', Result.State = 'submitted');
    Summary := TJSONObject.Create;
    try
      Summary.AddPair('passed', TJSONBool.Create(True));
      Summary.AddPair('checksCount', TJSONNumber.Create(Checks.Count));
      Summary.AddPair('checks', Checks.Clone as TJSONValue);
      Summary.AddPair('port', TJSONNumber.Create(Port));
      Summary.AddPair('nonceBeforeUi', Nonce);
      Summary.AddPair('pendingDeploymentPath', Request.DeploymentPath);
      Summary.AddPair('pendingDeploymentHash', Result.TransactionHash);
      TFile.WriteAllText(TPath.Combine(OutputDirectory, 'acceptance.json'), Summary.ToJSON, TEncoding.UTF8);
    finally Summary.Free; end;
  finally Checks.Free; end;
end;

begin
  try Run;
  except on Error: Exception do
    begin Writeln(Error.ClassName, ': ', Error.Message); ExitCode := 1; end;
  end;
end.
