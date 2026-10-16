unit Didactic.NodeService;

interface

uses System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  System.Generics.Collections, Didactic.Codec, Didactic.Block, Didactic.Chain, Didactic.Http;

type
  TPeerMessageKind = (pmTransaction, pmBlock, pmSync);
  TPeerMessage = record
    Kind: TPeerMessageKind;
    Port: Word;
    Payload: string;
  end;
  TPeerSnapshot = record
    Port: Word;
    Payload: string;
  end;

  TDidacticPeerWorker = class(TThread)
  private
    FPort: Word;
    FEnabled: PInteger;
    FOutgoing: TThreadedQueue<TPeerMessage>;
    FIncoming: TThreadedQueue<TPeerSnapshot>;
    procedure Fetch(const APort: Word);
  protected
    procedure Execute; override;
  public
    Failures: Integer;
    Delivered: Integer;
    Dropped: Integer;
    constructor Create(const APort: Word; const AEnabled: PInteger;
      const AOutgoing: TThreadedQueue<TPeerMessage>; const AIncoming: TThreadedQueue<TPeerSnapshot>);
  end;

  TDidacticNode = class
  private
    FId, FStore: string;
    FPort: Word;
    FPeers: TArray<Word>;
    FChain: TDidacticChain;
    FPolicy: TDidacticPolicy;
    FServer: TDidacticHttpServer;
    FWorker: TDidacticPeerWorker;
    FOutgoing: TThreadedQueue<TPeerMessage>;
    FIncoming: TThreadedQueue<TPeerSnapshot>;
    FStopRequested: TEvent;
    FNetworkEnabled: Integer;
    FStarted: Boolean;
    FBootHeight, FBootPending: Integer;
    FAcceptedTransactions, FAcceptedBlocks, FSyncProcessed, FRejectedSnapshots, FEqualForks: Integer;
    FLastRejection: string;
    procedure Queue(const AKind: TPeerMessageKind; const APort: Word; const APayload: string);
    procedure Broadcast(const AKind: TPeerMessageKind; const APayload: string; const AExclude: Word);
    procedure Announce(const AExclude: Word);
    procedure Commit(var ACandidate: TDidacticChain);
    procedure Tick;
    function Handle(const AMethod, APath, ABody: string; const AFromPort: Word;
      out AStatus: Integer): TJSONObject;
  public
    constructor Create(const AId, AStore: string; const APort: Word;
      const APeers: TArray<Word>; const APolicy: TDidacticPolicy);
    destructor Destroy; override;
    procedure Start;
    procedure Run;
  end;

implementation

uses System.IOUtils, Didactic.Transaction;

constructor TDidacticPeerWorker.Create(const APort: Word; const AEnabled: PInteger;
  const AOutgoing: TThreadedQueue<TPeerMessage>; const AIncoming: TThreadedQueue<TPeerSnapshot>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPort := APort;
  FEnabled := AEnabled;
  FOutgoing := AOutgoing;
  FIncoming := AIncoming;
end;

procedure TDidacticPeerWorker.Fetch(const APort: Word);
var Response: TDidacticHttpResult; Snapshot: TPeerSnapshot;
begin
  Response := DidacticRequest(APort, 'GET', '/chain', '', FPort);
  if Response.Status <> 200 then raise EDidacticNetwork.Create('Peer did not return a snapshot.');
  Snapshot.Port := APort;
  Snapshot.Payload := Response.Body;
  if FIncoming.PushItem(Snapshot) <> wrSignaled then TInterlocked.Increment(Dropped);
end;

procedure TDidacticPeerWorker.Execute;
var Message: TPeerMessage; Response: TDidacticHttpResult; Path: string;
begin
  while not Terminated do
  begin
    if FOutgoing.PopItem(Message) <> wrSignaled then Continue;
    if Terminated then Break;
    if TInterlocked.CompareExchange(FEnabled^, 0, 0) = 0 then
    begin TInterlocked.Increment(Dropped); Continue; end;
    try
      if Message.Kind = pmSync then Fetch(Message.Port)
      else
      begin
        if Message.Kind = pmTransaction then Path := '/transactions' else Path := '/blocks';
        Response := DidacticRequest(Message.Port, 'POST', Path, Message.Payload, FPort);
        if (Response.Status = 409) and (Message.Kind = pmBlock) then Fetch(Message.Port)
        else if Response.Status <> 200 then raise EDidacticNetwork.Create('Peer rejected relayed data.');
      end;
      TInterlocked.Increment(Delivered);
    except on Error: Exception do TInterlocked.Increment(Failures); end;
    Message.Payload := '';
  end;
end;

constructor TDidacticNode.Create(const AId, AStore: string; const APort: Word;
  const APeers: TArray<Word>; const APolicy: TDidacticPolicy);
var Peer, Previous: Word; Index, Other: Integer;
begin
  inherited Create;
  if (APort = 0) or (AId = '') or (Length(AId) > 64) or (Length(APeers) > 8) then
    raise EDidacticValidation.Create('Invalid node configuration.');
  for Index := 0 to High(APeers) do
  begin
    Peer := APeers[Index];
    if (Peer = 0) or (Peer = APort) then raise EDidacticValidation.Create('Invalid peer port.');
    for Other := 0 to Index - 1 do
    begin
      Previous := APeers[Other];
      if Previous = Peer then raise EDidacticValidation.Create('Duplicate peer.');
    end;
  end;
  FId := AId;
  FStore := TPath.GetFullPath(AStore);
  FPort := APort;
  FPeers := Copy(APeers);
  FPolicy := TDidacticPolicy.Create(APolicy.Difficulty);
  FStopRequested := TEvent.Create(nil, True, False, '');
  FOutgoing := TThreadedQueue<TPeerMessage>.Create(256, 0, 50);
  FIncoming := TThreadedQueue<TPeerSnapshot>.Create(16, 0, 0);
  FNetworkEnabled := 1;
  if TFile.Exists(FStore) then FChain := TDidacticChain.Load(FStore, FPolicy)
  else
  begin
    FChain := TDidacticChain.Create(FPolicy);
    FChain.Save(FStore);
  end;
  FBootHeight := FChain.BlockCount - 1;
  FBootPending := FChain.PendingCount;
  FWorker := TDidacticPeerWorker.Create(FPort, @FNetworkEnabled, FOutgoing, FIncoming);
  FServer := TDidacticHttpServer.Create(FPort,
    function(const AMethod, APath, ABody: string; const AFromPort: Word; out AStatus: Integer): TJSONObject
    begin Result := Handle(AMethod, APath, ABody, AFromPort, AStatus); end,
    procedure begin Tick; end);
end;

destructor TDidacticNode.Destroy;
begin
  FServer.Free;
  if Assigned(FWorker) then
  begin
    FWorker.Terminate;
    // Destrutor de TThread encerra tambem o worker nao iniciado durante falha no construtor.
    FWorker.Free;
  end;
  FIncoming.Free;
  FOutgoing.Free;
  FStopRequested.Free;
  FChain.Free;
  inherited;
end;

procedure TDidacticNode.Start;
begin
  if FStarted then raise EDidacticValidation.Create('Node already started.');
  FStarted := True;
  // Apenas o servidor acessa a cadeia depois do inicio. Worker transporta copias de mensagens.
  Announce(0);
  FServer.Start;
  FWorker.Start;
end;

procedure TDidacticNode.Run;
begin
  while FStopRequested.WaitFor(100) <> wrSignaled do
    if FServer.Finished then raise EDidacticNetwork.Create('Node HTTP server stopped: ' + FServer.Failure);
end;

procedure TDidacticNode.Queue(const AKind: TPeerMessageKind; const APort: Word; const APayload: string);
var Message: TPeerMessage;
begin
  if TInterlocked.CompareExchange(FNetworkEnabled, 0, 0) = 0 then Exit;
  Message.Kind := AKind; Message.Port := APort; Message.Payload := APayload;
  if FOutgoing.PushItem(Message) <> wrSignaled then TInterlocked.Increment(FWorker.Dropped);
end;

procedure TDidacticNode.Broadcast(const AKind: TPeerMessageKind; const APayload: string; const AExclude: Word);
var Peer: Word;
begin
  for Peer in FPeers do if Peer <> AExclude then Queue(AKind, Peer, APayload);
end;

procedure TDidacticNode.Announce(const AExclude: Word);
var Peer: Word; Document: TJSONObject; Index: Integer;
begin
  if FChain.BlockCount > 1 then
  begin
    Document := FChain.Tip.ToJson;
    try Broadcast(pmBlock, Document.ToJSON, AExclude); finally Document.Free; end;
  end;
  for Index := 0 to FChain.PendingCount - 1 do
  begin
    Document := FChain.PendingAt(Index).ToJson;
    try Broadcast(pmTransaction, Document.ToJSON, 0); finally Document.Free; end;
  end;
  for Peer in FPeers do if Peer <> AExclude then Queue(pmSync, Peer, '');
end;

procedure TDidacticNode.Commit(var ACandidate: TDidacticChain);
var Previous: TDidacticChain;
begin
  ACandidate.Save(FStore);
  Previous := FChain;
  FChain := ACandidate;
  ACandidate := nil;
  Previous.Free;
end;

procedure TDidacticNode.Tick;
var Snapshot: TPeerSnapshot; Document: TJSONValue; Remote, Candidate: TDidacticChain;
begin
  if TInterlocked.CompareExchange(FNetworkEnabled, 0, 0) = 0 then Exit;
  // Uma aplicacao por ciclo evita que sincronizacao monopolize o atendimento HTTP.
  if FIncoming.PopItem(Snapshot) <> wrSignaled then Exit;
  Inc(FSyncProcessed);
  Document := nil; Remote := nil; Candidate := nil;
  try
    try
      Document := TJSONObject.ParseJSONValue(Snapshot.Payload);
      if not (Document is TJSONObject) then raise EDidacticValidation.Create('Peer snapshot must be object.');
      Remote := TDidacticChain.FromJson(TJSONObject(Document), FPolicy);
      if (Remote.TotalWork = FChain.TotalWork) and (Remote.Tip.Hash <> FChain.Tip.Hash) then Inc(FEqualForks);
      Candidate := FChain.Clone;
      if Candidate.Consider(Remote) then
      begin
        Commit(Candidate);
        Announce(Snapshot.Port);
      end;
    except
      on Error: Exception do
      begin Inc(FRejectedSnapshots); FLastRejection := Error.Message; end;
    end;
  finally Candidate.Free; Remote.Free; Document.Free; end;
end;

function TDidacticNode.Handle(const AMethod, APath, ABody: string;
  const AFromPort: Word; out AStatus: Integer): TJSONObject;
var
  Input: TJSONValue;
  Candidate: TDidacticChain;
  Transaction: TDocumentTransaction;
  Block: TDidacticBlock;
  Mining: TMiningResult;
  Entry: TDocumentEntry;
  Parts: TArray<string>;
  Values: TJSONArray;
  Peer: Word;
  Value, MaxAttempts, TimeoutMs: UInt64;
  Accepted: Boolean;
  Document: TJSONObject;
begin
  AStatus := 200;
  Result := TJSONObject.Create;
  Input := nil; Candidate := nil;
  try
    try
      if (AMethod = 'GET') and (APath = '/status') then
      begin
        Result.AddPair('nodeId', FId);
        Result.AddPair('network', FPolicy.NetworkId);
        Result.AddPair('genesis', FChain.BlockAt(0).Hash);
        Result.AddPair('hash', FChain.Tip.Hash);
        Result.AddPair('height', UIntToStr(FChain.Tip.Height));
        Result.AddPair('work', UIntToStr(FChain.TotalWork));
        Result.AddPair('pending', IntToStr(FChain.PendingCount));
        Result.AddPair('bootHeight', IntToStr(FBootHeight));
        Result.AddPair('bootPending', IntToStr(FBootPending));
        Result.AddPair('networkEnabled', TJSONBool.Create(FNetworkEnabled = 1));
        Result.AddPair('acceptedTransactions', IntToStr(FAcceptedTransactions));
        Result.AddPair('acceptedBlocks', IntToStr(FAcceptedBlocks));
        Result.AddPair('syncProcessed', IntToStr(FSyncProcessed));
        Result.AddPair('rejectedSnapshots', IntToStr(FRejectedSnapshots));
        Result.AddPair('equalForksObserved', IntToStr(FEqualForks));
        Result.AddPair('lastRejection', FLastRejection);
        Result.AddPair('peerFailures', IntToStr(TInterlocked.CompareExchange(FWorker.Failures, 0, 0)));
        Result.AddPair('peerDelivered', IntToStr(TInterlocked.CompareExchange(FWorker.Delivered, 0, 0)));
        Result.AddPair('peerDropped', IntToStr(TInterlocked.CompareExchange(FWorker.Dropped, 0, 0)));
        Values := TJSONArray.Create;
        for Peer in FPeers do Values.Add(IntToStr(Peer));
        Result.AddPair('peers', Values);
        Exit;
      end;
      if (AMethod = 'GET') and (APath = '/chain') then
      begin Result.Free; Result := FChain.ToJson; Exit; end;
      Parts := APath.Split(['/']);
      if (AMethod = 'GET') and (Length(Parts) = 4) and (Parts[1] = 'documents') then
      begin
        Entry := FChain.Lookup(Parts[2], Parts[3]);
        Result.AddPair('found', TJSONBool.Create(Entry.Exists));
        Result.AddPair('height', UIntToStr(Entry.BlockHeight));
        Result.AddPair('transactionId', Entry.TransactionId);
        Exit;
      end;
      if (AMethod = 'GET') and (Length(Parts) = 3) and (Parts[1] = 'transactions') then
      begin Result.AddPair('state', FChain.TransactionState(Parts[2])); Result.AddPair('id', Parts[2]); Exit; end;
      if AMethod <> 'POST' then
      begin AStatus := 404; Result.AddPair('error', 'Unknown endpoint.'); Exit; end;
      Input := TJSONObject.ParseJSONValue(ABody);
      if not (Input is TJSONObject) then raise EDidacticValidation.Create('JSON object required.');
      if APath = '/stop' then
      begin RequireFields(TJSONObject(Input), []); FStopRequested.SetEvent; Result.AddPair('stopping', TJSONBool.Create(True)); Exit; end;
      if APath = '/network' then
      begin
        RequireFields(TJSONObject(Input), ['enabled']);
        Value := JsonUInt(TJSONObject(Input), 'enabled');
        if Value > 1 then raise EDidacticValidation.Create('Network switch must be zero or one.');
        TInterlocked.Exchange(FNetworkEnabled, Value);
        if Value = 1 then Announce(0);
        Result.AddPair('enabled', TJSONBool.Create(Value = 1));
        Exit;
      end;
      if (FNetworkEnabled = 0) and ((AFromPort <> 0) or (APath = '/sync')) then
      begin AStatus := 503; Result.AddPair('error', 'Controlled network partition enabled.'); Exit; end;
      if APath = '/sync' then
      begin
        RequireFields(TJSONObject(Input), ['port']);
        Value := JsonUInt(TJSONObject(Input), 'port');
        if (Value = 0) or (Value > 65535) or (Value = FPort) then raise EDidacticValidation.Create('Invalid synchronization peer.');
        Queue(pmSync, Value, '');
        Result.AddPair('queued', TJSONBool.Create(True));
        Exit;
      end;
      if APath = '/transactions' then
      begin
        Transaction := TDocumentTransaction.FromJson(TJSONObject(Input));
        Candidate := FChain.Clone;
        Accepted := Candidate.Submit(Transaction);
        if Accepted then
        begin
          Commit(Candidate);
          Inc(FAcceptedTransactions);
          Broadcast(pmTransaction, Input.ToJSON, AFromPort);
        end;
        Result.AddPair('accepted', TJSONBool.Create(Accepted));
        Result.AddPair('id', Transaction.Id);
        Exit;
      end;
      if APath = '/blocks' then
      begin
        Block := TDidacticBlock.FromJson(TJSONObject(Input));
        Candidate := FChain.Clone;
        try Accepted := Candidate.AcceptBlock(Block); except
          on Error: ENeedDidacticSync do
          begin
            if AFromPort <> 0 then Queue(pmSync, AFromPort, '');
            AStatus := 409;
            Result.AddPair('error', Error.Message);
            Exit;
          end;
        end;
        if Accepted then
        begin Commit(Candidate); Inc(FAcceptedBlocks); Broadcast(pmBlock, Input.ToJSON, AFromPort); end;
        Result.AddPair('accepted', TJSONBool.Create(Accepted));
        Result.AddPair('hash', Block.Hash);
        Exit;
      end;
      if APath = '/mine' then
      begin
        RequireFields(TJSONObject(Input), ['timestamp','maxAttempts','timeoutMs']);
        MaxAttempts := JsonUInt(TJSONObject(Input), 'maxAttempts');
        TimeoutMs := JsonUInt(TJSONObject(Input), 'timeoutMs');
        if (MaxAttempts = 0) or (MaxAttempts > 10000000) or (TimeoutMs = 0) or (TimeoutMs > 10000) then
          raise EDidacticValidation.Create('Mining request exceeds laboratory bounds.');
        Candidate := FChain.Clone;
        Mining := Candidate.Mine(JsonUInt(TJSONObject(Input), 'timestamp'), MaxAttempts, TimeoutMs);
        if Mining.Found then
        begin
          Block := Candidate.Tip;
          Commit(Candidate);
          Document := Block.ToJson;
          try Broadcast(pmBlock, Document.ToJSON, 0); finally Document.Free; end;
        end;
        Result.AddPair('found', TJSONBool.Create(Mining.Found));
        Result.AddPair('attempts', UIntToStr(Mining.Attempts));
        Result.AddPair('elapsedMs', IntToStr(Mining.ElapsedMs));
        Result.AddPair('hash', FChain.Tip.Hash);
        Exit;
      end;
      AStatus := 404;
      Result.AddPair('error', 'Unknown endpoint.');
    except
      Result.Free;
      Result := nil;
      raise;
    end;
  finally Candidate.Free; Input.Free; end;
end;

end.
