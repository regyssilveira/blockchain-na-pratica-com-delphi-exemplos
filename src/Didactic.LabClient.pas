unit Didactic.LabClient;

interface

uses System.SysUtils, System.JSON, Didactic.Codec, Didactic.Transaction;

function LabKey(const AIndex: Integer): TBytes;
function MakeDocumentTransaction(const AFile: string; const ASequence: UInt64;
  const AKeyIndex: Integer; const APolicy: TDidacticPolicy): TDocumentTransaction;
function LabObject(const APort: Word; const AMethod, APath, ABody: string;
  const AExpectedStatus: Integer = 200; const ABudgetMs: Cardinal = 1500): TJSONObject;
function LabStatus(const APort: Word): TJSONObject;
function LabMine(const APort: Word; const ATimestamp: UInt64): TJSONObject;
function LabSwitch(const APort: Word; const AEnabled: Boolean): TJSONObject;
function LabSync(const APort, APeer: Word): TJSONObject;
function WaitLabField(const APort: Word; const APath, AField, AExpected: string;
  const ATimeoutMs: Cardinal = 10000): TJSONObject;

implementation

uses System.Diagnostics, System.Classes, System.Math, Didactic.Http,
  Blockchain.Primitives, Blockchain.Ethereum;

function LabKey(const AIndex: Integer): TBytes;
begin
  if (AIndex < 1) or (AIndex > 9) then raise EDidacticValidation.Create('Use a known laboratory key index from 1 to 9.');
  Result := DecodeHex(StringOfChar('0', 63) + IntToHex(AIndex, 1).ToLower);
end;

function MakeDocumentTransaction(const AFile: string; const ASequence: UInt64;
  const AKeyIndex: Integer; const APolicy: TDidacticPolicy): TDocumentTransaction;
begin
  Result := TDocumentTransaction.Sign(APolicy, LabKey(AKeyIndex), Sha256File(AFile), ASequence);
end;

function LabObject(const APort: Word; const AMethod, APath, ABody: string;
  const AExpectedStatus: Integer; const ABudgetMs: Cardinal): TJSONObject;
var Response: TDidacticHttpResult;
begin
  Response := DidacticRequest(APort, AMethod, APath, ABody, 0, ABudgetMs);
  if Response.Status <> AExpectedStatus then
    raise EDidacticNetwork.CreateFmt('HTTP %d (expected %d): %s', [Response.Status, AExpectedStatus, Response.Body]);
  Result := Response.ObjectValue;
end;

function LabStatus(const APort: Word): TJSONObject;
begin
  Result := LabObject(APort, 'GET', '/status', '');
end;

function LabMine(const APort: Word; const ATimestamp: UInt64): TJSONObject;
var Document: TJSONObject;
begin
  Document := TJSONObject.Create;
  try
    Document.AddPair('timestamp', UIntToStr(ATimestamp));
    Document.AddPair('maxAttempts', '1000000');
    Document.AddPair('timeoutMs', '3000');
    Result := LabObject(APort, 'POST', '/mine', Document.ToJSON, 200, 5000);
  finally Document.Free; end;
end;

function LabSwitch(const APort: Word; const AEnabled: Boolean): TJSONObject;
var Document: TJSONObject;
begin
  Document := TJSONObject.Create;
  try
    if AEnabled then Document.AddPair('enabled', '1') else Document.AddPair('enabled', '0');
    Result := LabObject(APort, 'POST', '/network', Document.ToJSON);
  finally Document.Free; end;
end;

function LabSync(const APort, APeer: Word): TJSONObject;
var Document: TJSONObject;
begin
  Document := TJSONObject.Create;
  try
    Document.AddPair('port', UIntToStr(APeer));
    Result := LabObject(APort, 'POST', '/sync', Document.ToJSON);
  finally Document.Free; end;
end;

function WaitLabField(const APort: Word; const APath, AField, AExpected: string;
  const ATimeoutMs: Cardinal): TJSONObject;
var Clock: TStopwatch; Remaining: Cardinal; Response: TJSONObject; LastError: string;
begin
  Clock := TStopwatch.StartNew;
  repeat
    Remaining := ATimeoutMs - Cardinal(Min(Int64(ATimeoutMs), Clock.ElapsedMilliseconds));
    if Remaining = 0 then Break;
    try
      Response := LabObject(APort, 'GET', APath, '', 200, Min(Cardinal(1500), Remaining));
      if JsonText(Response, AField) = AExpected then Exit(Response);
      Response.Free;
    except on Error: EDidacticNetwork do LastError := Error.Message; end;
    TThread.Sleep(50);
  until Clock.ElapsedMilliseconds >= ATimeoutMs;
  raise EDidacticNetwork.Create('Local wait expired for ' + AField + '=' + AExpected + '. ' + LastError);
end;

end.
