program Chapter19.ReceiptLoss;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils,
  Blockchain.RegistryWorkflow, Blockchain.TransactionJournal, Blockchain.LocalRpc;

var Port: Word; Evidence: TJSONObject; Checks: TJSONArray;

function Call(const AMethod: string; AParameters: TJSONArray): TJSONValue;
var Rpc: TLocalRpc;
begin
  Rpc := TLocalRpc.Create(Port);
  try Result := Rpc.Call(AMethod, AParameters); finally Rpc.Free; end;
end;

procedure Mine;
var Value: TJSONValue;
begin Value := Call('evm_mine', TJSONArray.Create); Value.Free; end;

procedure Check(const AName: string; const ACondition: Boolean);
begin
  Checks.AddElement(TJSONObject.Create.AddPair('name', AName).AddPair('passed', TJSONBool.Create(ACondition)));
  if not ACondition then raise Exception.Create('Expected condition failed: ' + AName);
end;

function Nonce: string;
var Value: TJSONValue;
begin
  Value := Call('eth_getTransactionCount',
    TJSONArray.Create('0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f', 'pending'));
  try Result := Value.Value; finally Value.Free; end;
end;

procedure Run;
var
  Request: TRegistryRequest;
  First, Current: TRegistryResult;
  Checkpoint, Original: TTransactionCheckpoint;
  Snapshot, BeforeNonce, Folder: string;
  Value: TJSONValue;
  PortNumber: Integer;
begin
  if ParamCount <> 2 then raise EArgumentException.Create('Usage: Chapter19.ReceiptLoss port new-folder');
  PortNumber := StrToInt(ParamStr(1));
  if (PortNumber < 1024) or (PortNumber > 65535) then raise EArgumentException.Create('Invalid port.');
  Port := PortNumber;
  Folder := TPath.GetFullPath(ParamStr(2));
  TDirectory.CreateDirectory(Folder);
  Evidence := TJSONObject.Create;
  Checks := TJSONArray.Create;
  Evidence.AddPair('simulatedHistoryRollback', TJSONBool.Create(True));
  Evidence.AddPair('publicConsensusTested', TJSONBool.Create(False));
  Evidence.AddPair('checks', Checks);
  try
    Request := Default(TRegistryRequest);
    Request.Port := Port;
    Request.ArtifactPath := 'build\contract\DocumentRegistry.json';
    Request.DeploymentPath := TPath.Combine(Folder, 'deployment.json');
    Request.CheckpointPath := TPath.Combine(Folder, 'registration.json');
    Request.DocumentPath := 'fixtures\p02\document-a.txt';
    Request.TrackingMs := 500;
    Request.Action := raDeploy;
    TRegistryWorkflow.Execute(Request);
    Mine;
    Request.Action := raTrackDeployment;
    First := TRegistryWorkflow.Execute(Request);
    Check('deployment_succeeded', First.State = 'succeeded');
    Value := Call('evm_snapshot', TJSONArray.Create);
    try Snapshot := Value.Value; finally Value.Free; end;
    Request.Action := raRegister;
    TRegistryWorkflow.Execute(Request);
    Mine;
    Request.Action := raTrackRegistration;
    First := TRegistryWorkflow.Execute(Request);
    Check('registration_succeeded_before_rollback', First.State = 'succeeded');
    Original := TTransactionCheckpoint.Load(Request.CheckpointPath);
    Request.Action := raVerify;
    Current := TRegistryWorkflow.Execute(Request);
    Check('document_found_before_rollback', Current.HasLookup and Current.Found);
    Value := Call('evm_revert', TJSONArray.Create.Add(Snapshot));
    try Check('anvil_rollback_applied', Value is TJSONTrue); finally Value.Free; end;
    BeforeNonce := Nonce;
    Evidence.AddPair('nonceAfterRollback', BeforeNonce);
    Request.Action := raVerify;
    Current := TRegistryWorkflow.Execute(Request);
    Check('document_absent_after_rollback', Current.HasLookup and not Current.Found);
    Request.Action := raTrackRegistration;
    Current := TRegistryWorkflow.Execute(Request);
    Evidence.AddPair('presentedStateAfterLoss', Current.State);
    Evidence.AddPair('originalHashPreserved', TJSONBool.Create(Current.TransactionHash = Original.Hash));
    Checkpoint := TTransactionCheckpoint.Load(Request.CheckpointPath);
    Evidence.AddPair('storedStateAfterLoss', Checkpoint.State);
    Check('absent_receipt_not_presented_as_success', Current.State = 'unknown');
    Check('current_response_contains_no_receipt', not Current.ReceiptObserved);
    Check('stored_metadata_marked_as_historical', Current.StoredState = 'succeeded');
    Check('historical_observation_preserved', Checkpoint.State = 'succeeded');
    Check('same_signed_operation_preserved', (Checkpoint.Hash = Original.Hash) and (Checkpoint.RawHex = Original.RawHex));
    Check('tracking_did_not_resend', Nonce = BeforeNonce);
    Evidence.AddPair('passed', TJSONBool.Create(True));
  finally
    TFile.WriteAllText(TPath.Combine(Folder, 'receipt-loss.json'), Evidence.ToJSON, TEncoding.UTF8);
    Evidence.Free;
  end;
end;

begin
  try Run;
  except on Error: Exception do
    begin Writeln(Error.ClassName, ': ', Error.Message); ExitCode := 1; end;
  end;
end.
