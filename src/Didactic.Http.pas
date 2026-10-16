unit Didactic.Http;

interface

uses System.SysUtils, System.Classes, System.JSON, Winapi.WinSock2;

type
  EDidacticNetwork = class(Exception);
  TDidacticHttpResult = record
    Status: Integer;
    Body: string;
    function ObjectValue: TJSONObject;
  end;
  TDidacticHttpHandler = reference to function(const AMethod, APath, ABody: string;
    const AFromPort: Word; out AStatus: Integer): TJSONObject;

  TDidacticHttpServer = class(TThread)
  private
    FListener: TSocket;
    FPort: Word;
    FSocketStarted: Boolean;
    FHandler: TDidacticHttpHandler;
    FTick: TProc;
    FFailure: string;
    procedure Serve(const APeer: TSocket);
  protected
    procedure Execute; override;
  public
    constructor Create(const APort: Word; const AHandler: TDidacticHttpHandler; const ATick: TProc);
    destructor Destroy; override;
    procedure Stop;
    property Port: Word read FPort;
    property Failure: string read FFailure;
  end;

function DidacticRequest(const APort: Word; const AMethod, APath, ABody: string;
  const AFromPort: Word = 0; const ABudgetMs: Cardinal = 1500): TDidacticHttpResult;

implementation

uses System.Net.HttpClient, System.Net.URLClient, System.SyncObjs,
  Didactic.Codec;

function TDidacticHttpResult.ObjectValue: TJSONObject;
var Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Body);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise EDidacticNetwork.Create('HTTP response must contain a JSON object.');
  end;
  Result := TJSONObject(Value);
end;

function DidacticRequest(const APort: Word; const AMethod, APath, ABody: string;
  const AFromPort: Word; const ABudgetMs: Cardinal): TDidacticHttpResult;
var Client: THTTPClient; Request: IHTTPRequest; Response: IHTTPResponse;
  Source: TStringStream; Done: TEvent; Guard: TThread;
begin
  if (APort = 0) or (ABudgetMs = 0) or (Copy(APath, 1, 1) <> '/') then
    raise EDidacticNetwork.Create('Invalid local HTTP request.');
  Client := THTTPClient.Create;
  Source := TStringStream.Create(ABody, TEncoding.UTF8);
  Done := TEvent.Create(nil, True, False, '');
  try
    Client.ConnectionTimeout := 500;
    Client.SendTimeout := 1000;
    Client.ResponseTimeout := 1500;
    Client.HandleRedirects := False;
    Request := Client.GetRequest(AMethod, 'http://127.0.0.1:' + IntToStr(APort) + APath);
    if AMethod = 'POST' then Request.SourceStream := Source;
    Guard := TThread.CreateAnonymousThread(procedure begin
      if Done.WaitFor(ABudgetMs) = wrTimeout then Request.Cancel;
    end);
    Guard.FreeOnTerminate := False;
    Guard.Start;
    try
      try
        Response := Client.Execute(Request, nil,
          [TNameValuePair.Create('Content-Type', 'application/json'),
           TNameValuePair.Create('X-Didactic-Port', IntToStr(AFromPort))]);
        Result.Status := Response.StatusCode;
        Result.Body := Response.ContentAsString(TEncoding.UTF8);
        if TEncoding.UTF8.GetByteCount(Result.Body) > MaxSnapshotBytes then
          raise EDidacticNetwork.Create('HTTP response exceeds laboratory limit.');
      except
        on Error: Exception do raise EDidacticNetwork.Create('Local HTTP failure: ' + Error.Message);
      end;
    finally
      Done.SetEvent;
      Guard.WaitFor;
      Guard.Free;
    end;
  finally Done.Free; Source.Free; Client.Free; end;
end;

constructor TDidacticHttpServer.Create(const APort: Word;
  const AHandler: TDidacticHttpHandler; const ATick: TProc);
var Data: TWSAData; Address: TSockAddrIn; Size: Integer;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FListener := INVALID_SOCKET;
  FHandler := AHandler;
  FTick := ATick;
  if WSAStartup($0202, Data) <> 0 then raise EDidacticNetwork.Create('WSAStartup failed.');
  FSocketStarted := True;
  FListener := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListener = INVALID_SOCKET then raise EDidacticNetwork.Create('Socket creation failed.');
  FillChar(Address, SizeOf(Address), 0);
  Address.sin_family := AF_INET;
  Address.sin_addr.S_addr := inet_addr('127.0.0.1');
  Address.sin_port := htons(APort);
  if bind(FListener, TSockAddr(Address), SizeOf(Address)) <> 0 then
    raise EDidacticNetwork.Create('Loopback port unavailable.');
  Size := SizeOf(Address);
  if getsockname(FListener, TSockAddr(Address), Size) <> 0 then raise EDidacticNetwork.Create('Cannot inspect bound port.');
  FPort := ntohs(Address.sin_port);
  if listen(FListener, 16) <> 0 then raise EDidacticNetwork.Create('Listen failed.');
end;

procedure TDidacticHttpServer.Stop;
begin
  Terminate;
  if FListener <> INVALID_SOCKET then
  begin
    closesocket(FListener);
    FListener := INVALID_SOCKET;
  end;
end;

destructor TDidacticHttpServer.Destroy;
var Started: Boolean;
begin
  Started := FSocketStarted;
  Stop;
  // TThread tambem encerra com seguranca uma instancia ainda nao iniciada.
  inherited;
  if Started then WSACleanup;
end;

procedure TDidacticHttpServer.Serve(const APeer: TSocket);
var
  Received, Chunk, ResponseBytes: TBytes;
  Count, OldLength, HeaderEnd, ContentLength, HeaderIndex, Status, FromValue: Integer;
  LengthFields, Offset, Sent, Timeout: Integer;
  HeaderText, Body, ResponseText, Method, Path: string;
  Headers: TStringList;
  Parts: TArray<string>;
  Response: TJSONObject;
begin
  Timeout := 1500;
  setsockopt(APeer, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
  setsockopt(APeer, SOL_SOCKET, SO_SNDTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
  Response := nil;
  Status := 200;
  try
    try
      SetLength(Chunk, 4096);
      Received := nil;
      HeaderEnd := 0;
      ContentLength := 0;
      FromValue := 0;
      repeat
        Count := recv(APeer, Chunk[0], Length(Chunk), 0);
        if Count <= 0 then raise EDidacticValidation.Create('Incomplete HTTP request.');
        OldLength := Length(Received);
        SetLength(Received, OldLength + Count);
        Move(Chunk[0], Received[OldLength], Count);
        if Length(Received) > MaxSnapshotBytes + 8192 then raise EDidacticValidation.Create('Request too large.');
        if HeaderEnd = 0 then
        begin
          HeaderText := TEncoding.ASCII.GetString(Received);
          HeaderEnd := Pos(#13#10#13#10, HeaderText);
          if (HeaderEnd = 0) and (Length(Received) > 8192) then raise EDidacticValidation.Create('Headers too large.');
          if HeaderEnd > 0 then
          begin
            Headers := TStringList.Create;
            try
              Headers.Text := Copy(HeaderText, 1, HeaderEnd);
              Parts := Headers[0].Split([' ']);
              if Length(Parts) <> 3 then raise EDidacticValidation.Create('Invalid request line.');
              Method := Parts[0]; Path := Parts[1];
              if (Length(Path) > 1024) or (Parts[2] <> 'HTTP/1.1') then raise EDidacticValidation.Create('Unsupported HTTP request.');
              LengthFields := 0;
              for HeaderIndex := 1 to Headers.Count - 1 do
              begin
                if SameText(Copy(Headers[HeaderIndex], 1, 15), 'Content-Length:') then
                begin
                  Inc(LengthFields);
                  if not TryStrToInt(Trim(Copy(Headers[HeaderIndex], 16, MaxInt)), ContentLength) then
                    raise EDidacticValidation.Create('Invalid content length.');
                end;
                if SameText(Copy(Headers[HeaderIndex], 1, 16), 'X-Didactic-Port:') then
                  if not TryStrToInt(Trim(Copy(Headers[HeaderIndex], 17, MaxInt)), FromValue) then
                    raise EDidacticValidation.Create('Invalid sender port.');
                if SameText(Copy(Headers[HeaderIndex], 1, 18), 'Transfer-Encoding:') then
                  raise EDidacticValidation.Create('Chunked requests are outside this laboratory.');
              end;
              if (LengthFields > 1) or ((Method = 'POST') and (LengthFields <> 1)) or
                (ContentLength < 0) or (ContentLength > MaxSnapshotBytes) or
                (FromValue < 0) or (FromValue > 65535) then raise EDidacticValidation.Create('Invalid HTTP framing.');
            finally Headers.Free; end;
          end;
        end;
      until (HeaderEnd > 0) and (Length(Received) >= HeaderEnd + 3 + ContentLength);
      Body := TEncoding.UTF8.GetString(Received, HeaderEnd + 3, ContentLength);
      Response := FHandler(Method, Path, Body, FromValue, Status);
    except
      on Error: Exception do
      begin
        if Error is EDidacticValidation then Status := 400 else Status := 500;
        Response.Free;
        Response := TJSONObject.Create;
        Response.AddPair('error', Error.Message);
      end;
    end;
    if not Assigned(Response) then raise EDidacticNetwork.Create('Handler returned no response.');
    Body := Response.ToJSON;
    Headers := TStringList.Create;
    try
      Headers.LineBreak := #13#10;
      Headers.Add(Format('HTTP/1.1 %d lab', [Status]));
      Headers.Add('Content-Type: application/json; charset=utf-8');
      Headers.Add('Content-Length: ' + IntToStr(TEncoding.UTF8.GetByteCount(Body)));
      Headers.Add('Connection: close');
      Headers.Add('');
      ResponseText := Headers.Text + Body;
    finally Headers.Free; end;
    ResponseBytes := TEncoding.UTF8.GetBytes(ResponseText);
    Offset := 0;
    while Offset < Length(ResponseBytes) do
    begin
      Sent := send(APeer, ResponseBytes[Offset], Length(ResponseBytes) - Offset, 0);
      if Sent <= 0 then Break;
      Inc(Offset, Sent);
    end;
  finally Response.Free; end;
end;

procedure TDidacticHttpServer.Execute;
var ReadSet: TFDSet; Timeout: TTimeVal; Peer: TSocket; Ready: Integer;
begin
  try
    while not Terminated do
    begin
      if Assigned(FTick) then FTick();
      FillChar(ReadSet, SizeOf(ReadSet), 0);
      ReadSet.fd_count := 1;
      ReadSet.fd_array[0] := FListener;
      Timeout.tv_sec := 0; Timeout.tv_usec := 50000;
      Ready := Winapi.WinSock2.select(0, @ReadSet, nil, nil, @Timeout);
      if Ready = SOCKET_ERROR then Break;
      if Ready > 0 then
      begin
        Peer := accept(FListener, nil, nil);
        if Peer <> INVALID_SOCKET then
          try Serve(Peer); finally closesocket(Peer); end;
      end;
    end;
  except on Error: Exception do FFailure := Error.Message; end;
end;

end.
