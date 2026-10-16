unit Blockchain.HttpStub;

interface

uses System.Classes, System.SyncObjs, Winapi.WinSock2;

type
  // Servidor HTTP Delphi simulado. Nao representa comportamento de consenso de um no.
  TLocalHttpStub = class(TThread)
  private
    FListener: TSocket;
    FPort: Word;
    FStop: TEvent;
    FResponse: string;
    FDelayMs: Cardinal;
    FStatus: Integer;
    FRequests: Integer;
    FFailure: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AResponse: string; const ADelayMs: Cardinal = 0;
      const AStatus: Integer = 200);
    destructor Destroy; override;
    property Port: Word read FPort;
    property Requests: Integer read FRequests;
    property Failure: string read FFailure;
  end;

implementation

uses System.SysUtils, System.JSON;

constructor TLocalHttpStub.Create(const AResponse: string; const ADelayMs: Cardinal;
  const AStatus: Integer);
var Data: TWSAData; Address: TSockAddrIn; AddressSize: Integer;
begin
  // TThread inicia em AfterConstruction, depois que os campos do servidor estao prontos.
  inherited Create(False);
  FreeOnTerminate := False;
  FListener := INVALID_SOCKET;
  FStop := TEvent.Create(nil, True, False, '');
  FResponse := AResponse;
  FDelayMs := ADelayMs;
  FStatus := AStatus;
  if WSAStartup($0202, Data) <> 0 then raise Exception.Create('Stub WSAStartup failed.');
  FListener := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListener = INVALID_SOCKET then raise Exception.Create('Stub socket failed.');
  FillChar(Address, SizeOf(Address), 0);
  Address.sin_family := AF_INET;
  Address.sin_addr.S_addr := inet_addr('127.0.0.1');
  if bind(FListener, TSockAddr(Address), SizeOf(Address)) <> 0 then raise Exception.Create('Stub bind failed.');
  AddressSize := SizeOf(Address);
  if getsockname(FListener, TSockAddr(Address), AddressSize) <> 0 then raise Exception.Create('Stub getsockname failed.');
  FPort := ntohs(Address.sin_port);
  if listen(FListener, 4) <> 0 then raise Exception.Create('Stub listen failed.');
end;

destructor TLocalHttpStub.Destroy;
begin
  Terminate;
  FStop.SetEvent;
  closesocket(FListener);
  WaitFor;
  FStop.Free;
  WSACleanup;
  inherited;
end;

procedure TLocalHttpStub.Execute;
var
  Peer: TSocket;
  Buffer: TBytes;
  Count, HeaderEnd, BodyLength, HeaderIndex, Offset, Sent: Integer;
  RequestText, BodyText, ResponseText, IdText: string;
  Headers: TStringList;
  Bytes: TBytes;
  Request: TJSONValue;
  ReceiveTimeout: Integer;
begin
  SetLength(Buffer, 4096);
  try
    while not Terminated do
    begin
      Peer := accept(FListener, nil, nil);
      if Peer = INVALID_SOCKET then Break;
      try
        ReceiveTimeout := 1000;
        setsockopt(Peer, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@ReceiveTimeout), SizeOf(ReceiveTimeout));
        RequestText := '';
        HeaderEnd := 0;
        BodyLength := 0;
        repeat
          Count := recv(Peer, Buffer[0], Length(Buffer), 0);
          if Count <= 0 then Break;
          RequestText := RequestText + TEncoding.UTF8.GetString(Buffer, 0, Count);
          if Length(RequestText) > 65536 then raise Exception.Create('Stub request too large.');
          HeaderEnd := Pos(#13#10#13#10, RequestText);
          if HeaderEnd > 0 then
          begin
            Headers := TStringList.Create;
            try
              Headers.Text := Copy(RequestText, 1, HeaderEnd);
              for HeaderIndex := 0 to Headers.Count - 1 do
                if SameText(Copy(Headers[HeaderIndex], 1, 15), 'Content-Length:') then
                  BodyLength := StrToInt(Trim(Copy(Headers[HeaderIndex], 16, MaxInt)));
            finally Headers.Free; end;
          end;
        until (HeaderEnd > 0) and (Length(RequestText) >= HeaderEnd + 3 + BodyLength);
        if (HeaderEnd = 0) or Terminated then Continue;
        TInterlocked.Increment(FRequests);
        Request := TJSONObject.ParseJSONValue(Copy(RequestText, HeaderEnd + 4, BodyLength));
        try
          if not (Request is TJSONObject) then raise Exception.Create('Stub invalid request.');
          IdText := TJSONObject(Request).GetValue('id').ToJSON;
          if Request.GetValue<string>('method') = 'eth_chainId' then
            BodyText := '{"jsonrpc":"2.0","id":' + IdText + ',"result":"0x7a69"}'
          else
          begin
            if FStop.WaitFor(FDelayMs) = wrSignaled then Break;
            BodyText := StringReplace(FResponse, '$id', IdText, [rfReplaceAll]);
          end;
        finally Request.Free; end;
        Headers := TStringList.Create;
        try
          Headers.LineBreak := #13#10;
          Headers.Add(Format('HTTP/1.1 %d test', [FStatus]));
          Headers.Add('Content-Type: application/json');
          Headers.Add('Content-Length: ' + IntToStr(TEncoding.UTF8.GetByteCount(BodyText)));
          Headers.Add('Connection: close');
          Headers.Add('');
          ResponseText := Headers.Text + BodyText;
        finally Headers.Free; end;
        Bytes := TEncoding.UTF8.GetBytes(ResponseText);
        Offset := 0;
        while Offset < Length(Bytes) do
        begin
          Sent := send(Peer, Bytes[Offset], Length(Bytes) - Offset, 0);
          if Sent <= 0 then Break;
          Inc(Offset, Sent);
        end;
      finally closesocket(Peer); end;
    end;
  except
    on Error: Exception do if not Terminated then FFailure := Error.Message;
  end;
end;

end.
