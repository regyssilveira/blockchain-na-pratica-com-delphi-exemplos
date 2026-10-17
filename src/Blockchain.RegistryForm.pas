unit Blockchain.RegistryForm;

interface

uses System.SysUtils, System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Controls, Vcl.Dialogs, Blockchain.RegistryWorkflow;

type
  TRegistryForm = class(TForm)
  private
    FDocument, FDeployment, FCheckpoint: TEdit;
    FHeader: TPanel;
    FControlsDisabled, FUpdatedOnMainThread: Boolean;
    FStatus, FActivity: TLabel;
    FDetails: TMemo;
    FControls: TList;
    FTimer: TTimer;
    FWorker: TRegistryWorker;
    FPort: Word;
    FArtifactPath: string;
    FBusyTicks, FCloseAttempts: Integer;
    FSelfTestDirectory: string;
    FSelfTestStarted: Boolean;
    FSelfTestClock: UInt64;
    FExpectedHash: string;
    function AddPath(const ACaption, AButtonCaption: string;
      const AHandler: TNotifyEvent; const ATop: Integer): TEdit;
    procedure AddAction(const APanel: TPanel; const ACaption: string;
      const AAction: TRegistryAction; const ALeft: Integer);
    procedure ChooseDocument(Sender: TObject);
    procedure ChooseDeployment(Sender: TObject);
    procedure ChooseCheckpoint(Sender: TObject);
    procedure ActionClick(Sender: TObject);
    procedure StartAction(const AAction: TRegistryAction);
    procedure SetBusy(const AValue: Boolean);
    procedure Tick(Sender: TObject);
    procedure QueryClose(Sender: TObject; var CanClose: Boolean);
    procedure Present(const AResult: TRegistryResult);
    procedure FinishSelfTest(const AResult: TRegistryResult);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Configure(const APort: Word; const ATestDirectory,
      ATestDeployment: string);
  end;

implementation

uses System.JSON, System.IOUtils, Winapi.Windows, Winapi.Messages,
  Blockchain.TransactionJournal;

function StateText(const AState: string): string;
begin
  if AState = 'hashed' then Exit('Hash calculado localmente; nenhum registro enviado.');
  if AState = 'prepared' then Exit('Preparado e assinado; envio ainda não confirmado.');
  if AState = 'submitted' then Exit('Enviado ao nó; inclusão ainda não confirmada.');
  if AState = 'pending' then Exit('Sem recibo; preserve o acompanhamento e consulte novamente.');
  if AState = 'succeeded' then Exit('Execução incluída com sucesso no laboratório.');
  if AState = 'reverted' then Exit('Execução incluída e revertida; o registro não foi efetuado.');
  if AState = 'rejected' then Exit('O nó declarou rejeição do envio.');
  Result := 'Resultado desconhecido; consulte o hash original antes de outro envio.';
end;

constructor TRegistryForm.Create(AOwner: TComponent);
var Panel: TPanel;
begin
  inherited CreateNew(AOwner);
  // CreateNew não transfere a marcação de formulário principal de TApplication.
  ShowInTaskBar := True;
  Caption := 'Registro de documentos — Delphi nativo / Anvil local';
  Width := 1040;
  Height := 690;
  Position := poScreenCenter;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 620;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  FControls := TList.Create;
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Height := 282;
  FHeader.BevelOuter := bvNone;
  OnCloseQuery := QueryClose;
  FDetails := TMemo.Create(Self);
  FDetails.Parent := Self;
  FDetails.Align := alClient;
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssBoth;
  FDetails.WordWrap := False;
  FDetails.Font.Name := 'Consolas';
  FDetails.Font.Size := 10;
  FActivity := TLabel.Create(Self);
  FActivity.Parent := Self;
  FActivity.Align := alBottom;
  FActivity.AutoSize := False;
  FActivity.Height := 32;
  FActivity.Caption := 'Somente rede local 31337. Chave publicada de teste; sem valores reais.';
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.AutoSize := False;
  FStatus.Height := 64;
  FStatus.WordWrap := True;
  FStatus.Caption := 'Selecione um arquivo e uma implantação confirmada, ou faça uma nova implantação.';
  Panel := TPanel.Create(Self);
  Panel.Parent := FHeader;
  Panel.SetBounds(0, 234, FHeader.Width, 48);
  Panel.Anchors := [akLeft, akTop, akRight];
  AddAction(Panel, 'Registrar arquivo', raRegister, 8);
  AddAction(Panel, 'Acompanhar registro', raTrackRegistration, 205);
  AddAction(Panel, 'Verificar arquivo', raVerify, 402);
  Panel := TPanel.Create(Self);
  Panel.Parent := FHeader;
  Panel.SetBounds(0, 186, FHeader.Width, 48);
  Panel.Anchors := [akLeft, akTop, akRight];
  AddAction(Panel, 'Calcular hash', raHash, 8);
  AddAction(Panel, 'Implantar contrato', raDeploy, 205);
  AddAction(Panel, 'Acompanhar implantação', raTrackDeployment, 402);
  FCheckpoint := AddPath('Acompanhamento do registro', 'Abrir registro', ChooseCheckpoint, 124);
  FDeployment := AddPath('Acompanhamento da implantação', 'Abrir implantação', ChooseDeployment, 62);
  FDocument := AddPath('Arquivo a registrar ou verificar', 'Selecionar arquivo', ChooseDocument, 0);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

function TRegistryForm.AddPath(const ACaption, AButtonCaption: string;
  const AHandler: TNotifyEvent; const ATop: Integer): TEdit;
var Panel: TPanel; LabelControl: TLabel; Button: TButton;
begin
  Panel := TPanel.Create(Self);
  Panel.Parent := FHeader;
  Panel.SetBounds(0, ATop, FHeader.Width, 62);
  Panel.Anchors := [akLeft, akTop, akRight];
  Panel.Padding.SetBounds(8, 4, 8, 4);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Panel;
  LabelControl.Align := alTop;
  LabelControl.Caption := ACaption;
  Button := TButton.Create(Self);
  Button.Parent := Panel;
  Button.Align := alRight;
  Button.Width := 170;
  Button.Caption := AButtonCaption;
  Button.OnClick := AHandler;
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Align := alClient;
  Result.ReadOnly := True;
  FControls.Add(Button);
end;

procedure TRegistryForm.AddAction(const APanel: TPanel; const ACaption: string;
  const AAction: TRegistryAction; const ALeft: Integer);
var Button: TButton;
begin
  Button := TButton.Create(Self);
  Button.Parent := APanel;
  Button.SetBounds(ALeft, 7, 190, 34);
  Button.Caption := ACaption;
  Button.Tag := Ord(AAction);
  Button.OnClick := ActionClick;
  FControls.Add(Button);
end;

procedure TRegistryForm.Configure(const APort: Word; const ATestDirectory,
  ATestDeployment: string);
begin
  if APort = 0 then raise EArgumentException.Create('Porta inválida.');
  FPort := APort;
  FArtifactPath := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\contract\DocumentRegistry.json'));
  FSelfTestDirectory := ATestDirectory;
  FDeployment.Text := ATestDeployment;
  if ATestDirectory <> '' then
  begin
    FExpectedHash := TTransactionCheckpoint.Load(ATestDeployment).Hash;
    FSelfTestClock := GetTickCount64;

  end;
  Caption := Caption + ' — porta ' + IntToStr(FPort);
end;

procedure TRegistryForm.ChooseDocument(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing, ofNoChangeDir];
    Dialog.Title := 'Selecione uma cópia de teste; o arquivo permanece local';
    if Dialog.Execute then FDocument.Text := Dialog.FileName;
  finally Dialog.Free; end;
end;

procedure TRegistryForm.ChooseDeployment(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'Acompanhamento JSON|*.json';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing, ofNoChangeDir];
    if Dialog.Execute then FDeployment.Text := Dialog.FileName;
  finally Dialog.Free; end;
end;

procedure TRegistryForm.ChooseCheckpoint(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'Acompanhamento JSON|*.json';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing, ofNoChangeDir];
    if Dialog.Execute then FCheckpoint.Text := Dialog.FileName;
  finally Dialog.Free; end;
end;

procedure TRegistryForm.ActionClick(Sender: TObject);
var Action: TRegistryAction; Dialog: TSaveDialog;
begin
  Action := TRegistryAction(TButton(Sender).Tag);
  if Action in [raDeploy, raRegister] then
  begin
    Dialog := TSaveDialog.Create(Self);
    try
      Dialog.Filter := 'Novo acompanhamento JSON|*.json';
      Dialog.DefaultExt := 'json';
      Dialog.Title := 'Escolha um arquivo novo para esta operação';
      Dialog.Options := [ofPathMustExist, ofEnableSizing, ofNoChangeDir];
      if not Dialog.Execute then Exit;
      if FileExists(Dialog.FileName) then
      begin
        FStatus.Caption := 'O arquivo já existe. Abra-o para acompanhar ou escolha outro nome.';
        Exit;
      end;
      if Action = raDeploy then FDeployment.Text := Dialog.FileName
      else FCheckpoint.Text := Dialog.FileName;
    finally Dialog.Free; end;
  end;
  StartAction(Action);
end;

procedure TRegistryForm.StartAction(const AAction: TRegistryAction);
var Request: TRegistryRequest;
begin
  if Assigned(FWorker) then Exit;
  Request := Default(TRegistryRequest);
  Request.Action := AAction;
  Request.Port := FPort;
  Request.ArtifactPath := FArtifactPath;
  Request.DocumentPath := FDocument.Text;
  Request.DeploymentPath := FDeployment.Text;
  Request.CheckpointPath := FCheckpoint.Text;
  Request.TrackingMs := 3000;
  FWorker := TRegistryWorker.Create(Request);
  SetBusy(True);
  try
    FWorker.Start;
  except
    FWorker.Free;
    FWorker := nil;
    SetBusy(False);
    raise;
  end;
end;

procedure TRegistryForm.SetBusy(const AValue: Boolean);
var Index: Integer;
begin
  for Index := 0 to FControls.Count - 1 do
    TControl(FControls[Index]).Enabled := not AValue;
  if AValue then
  begin
    FBusyTicks := 0;
    FStatus.Caption := 'Operação em andamento. Nenhum reenvio automático será feito.';
  end
  else FActivity.Caption := 'Pronto. Consultas e acompanhamento não reenviam a transação.';
end;

procedure TRegistryForm.QueryClose(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not Assigned(FWorker);
  if not CanClose then
  begin
    Inc(FCloseAttempts);
    FStatus.Caption := 'Aguarde esta operação terminar para fechar. O acompanhamento será preservado.';
  end;
end;

procedure TRegistryForm.Present(const AResult: TRegistryResult);
begin
  FUpdatedOnMainThread := GetCurrentThreadId = MainThreadID;
  FStatus.Caption := StateText(AResult.State);
  if AResult.HasLookup then
  begin
    if AResult.Found then FStatus.Caption := 'Hash encontrado para a conta e o contrato consultados.'
    else FStatus.Caption := 'Hash não encontrado para a conta e o contrato consultados.';
  end;
  if AResult.ErrorText <> '' then
  begin
    if AResult.TransactionHash = '' then FStatus.Caption := 'Falha no cliente; confira os dados e o diagnóstico.'
    else FStatus.Caption := 'Falha no cliente. ' + FStatus.Caption;
  end;
  FDetails.Lines.BeginUpdate;
  try
    FDetails.Clear;
    FDetails.Lines.Add('Estado apresentado: ' + AResult.State);
    FDetails.Lines.Add('Estado preservado no arquivo: ' + AResult.StoredState);
    FDetails.Lines.Add('Hash da transação: ' + AResult.TransactionHash);
    FDetails.Lines.Add('SHA-256 do arquivo: ' + AResult.DocumentHash);
    FDetails.Lines.Add('Contrato: ' + AResult.ContractAddress);
    FDetails.Lines.Add('Conta: ' + AResult.Account);
    FDetails.Lines.Add('Bloco: ' + AResult.BlockNumber);
    if AResult.HasLookup then
    begin
      FDetails.Lines.Add('Encontrado: ' + BoolToStr(AResult.Found, True));
      FDetails.Lines.Add('Mesmo hash do acompanhamento: ' + BoolToStr(AResult.MatchesDocument, True));
    end;
    if AResult.Diagnostic <> '' then FDetails.Lines.Add('Acompanhamento: ' + AResult.Diagnostic);
    if AResult.ErrorText <> '' then FDetails.Lines.Add('Diagnóstico: ' + AResult.ErrorText);
    FDetails.Lines.Add('O resultado não certifica identidade, autoria, veracidade ou finalidade pública.');
  finally FDetails.Lines.EndUpdate; end;
end;

procedure TRegistryForm.FinishSelfTest(const AResult: TRegistryResult);
var Document: TJSONObject; Passed, TaskbarWindow, ArtifactAvailable: Boolean;
begin
  TaskbarWindow := (GetWindowLong(Handle, GWL_EXSTYLE) and WS_EX_APPWINDOW <> 0) and
    (GetWindow(Handle, GW_OWNER) = 0);
  ArtifactAvailable := FileExists(FArtifactPath);
  Passed := (AResult.ErrorText = '') and (AResult.State = 'pending') and
    (AResult.TransactionHash = FExpectedHash) and (FBusyTicks >= 20) and
    (FCloseAttempts > 0) and not Assigned(FWorker) and
    FControlsDisabled and FUpdatedOnMainThread and (FDetails.Lines.Count > 5) and
    TaskbarWindow and ArtifactAvailable;
  Document := TJSONObject.Create;
  try
    Document.AddPair('passed', TJSONBool.Create(Passed));
    Document.AddPair('unownedTaskbarWindow', TJSONBool.Create(TaskbarWindow));
    Document.AddPair('contractArtifactAvailable', TJSONBool.Create(ArtifactAvailable));
    Document.AddPair('busyTimerTicks', TJSONNumber.Create(FBusyTicks));
    Document.AddPair('closeAttemptsDeferred', TJSONNumber.Create(FCloseAttempts));
    Document.AddPair('state', AResult.State);
    Document.AddPair('sameTransactionHash', TJSONBool.Create(AResult.TransactionHash = FExpectedHash));
    Document.AddPair('controlsDisabledWhileBusy', TJSONBool.Create(FControlsDisabled));
    Document.AddPair('updatedOnMainThread', TJSONBool.Create(FUpdatedOnMainThread));
    Document.AddPair('workerReleased', TJSONBool.Create(not Assigned(FWorker)));
    Document.AddPair('error', AResult.ErrorText);
    TDirectory.CreateDirectory(FSelfTestDirectory);
    TFile.WriteAllText(TPath.Combine(FSelfTestDirectory, 'ui-acceptance.json'), Document.ToJSON, TEncoding.UTF8);
  finally
    Document.Free;
  end;
  if not Passed then System.ExitCode := 1;
  Close;
end;

procedure TRegistryForm.Tick(Sender: TObject);
var Outcome: TRegistryResult; Index: Integer;
begin
  if Assigned(FWorker) then
  begin
    Inc(FBusyTicks);
    FActivity.Caption := 'Interface ativa durante a operação: ' + IntToStr(FBusyTicks);
    if (FSelfTestDirectory <> '') and (FBusyTicks = 3) then
    begin
      FControlsDisabled := True;
      for Index := 0 to FControls.Count - 1 do
        if TControl(FControls[Index]).Enabled then FControlsDisabled := False;
      PostMessage(Handle, WM_CLOSE, 0, 0);
    end;
    // O handle sinalizado garante que Execute terminou; nada acessa controles na thread.
    if WaitForSingleObject(FWorker.Handle, 0) = WAIT_OBJECT_0 then
    begin
      FWorker.WaitFor;
      Outcome := FWorker.Outcome;
      FWorker.Free;
      FWorker := nil;
      SetBusy(False);
      Present(Outcome);
      if FSelfTestDirectory <> '' then FinishSelfTest(Outcome);
    end;
  end
  else if (FSelfTestDirectory <> '') and not FSelfTestStarted then
  begin
    FSelfTestStarted := True;
    StartAction(raTrackDeployment);
  end;
  if (FSelfTestDirectory <> '') and (GetTickCount64 - FSelfTestClock > 15000) then
  begin
    System.ExitCode := 2;
    FStatus.Caption := 'Autoteste excedeu prazo; não encerrar thread à força.';
    if not Assigned(FWorker) then Close;
  end;
end;

destructor TRegistryForm.Destroy;
begin
  if Assigned(FTimer) then FTimer.Enabled := False;
  // OnCloseQuery impede destruir a janela durante uma operacao normal.
  if Assigned(FWorker) then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FControls.Free;
  inherited;
end;

end.
