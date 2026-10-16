unit Didactic.ProcessHarness;

interface

uses System.SysUtils, Winapi.Windows;

type
  TLabNodeProcess = class
  private
    FProcess: TProcessInformation;
    FJob: THandle;
    FReady: Boolean;
    FRoot, FExecutable, FId, FData, FPeers: string;
    FPort: Word;
    FDifficulty: Byte;
  public
    ForcedStops: Integer;
    constructor Create(const ARoot, AId: string; const APort: Word;
      const APeers: string; const ADifficulty: Byte = 2);
    destructor Destroy; override;
    procedure Start(const AExpectReady: Boolean = True);
    procedure Stop;
    function WaitExit(const ATimeoutMs: Cardinal): Cardinal;
    function Alive: Boolean;
    procedure SetPeers(const APeers: string);
    property Port: Word read FPort;
    property DataFile: string read FData write FData;
    property ProcessId: Cardinal read FProcess.dwProcessId;
  end;

implementation

uses System.IOUtils, System.Classes, System.Diagnostics, System.JSON,
  Didactic.Codec, Didactic.Http, Didactic.LabClient;

constructor TLabNodeProcess.Create(const ARoot, AId: string; const APort: Word;
  const APeers: string; const ADifficulty: Byte);
var Limits: TJobObjectExtendedLimitInformation;
begin
  inherited Create;
  FRoot := TPath.GetFullPath(ARoot);
  TDirectory.CreateDirectory(FRoot);
  FExecutable := TPath.Combine(GetCurrentDir, 'build\Didactic.Node\Didactic.Node.exe');
  FId := AId;
  FPort := APort;
  FData := TPath.Combine(FRoot, AId + '.json');
  FPeers := APeers;
  FDifficulty := ADifficulty;
  FJob := CreateJobObject(nil, nil);
  if FJob = 0 then RaiseLastOSError;
  FillChar(Limits, SizeOf(Limits), 0);
  Limits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if not SetInformationJobObject(FJob, JobObjectExtendedLimitInformation, @Limits, SizeOf(Limits)) then
    RaiseLastOSError;
end;

destructor TLabNodeProcess.Destroy;
begin
  Stop;
  if FJob <> 0 then CloseHandle(FJob);
  inherited;
end;

function TLabNodeProcess.Alive: Boolean;
var Code: Cardinal;
begin
  Result := (FProcess.hProcess <> 0) and GetExitCodeProcess(FProcess.hProcess, Code) and (Code = STILL_ACTIVE);
end;

function Quote(const AText: string): string;
begin
  if (Pos('"', AText) > 0) or (Pos(#0, AText) > 0) then raise EDidacticValidation.Create('Invalid process argument.');
  Result := '"' + AText + '"';
end;

procedure TLabNodeProcess.Start(const AExpectReady: Boolean);
var Info: TStartupInfo; Attributes: TSecurityAttributes; Log, NullInput: THandle;
  Command: string; Clock: TStopwatch; Status: TJSONObject;
begin
  if FProcess.hProcess <> 0 then raise EDidacticValidation.Create('Close previous node handle first.');
  FillChar(Info, SizeOf(Info), 0); Info.cb := SizeOf(Info);
  FillChar(Attributes, SizeOf(Attributes), 0); Attributes.nLength := SizeOf(Attributes); Attributes.bInheritHandle := True;
  Log := CreateFile(PChar(TPath.Combine(FRoot, FId + '-' + UIntToStr(GetTickCount64) + '.log')),
    GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if Log = INVALID_HANDLE_VALUE then RaiseLastOSError;
  NullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Attributes, OPEN_EXISTING, 0, 0);
  if NullInput = INVALID_HANDLE_VALUE then begin CloseHandle(Log); RaiseLastOSError; end;
  try
    Info.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Info.wShowWindow := SW_HIDE;
    Info.hStdInput := NullInput; Info.hStdOutput := Log; Info.hStdError := Log;
    Command := Quote(FExecutable) + ' ' + Quote(FId) + ' ' + UIntToStr(FPort) + ' ' + Quote(FData) +
      ' ' + Quote(FPeers) + ' ' + UIntToStr(FDifficulty);
    UniqueString(Command);
    if not CreateProcess(PChar(FExecutable), PChar(Command), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, PChar(GetCurrentDir), Info, FProcess) then RaiseLastOSError;
    if not AssignProcessToJobObject(FJob, FProcess.hProcess) then
    begin TerminateProcess(FProcess.hProcess, 99); RaiseLastOSError; end;
    if ResumeThread(FProcess.hThread) = Cardinal(-1) then RaiseLastOSError;
  finally CloseHandle(NullInput); CloseHandle(Log); end;
  FReady := False;
  if not AExpectReady then Exit;
  Clock := TStopwatch.StartNew;
  repeat
    if not Alive then raise EDidacticNetwork.Create('Node exited before readiness: ' + FId);
    try
      Status := LabStatus(FPort);
      try
        if JsonText(Status, 'nodeId') <> FId then raise EDidacticNetwork.Create('Port belongs to another node.');
        FReady := True;
        Exit;
      finally Status.Free; end;
    except on Error: EDidacticNetwork do begin end; end;
    TThread.Sleep(50);
  until Clock.ElapsedMilliseconds >= 8000;
  raise EDidacticNetwork.Create('Node readiness expired: ' + FId);
end;

function TLabNodeProcess.WaitExit(const ATimeoutMs: Cardinal): Cardinal;
begin
  if (FProcess.hProcess = 0) or (WaitForSingleObject(FProcess.hProcess, ATimeoutMs) <> WAIT_OBJECT_0) then
    raise EDidacticNetwork.Create('Node did not exit within deadline.');
  if not GetExitCodeProcess(FProcess.hProcess, Result) then RaiseLastOSError;
end;

procedure TLabNodeProcess.Stop;
var Response: TJSONObject;
begin
  if FProcess.hProcess = 0 then Exit;
  try
    if Alive and FReady then
      try
        Response := LabObject(FPort, 'POST', '/stop', '{}');
        Response.Free;
      except on Error: EDidacticNetwork do begin end; end;
    if Alive and (WaitForSingleObject(FProcess.hProcess, 5000) <> WAIT_OBJECT_0) then
    begin
      Inc(ForcedStops);
      TerminateProcess(FProcess.hProcess, 99);
      WaitForSingleObject(FProcess.hProcess, 2000);
    end;
  finally
    CloseHandle(FProcess.hThread);
    CloseHandle(FProcess.hProcess);
    FillChar(FProcess, SizeOf(FProcess), 0);
    FReady := False;
  end;
end;

procedure TLabNodeProcess.SetPeers(const APeers: string);
begin
  if Alive then raise EDidacticValidation.Create('Stop node before changing peers.');
  FPeers := APeers;
end;

end.
