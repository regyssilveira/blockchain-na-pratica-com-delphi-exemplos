unit Blockchain.LocalRpc;

interface

uses System.SysUtils, System.JSON, System.Net.HttpClient;

type
  ELocalRpcError = class(Exception);
  ELocalRpcTimeout = class(ELocalRpcError);
  EJsonRpcError = class(ELocalRpcError);
  TLocalRpc = class
  private
    FClient: THTTPClient;
    FUrl: string;
    FId: Integer;
  protected
    // Ponto de substituicao para duplos Delphi explicitamente simulados.
    function Exchange(const ABody: string; const ABudgetMs: Cardinal): string; virtual;
  public
    constructor Create(const APort: Word);
    destructor Destroy; override;
    // O chamador entrega AParameters e recebe a propriedade do resultado.
    function Call(const AMethod: string; AParameters: TJSONArray;
      const ABudgetMs: Cardinal = 8000): TJSONValue; virtual;
  end;

implementation

uses System.Classes, System.Net.URLClient, System.SyncObjs;

constructor TLocalRpc.Create(const APort: Word);
begin
  inherited Create;
  if APort = 0 then raise EArgumentException.Create('Port must be between 1 and 65535.');
  FUrl := 'http://127.0.0.1:' + IntToStr(APort);
  FClient := THTTPClient.Create;
  FClient.ConnectionTimeout := 3000;
  FClient.ResponseTimeout := 5000;
  FClient.SendTimeout := 3000;
  FClient.HandleRedirects := False;
end;

destructor TLocalRpc.Destroy;
begin
  FClient.Free;
  inherited;
end;

function TLocalRpc.Exchange(const ABody: string; const ABudgetMs: Cardinal): string;
var
  Response: IHTTPResponse;
  Body: TStringStream;
  HttpRequest: IHTTPRequest;
  Finished: TEvent;
  DeadlineThread: TThread;
  Expired: Integer;
begin
  Body := TStringStream.Create(ABody, TEncoding.UTF8);
  try
    HttpRequest := FClient.GetRequest('POST', FUrl);
    HttpRequest.SourceStream := Body;
    Finished := TEvent.Create(nil, True, False, '');
    Expired := 0;
    DeadlineThread := TThread.CreateAnonymousThread(
      procedure
      begin
        if Finished.WaitFor(ABudgetMs) = wrTimeout then
        begin
          TInterlocked.Exchange(Expired, 1);
          HttpRequest.Cancel;
        end;
      end);
    DeadlineThread.FreeOnTerminate := False;
    DeadlineThread.Start;
    try
      try
        Response := FClient.Execute(HttpRequest, nil,
          [TNameValuePair.Create('Content-Type', 'application/json')]);
      except
        on Error: Exception do
        begin
          if TInterlocked.CompareExchange(Expired, 0, 0) = 1 then
            raise ELocalRpcTimeout.Create('RPC total deadline expired; outcome may be unknown.');
          raise ELocalRpcError.Create('Transport failure: ' + Error.Message);
        end;
      end;
    finally
      Finished.SetEvent;
      DeadlineThread.WaitFor;
      DeadlineThread.Free;
      Finished.Free;
    end;
    if Expired = 1 then raise ELocalRpcTimeout.Create('RPC total deadline expired.');
    if Response.StatusCode <> 200 then
      raise ELocalRpcError.CreateFmt('HTTP %d', [Response.StatusCode]);
    Result := Response.ContentAsString(TEncoding.UTF8);
  finally Body.Free; end;
end;

function TLocalRpc.Call(const AMethod: string; AParameters: TJSONArray;
  const ABudgetMs: Cardinal): TJSONValue;
var
  Request: TJSONObject;
  Document: TJSONValue;
  Value: TJSONValue;
  Identifier, Version, ErrorValue: TJSONValue;
  ErrorCode: Integer;
begin
  if ABudgetMs = 0 then
  begin
    AParameters.Free;
    raise ELocalRpcTimeout.Create('RPC deadline expired.');
  end;
  Inc(FId);
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', TJSONNumber.Create(FId));
    Request.AddPair('method', AMethod);
    Request.AddPair('params', AParameters);
    Document := TJSONObject.ParseJSONValue(Exchange(Request.ToJSON, ABudgetMs));
    try
      if not (Document is TJSONObject) then raise ELocalRpcError.Create('Invalid JSON object.');
      Version := TJSONObject(Document).GetValue('jsonrpc');
      if not (Version is TJSONString) or (Version.Value <> '2.0') then
        raise ELocalRpcError.Create('Invalid JSON-RPC version.');
      Identifier := TJSONObject(Document).GetValue('id');
      if not (Identifier is TJSONNumber) or (Identifier.Value <> IntToStr(FId)) then
        raise ELocalRpcError.Create('Mismatched response id.');
      ErrorValue := TJSONObject(Document).GetValue('error');
      if Assigned(ErrorValue) and Assigned(TJSONObject(Document).GetValue('result')) then
        raise ELocalRpcError.Create('Response contains both result and error.');
      Value := TJSONObject(Document).GetValue('error');
      if Assigned(Value) then
      begin
        if not (Value is TJSONObject) or
          not (TJSONObject(Value).GetValue('code') is TJSONNumber) or
          not (TJSONObject(Value).GetValue('message') is TJSONString) or
          not TryStrToInt(TJSONObject(Value).GetValue('code').Value, ErrorCode) then
          raise ELocalRpcError.Create('Invalid JSON-RPC error.');
        raise EJsonRpcError.Create(Value.ToJSON);
      end;
      Value := TJSONObject(Document).GetValue('result');
      if not Assigned(Value) then raise ELocalRpcError.Create('Missing result.');
      Result := Value.Clone as TJSONValue;
    finally
      Document.Free;
    end;
  finally
    Request.Free;
  end;
end;

end.
