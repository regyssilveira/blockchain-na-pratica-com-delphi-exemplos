program Didactic.Scenario;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  System.Diagnostics, Winapi.Windows, Didactic.Codec, Didactic.Transaction,
  Didactic.Block, Didactic.Chain, Didactic.Http, Didactic.LabClient,
  Didactic.ProcessHarness in '..\tests\Didactic.ProcessHarness.pas', Blockchain.Primitives;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create('Scenario assertion: ' + AMessage);
end;

function SendTransaction(const APort: Word; const ATransaction: TDocumentTransaction;
  const AExpectedStatus: Integer = 200): TJSONObject;
var Document: TJSONObject;
begin
  Document := ATransaction.ToJson;
  try Result := LabObject(APort, 'POST', '/transactions', Document.ToJSON, AExpectedStatus);
  finally Document.Free; end;
end;

procedure WaitTransaction(const APort: Word; const ATransaction: TDocumentTransaction; const AState: string);
var Document: TJSONObject;
begin
  Document := WaitLabField(APort, '/transactions/' + ATransaction.Id, 'state', AState);
  Document.Free;
end;

function Mine(const APort: Word; const ATimestamp: UInt64): string;
var Document: TJSONObject;
begin
  Document := LabMine(APort, ATimestamp);
  try
    Check(Document.GetValue('found') is TJSONTrue, 'Mining must find proof within bounds');
    Result := JsonText(Document, 'hash');
  finally Document.Free; end;
end;

procedure WaitTip(const APort: Word; const AHash: string);
var Document: TJSONObject;
begin
  Document := WaitLabField(APort, '/status', 'hash', AHash);
  Document.Free;
end;

procedure WaitCounter(const APort: Word; const AField: string; const AMinimum: UInt64);
var Clock: TStopwatch; Document: TJSONObject;
begin
  Clock := TStopwatch.StartNew;
  repeat
    Document := LabStatus(APort);
    try if JsonUInt(Document, AField) >= AMinimum then Exit; finally Document.Free; end;
    TThread.Sleep(50);
  until Clock.ElapsedMilliseconds > 12000;
  raise Exception.Create('Counter did not advance: ' + AField);
end;

procedure CheckDocument(const APort: Word; const ATransaction: TDocumentTransaction;
  const AFound: Boolean; const AHeight: UInt64 = 0);
var Document: TJSONObject;
begin
  Document := LabObject(APort, 'GET', '/documents/' + ATransaction.Account + '/' + ATransaction.DocumentHash, '');
  try
    Check((Document.GetValue('found') is TJSONTrue) = AFound, 'Unexpected document existence');
    if AFound then
    begin
      Check(JsonUInt(Document, 'height') = AHeight, 'Document height differs');
      Check(JsonText(Document, 'transactionId') = ATransaction.Id, 'Document transaction id differs');
    end;
  finally Document.Free; end;
end;

function TextTransaction(const AText: string; const ASequence: UInt64; const AKey: Integer): TDocumentTransaction;
begin
  Result := TDocumentTransaction.Sign(TDidacticPolicy.Create, LabKey(AKey),
    Sha256Bytes(TEncoding.UTF8.GetBytes(AText)), ASequence);
end;

procedure Run;
var
  Root, Stamp, Tip, LeftTip, RightTip, FinalTip, BadPath, BeforeDisk: string;
  BasePort, Index: Integer;
  A, B, C, Foreign, Bad: TLabNodeProcess;
  First, Second, Pending, Left, Right, RightNext, Orphan, Line, Invalid: TDocumentTransaction;
  Policy: TDidacticPolicy;
  Document, Report, Event, Snapshot, Envelope: TJSONObject;
  Cases, Processes: TJSONArray;
  Value: TJSONValue;
  Block: TDidacticBlock;
  Mining: TMiningResult;
  Chain: TDidacticChain;
  RejectedBefore: UInt64;
  Started: TStopwatch;
  procedure Pass(const AId, ADescription, AObserved: string);
  begin
    Event := TJSONObject.Create;
    Event.AddPair('id', AId); Event.AddPair('description', ADescription);
    Event.AddPair('observed', AObserved); Event.AddPair('passed', TJSONBool.Create(True));
    Cases.AddElement(Event);
    Writeln(AId, ': ', ADescription);
  end;
  procedure RecordProcess(const AName: string; const ANode: TLabNodeProcess);
  begin
    Event := TJSONObject.Create;
    Event.AddPair('name', AName); Event.AddPair('pid', TJSONNumber.Create(ANode.ProcessId));
    Event.AddPair('port', IntToStr(ANode.Port)); Processes.AddElement(Event);
  end;
  procedure AllTips(const AHash: string);
  begin WaitTip(A.Port, AHash); WaitTip(B.Port, AHash); WaitTip(C.Port, AHash); end;
begin
  if (ParamCount < 2) or (ParamCount > 3) then raise Exception.Create('Usage: Didactic.Scenario outputDirectory basePort [lifecycle-probe]');
  Root := TPath.GetFullPath(ParamStr(1)); TDirectory.CreateDirectory(Root);
  Stamp := TPath.GetFileName(Root); if Length(Stamp) > 40 then Stamp := Copy(Stamp, 1, 40);
  BasePort := StrToInt(ParamStr(2));
  Check((BasePort > 1024) and (BasePort < 65532), 'Invalid port range');
  if ParamCount = 3 then
  begin
    Check(ParamStr(3) = 'lifecycle-probe', 'Unknown probe mode');
    A := TLabNodeProcess.Create(Root, 'probe-' + Stamp, BasePort, '-');
    try
      A.Start;
      Document := TJSONObject.Create;
      try
        Document.AddPair('childPid', TJSONNumber.Create(A.ProcessId));
        Document.AddPair('port', IntToStr(A.Port));
        SaveAtomicUtf8(TPath.Combine(Root, 'lifecycle-ready.json'), Document.ToJSON);
      finally Document.Free; end;
      // O roteiro encerra este processo de proposito e confere o encerramento do filho pelo Job Object.
      while True do TThread.Sleep(1000);
    finally A.Free; end;
  end;
  Policy := TDidacticPolicy.Create;
  A := TLabNodeProcess.Create(Root, 'A-' + Stamp, BasePort, IntToStr(BasePort + 1) + ',' + IntToStr(BasePort + 2));
  B := TLabNodeProcess.Create(Root, 'B-' + Stamp, BasePort + 1, IntToStr(BasePort) + ',' + IntToStr(BasePort + 2));
  C := TLabNodeProcess.Create(Root, 'C-' + Stamp, BasePort + 2, IntToStr(BasePort) + ',' + IntToStr(BasePort + 1));
  Foreign := nil; Bad := nil;
  Report := TJSONObject.Create; Cases := TJSONArray.Create; Processes := TJSONArray.Create;
  Report.AddPair('cases', Cases); Report.AddPair('processes', Processes);
  Started := TStopwatch.StartNew;
  try
    try
      A.Start; B.Start; C.Start;
      RecordProcess('A-initial', A); RecordProcess('B-initial', B); RecordProcess('C-initial', C);
      Tip := GenesisBlock(Policy).Hash; AllTips(Tip);
      Pass('N01', 'Three real Delphi nodes share fixed genesis', Tip);
      First := MakeDocumentTransaction('fixtures\p02\document-a.txt', 1, 1, Policy);
      Document := SendTransaction(A.Port, First);
      try Check(Document.GetValue('accepted') is TJSONTrue, 'First submission accepted'); finally Document.Free; end;
      WaitTransaction(B.Port, First, 'pending'); WaitTransaction(C.Port, First, 'pending');
      CheckDocument(C.Port, First, False);
      Pass('N02', 'Signed transaction propagates before inclusion', First.Id);
      Document := SendTransaction(B.Port, First);
      try Check(Document.GetValue('accepted') is TJSONFalse, 'Replay is idempotent'); finally Document.Free; end;
      for Index := 0 to 2 do
      begin
        Document := LabStatus(BasePort + Index);
        try Check(JsonUInt(Document, 'acceptedTransactions') = 1, 'Replay must not create another pending transaction');
        finally Document.Free; end;
      end;
      Pass('N03', 'Repeated message does not change pool or trigger a new transaction', 'one accepted transaction per node');
      Tip := Mine(A.Port, 1); AllTips(Tip);
      CheckDocument(A.Port, First, True, 1); CheckDocument(B.Port, First, True, 1); CheckDocument(C.Port, First, True, 1);
      Pass('N04', 'Mined block propagates and all nodes query identical record', Tip);

      Invalid := TextTransaction('valid-before-tampering', 2, 1);
      Invalid.DocumentHash := Sha256Bytes(TEncoding.UTF8.GetBytes('tampered-after-signing'));
      Document := SendTransaction(A.Port, Invalid, 400); Document.Free;
      Document := LabObject(A.Port, 'POST', '/transactions', '{', 400); Document.Free;
      Document := LabObject(A.Port, 'POST', '/transactions', '{"network":"bad","network":"bad"}', 400); Document.Free;
      WaitTip(A.Port, Tip);
      Document := LabStatus(A.Port);
      try Check(JsonUInt(Document, 'pending') = 0, 'Invalid input cannot enter pool'); finally Document.Free; end;
      Pass('N05', 'Actual node rejects bad signature, truncated JSON and duplicate fields', 'HTTP 400; head and pool unchanged');

      Block := Default(TDidacticBlock); Block.Height := 2; Block.Timestamp := 2;
      Block.Difficulty := 2; Block.PreviousHash := Tip;
      Block.Transactions := TArray<TDocumentTransaction>.Create(Invalid);
      Mining := MineBlock(Block, Policy);
      Check(Mining.Found, 'Adversarial block has genuine proof of work');
      Document := Block.ToJson;
      try Value := LabObject(A.Port, 'POST', '/blocks', Document.ToJSON, 400); Value.Free; finally Document.Free; end;
      WaitTip(A.Port, Tip);
      Pass('N06', 'Proof of work does not bypass signature validation', 'genuinely mined invalid block rejected');

      Second := MakeDocumentTransaction('fixtures\p02\document-b.txt', 2, 1, Policy);
      BeforeDisk := TFile.ReadAllText(A.DataFile, TEncoding.UTF8);
      Check(SetFileAttributes(PChar(A.DataFile), FILE_ATTRIBUTE_READONLY), 'Set test snapshot readonly');
      try Document := SendTransaction(A.Port, Second, 500); Document.Free;
      finally SetFileAttributes(PChar(A.DataFile), FILE_ATTRIBUTE_NORMAL); end;
      Check(BeforeDisk = TFile.ReadAllText(A.DataFile, TEncoding.UTF8), 'Old durable snapshot must survive failed save');
      Document := LabStatus(A.Port);
      try Check(JsonUInt(Document, 'pending') = 0, 'Failed persistence must roll back live state'); finally Document.Free; end;
      Pass('N07', 'Failed disk replacement does not acknowledge or retain mutation', 'HTTP 500; previous bytes and live pool preserved');

      // Particao controlada preserva um pendente so em B; depois B e realmente encerrado.
      Document := LabSwitch(B.Port, False); Document.Free;
      Pending := TextTransaction('pending-across-process-restart', 1, 2);
      Document := SendTransaction(B.Port, Pending); Document.Free;
      B.Stop;
      Check(B.ForcedStops = 0, 'B must stop gracefully');
      Document := SendTransaction(A.Port, Second); Document.Free;
      WaitTransaction(C.Port, Second, 'pending');
      Tip := Mine(C.Port, 2); WaitTip(A.Port, Tip);
      B.Start; RecordProcess('B-restarted-with-pending', B);
      Document := LabStatus(B.Port);
      try
        Check(JsonUInt(Document, 'bootHeight') = 1, 'B loaded previous confirmed chain');
        Check(JsonUInt(Document, 'bootPending') = 1, 'B loaded its durable pending transaction');
      finally Document.Free; end;
      AllTips(Tip);
      WaitTransaction(A.Port, Pending, 'pending'); WaitTransaction(C.Port, Pending, 'pending');
      Tip := Mine(B.Port, 3); AllTips(Tip);
      CheckDocument(A.Port, Pending, True, 3);
      Pass('N08', 'Stopped process restores pending data and catches up missed blocks', Tip);

      Document := LabSwitch(A.Port, False); Document.Free;
      Document := LabSwitch(B.Port, False); Document.Free;
      Document := LabSwitch(C.Port, False); Document.Free;
      Left := TextTransaction('fork-left', 1, 3);
      Orphan := TextTransaction('orphan-independent-account', 1, 4);
      Right := TextTransaction('fork-right', 1, 3);
      RightNext := TextTransaction('fork-right-next', 2, 3);
      Document := SendTransaction(A.Port, Left); Document.Free;
      Document := SendTransaction(A.Port, Orphan); Document.Free;
      LeftTip := Mine(A.Port, 4);
      Document := SendTransaction(B.Port, Right); Document.Free;
      RightTip := Mine(B.Port, 4);
      Check(LeftTip <> RightTip, 'Fork histories differ');
      Document := LabSwitch(A.Port, True); Document.Free;
      Document := LabSwitch(B.Port, True); Document.Free;
      WaitCounter(A.Port, 'equalForksObserved', 1); WaitCounter(B.Port, 'equalForksObserved', 1);
      WaitTip(A.Port, LeftTip); WaitTip(B.Port, RightTip);
      Pass('N09', 'Real processes retain different valid histories at equal work', LeftTip + ' / ' + RightTip);
      Document := SendTransaction(B.Port, RightNext); Document.Free;
      RightTip := Mine(B.Port, 5);
      WaitTip(A.Port, RightTip);
      WaitTransaction(A.Port, Left, 'absent');
      WaitTransaction(A.Port, Orphan, 'pending');
      CheckDocument(A.Port, Left, False); CheckDocument(A.Port, Right, True, 4);
      Document := LabSwitch(C.Port, True); Document.Free;
      AllTips(RightTip);
      WaitTransaction(B.Port, Orphan, 'pending'); WaitTransaction(C.Port, Orphan, 'pending');
      Tip := Mine(C.Port, 6); AllTips(Tip);
      CheckDocument(B.Port, Orphan, True, 6);
      Pass('N10', 'More work heals fork; conflicting sequence drops, valid orphan requeues', Tip);

      Foreign := TLabNodeProcess.Create(Root, 'D-' + Stamp, BasePort + 3, '-', 3);
      Foreign.Start; RecordProcess('D-foreign-policy', Foreign);
      Document := LabStatus(A.Port);
      try RejectedBefore := JsonUInt(Document, 'rejectedSnapshots'); finally Document.Free; end;
      Document := LabSync(A.Port, Foreign.Port); Document.Free;
      WaitCounter(A.Port, 'rejectedSnapshots', RejectedBefore + 1);
      WaitTip(A.Port, Tip);
      Foreign.Stop;
      Pass('N11', 'Foreign genesis/network snapshot is rejected by real node', 'd3 cannot replace d2');

      // Reiniciar todos com topologia em linha comprova encaminhamento por salto intermediario.
      A.Stop; B.Stop; C.Stop;
      A.SetPeers(IntToStr(B.Port)); B.SetPeers(IntToStr(A.Port) + ',' + IntToStr(C.Port)); C.SetPeers(IntToStr(B.Port));
      A.Start; B.Start; C.Start;
      RecordProcess('A-line-restart', A); RecordProcess('B-line-restart', B); RecordProcess('C-line-restart', C);
      AllTips(Tip);
      for Index := 0 to 2 do
      begin
        Document := LabStatus(BasePort + Index);
        try Check(JsonUInt(Document, 'bootHeight') = 6, 'All nodes reload validated chain'); finally Document.Free; end;
      end;
      Line := TextTransaction('multi-hop-after-full-restart', 3, 1);
      Document := SendTransaction(A.Port, Line); Document.Free;
      WaitTransaction(C.Port, Line, 'pending');
      FinalTip := Mine(A.Port, 7); AllTips(FinalTip);
      CheckDocument(C.Port, Line, True, 7);
      Pass('N12', 'Three restarted processes relay A to B to C without direct A-C edge', FinalTip);

      // Checksum externo correto nao mascara adulteracao do conteudo dos blocos.
      Envelope := TJSONObject.ParseJSONValue(TFile.ReadAllText(A.DataFile, TEncoding.UTF8)) as TJSONObject;
      try
        Snapshot := TJSONObject.ParseJSONValue(JsonText(Envelope, 'payload')) as TJSONObject;
        try
          Document := TJSONObject(Snapshot.GetValue<TJSONArray>('blocks').Items[1]);
          Document.RemovePair('hash').Free; Document.AddPair('hash', StringOfChar('f', 64));
          Envelope.RemovePair('payload').Free; Envelope.RemovePair('sha256').Free;
          Envelope.AddPair('payload', Snapshot.ToJSON);
          Envelope.AddPair('sha256', Sha256Bytes(TEncoding.UTF8.GetBytes(Snapshot.ToJSON)));
        finally Snapshot.Free; end;
        BadPath := TPath.Combine(Root, 'corrupt-copy.json');
        SaveAtomicUtf8(BadPath, Envelope.ToJSON);
      finally Envelope.Free; end;
      Bad := TLabNodeProcess.Create(Root, 'invalid-' + Stamp, BasePort + 3, '-');
      Bad.DataFile := BadPath;
      BeforeDisk := TFile.ReadAllText(BadPath, TEncoding.UTF8);
      Bad.Start(False);
      RecordProcess('corrupt-startup', Bad);
      Check(Bad.WaitExit(5000) = 1, 'Corrupt snapshot must stop startup, never reset silently');
      Bad.Stop;
      Check(BeforeDisk = TFile.ReadAllText(BadPath, TEncoding.UTF8), 'Corrupt input must remain available for diagnosis');
      Pass('N13', 'Corrupt storage stops native process startup without silent genesis reset', 'exit 1; corrupt copy preserved');

      A.Stop; B.Stop; C.Stop;
      Check((A.ForcedStops + B.ForcedStops + C.ForcedStops + Foreign.ForcedStops) = 0, 'All expected nodes stop gracefully');
      for Index := 0 to 2 do
      begin
        if Index = 0 then BadPath := A.DataFile else if Index = 1 then BadPath := B.DataFile else BadPath := C.DataFile;
        Chain := TDidacticChain.Load(BadPath, Policy);
        try
          Check(Chain.Tip.Hash = FinalTip, 'Durable final tips match');
          Check(Chain.BlockCount = 8, 'Seven confirmed blocks plus genesis');
          Check(Chain.TotalWork = 1792, 'Exact accumulated fixed-difficulty work');
          Check(Chain.PendingCount = 0, 'No stale pending transactions at completion');
          Check(Chain.Lookup(First.Account, First.DocumentHash).Exists, 'Original document preserved');
        finally Chain.Free; end;
      end;
      Pass('N14', 'All durable chains validate after shutdown and converge', FinalTip);
      Report.AddPair('passed', TJSONBool.Create(True));
      Report.AddPair('finalHash', FinalTip); Report.AddPair('finalHeight', '7'); Report.AddPair('work', '1792');
      Report.AddPair('normalForcedStops', '0');
    except
      on Error: Exception do
      begin Report.AddPair('passed', TJSONBool.Create(False)); Report.AddPair('error', Error.Message); raise; end;
    end;
  finally
    Bad.Free; Foreign.Free; C.Free; B.Free; A.Free;
    Report.AddPair('elapsedMs', IntToStr(Started.ElapsedMilliseconds));
    try SaveAtomicUtf8(TPath.Combine(Root, 'scenario.json'), Report.ToJSON); finally Report.Free; end;
  end;
end;

begin
  try Run; except on Error: Exception do begin Writeln(Error.ClassName, ': ', Error.Message); System.ExitCode := 1; end; end;
end.
