unit Blockchain.LocalRpc;

interface

uses System.SysUtils, System.JSON, System.Net.HttpClient;

type
  ELocalRpcError = class(Exception);
  EJsonRpcError = class(ELocalRpcError);
  TLocalRpc = class
  private
    FClient: THTTPClient;
    FUrl: string;
    FId: Integer;
  public
    constructor Create(const APort: Word);
    destructor Destroy; override;
    // O chamador entrega AParameters e recebe a propriedade do resultado.
    function Call(const AMethod: string; AParameters: TJSONArray): TJSONValue;
  end;

implementation

uses System.Classes, System.Net.URLClient;

constructor TLocalRpc.Create(const APort: Word);
begin
  inherited Create;
  FUrl := 'http://127.0.0.1:' + IntToStr(APort);
  FClient := THTTPClient.Create;
  FClient.ConnectionTimeout := 3000;
  FClient.ResponseTimeout := 5000;
end;

destructor TLocalRpc.Destroy;
begin
  FClient.Free;
  inherited;
end;

function TLocalRpc.Call(const AMethod: string; AParameters: TJSONArray): TJSONValue;
var
  Request: TJSONObject;
  Document: TJSONValue;
  Response: IHTTPResponse;
  Body: TStringStream;
  Value: TJSONValue;
begin
  Inc(FId);
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', TJSONNumber.Create(FId));
    Request.AddPair('method', AMethod);
    Request.AddPair('params', AParameters);
    Body := TStringStream.Create(Request.ToJSON, TEncoding.UTF8);
    try
      Response := FClient.Post(FUrl, Body, nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]);
      if Response.StatusCode <> 200 then
        raise ELocalRpcError.CreateFmt('HTTP %d', [Response.StatusCode]);
      Document := TJSONObject.ParseJSONValue(Response.ContentAsString(TEncoding.UTF8));
      try
        if not (Document is TJSONObject) then raise ELocalRpcError.Create('Invalid JSON object.');
        if Document.GetValue<string>('jsonrpc', '') <> '2.0' then raise ELocalRpcError.Create('Invalid JSON-RPC version.');
        if Document.GetValue<Integer>('id', -1) <> FId then raise ELocalRpcError.Create('Mismatched response id.');
        Value := TJSONObject(Document).GetValue('error');
        if Assigned(Value) then
        begin
          if not (Value is TJSONObject) or
            not (TJSONObject(Value).GetValue('code') is TJSONNumber) or
            not (TJSONObject(Value).GetValue('message') is TJSONString) then
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
      Body.Free;
    end;
  finally
    Request.Free;
  end;
end;

end.
