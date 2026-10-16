program Didactic.Node;

{$APPTYPE CONSOLE}

uses System.SysUtils, Didactic.Codec, Didactic.NodeService;

procedure Run;
var Node: TDidacticNode; Parts: TArray<string>; Peers: TArray<Word>;
  Index, Port, Difficulty, Peer: Integer;
begin
  if (ParamCount < 3) or (ParamCount > 5) then
    raise EDidacticValidation.Create('Usage: Didactic.Node nodeId port dataFile [peerPortsCommaSeparated] [difficulty]');
  Port := StrToInt(ParamStr(2));
  if (Port < 1) or (Port > 65535) then raise EDidacticValidation.Create('Invalid port.');
  if ParamCount >= 5 then Difficulty := StrToInt(ParamStr(5)) else Difficulty := 2;
  if (Difficulty < 2) or (Difficulty > 4) then raise EDidacticValidation.Create('Invalid difficulty.');
  Peers := nil;
  if (ParamCount >= 4) and (ParamStr(4) <> '-') then
  begin
    Parts := ParamStr(4).Split([',']);
    SetLength(Peers, Length(Parts));
    for Index := 0 to High(Parts) do
    begin
      Peer := StrToInt(Parts[Index]);
      if (Peer < 1) or (Peer > 65535) then raise EDidacticValidation.Create('Invalid peer.');
      Peers[Index] := Peer;
    end;
  end;
  Node := TDidacticNode.Create(ParamStr(1), ParamStr(3), Port, Peers, TDidacticPolicy.Create(Difficulty));
  try
    Node.Start;
    Writeln('Didactic node ready on loopback port ', Port);
    Node.Run;
  finally Node.Free; end;
end;

begin
  try Run; except on Error: Exception do begin Writeln(Error.ClassName, ': ', Error.Message); System.ExitCode := 1; end; end;
end.
