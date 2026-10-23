program Didactic.Cli;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.JSON, System.IOUtils,
  Didactic.Codec, Didactic.Transaction, Didactic.Block, Didactic.Chain,
  Didactic.Http, Didactic.LabClient, Blockchain.Primitives;

function PortArgument(const AIndex: Integer): Word;
var Value: UInt64;
begin
  Value := CanonicalUInt(ParamStr(AIndex));
  if (Value < 1) or (Value > 65535) then raise EDidacticValidation.Create('Invalid port.');
  Result := Value;
end;

procedure RequireArguments(const AMinimum, AMaximum: Integer);
begin
  if (ParamCount < AMinimum) or (ParamCount > AMaximum) then
    raise EDidacticValidation.Create('Invalid command arguments. See chapters/part03/README.md.');
end;

function PolicyArgument(const AIndex: Integer): TDidacticPolicy;
var Value: UInt64;
begin
  Value := CanonicalUInt(ParamStr(AIndex));
  if (Value < 2) or (Value > 4) then raise EDidacticValidation.Create('Difficulty must be 2, 3 or 4.');
  Result := TDidacticPolicy.Create(Value);
end;

procedure Run;
var Command: string; Document, Input: TJSONObject;
  Transaction: TDocumentTransaction; Block, Changed, Previous, OriginalPrevious: TDidacticBlock;
  Chain: TDidacticChain; Policy: TDidacticPolicy; Mining: TMiningResult;
  Items: TJSONArray; Difficulty: Integer; Rejected: Boolean; LinkDiagnostic, TimeDiagnostic: string;
begin
  if ParamCount = 0 then raise EDidacticValidation.Create('Commands: make send status mine document transaction sync network stop validate wait-tip wait-tx block-demo link-demo pow-demo');
  Command := ParamStr(1);
  Policy := TDidacticPolicy.Create;
  Document := nil; Input := nil; Chain := nil;
  try
    if Command = 'make' then
    begin
      RequireArguments(5, 6);
      if ParamCount = 6 then Policy := PolicyArgument(6);
      Transaction := MakeDocumentTransaction(ParamStr(3), CanonicalUInt(ParamStr(4)), StrToInt(ParamStr(2)), Policy);
      Document := Transaction.ToJson;
      SaveAtomicUtf8(ParamStr(5), Document.ToJSON);
      Document.AddPair('id', Transaction.Id);
      Document.AddPair('account', Transaction.Account);
    end
    else if Command = 'send' then
    begin
      RequireArguments(3, 3);
      Document := LabObject(PortArgument(2), 'POST', '/transactions', TFile.ReadAllText(ParamStr(3), TEncoding.UTF8));
    end
    else if Command = 'status' then begin RequireArguments(2, 2); Document := LabStatus(PortArgument(2)); end
    else if Command = 'mine' then begin RequireArguments(3, 3); Document := LabMine(PortArgument(2), CanonicalUInt(ParamStr(3))); end
    else if Command = 'sync' then begin RequireArguments(3, 3); Document := LabSync(PortArgument(2), PortArgument(3)); end
    else if Command = 'network' then
    begin
      RequireArguments(3, 3);
      if (ParamStr(3) <> '0') and (ParamStr(3) <> '1') then raise EDidacticValidation.Create('Use zero or one.');
      Document := LabSwitch(PortArgument(2), ParamStr(3) = '1');
    end
    else if Command = 'stop' then begin RequireArguments(2, 2); Document := LabObject(PortArgument(2), 'POST', '/stop', '{}'); end
    else if Command = 'document' then
    begin
      RequireArguments(4, 4);
      Document := LabObject(PortArgument(2), 'GET', '/documents/' + ParamStr(3) + '/' + ParamStr(4), '');
      if not (Document.GetValue('found') is TJSONTrue) then System.ExitCode := 4;
    end
    else if Command = 'transaction' then
    begin
      RequireArguments(3, 3);
      Document := LabObject(PortArgument(2), 'GET', '/transactions/' + ParamStr(3), '');
    end
    else if Command = 'wait-tip' then begin RequireArguments(3, 3); Document := WaitLabField(PortArgument(2), '/status', 'hash', ParamStr(3)); end
    else if Command = 'wait-tx' then
    begin
      RequireArguments(4, 4);
      Document := WaitLabField(PortArgument(2), '/transactions/' + ParamStr(3), 'state', ParamStr(4));
    end
    else if Command = 'validate' then
    begin
      RequireArguments(2, 3);
      if ParamCount = 3 then Policy := PolicyArgument(3);
      Chain := TDidacticChain.Load(ParamStr(2), Policy);
      Document := TJSONObject.Create;
      Document.AddPair('valid', TJSONBool.Create(True));
      Document.AddPair('hash', Chain.Tip.Hash);
      Document.AddPair('height', UIntToStr(Chain.Tip.Height));
      Document.AddPair('pending', IntToStr(Chain.PendingCount));
    end
    else if (Command = 'block-demo') or (Command = 'link-demo') then
    begin
      RequireArguments(2, 2);
      Transaction := MakeDocumentTransaction(ParamStr(2), 1, 1, Policy);
      Previous := GenesisBlock(Policy);
      Block := Default(TDidacticBlock);
      Block.Height := 1; Block.Timestamp := 1; Block.Difficulty := 2;
      Block.PreviousHash := Previous.Hash;
      Block.Transactions := TArray<TDocumentTransaction>.Create(Transaction);
      Block.Hash := Block.CalculateHash(Policy);
      Block.ValidateLink(Policy, Previous);
      Document := TJSONObject.Create;
      Document.AddPair('canonicalHex', BytesToLowerHex(Block.CanonicalBytes(Policy)));
      Document.AddPair('originalHash', Block.Hash);
      if Command = 'block-demo' then
      begin
        Changed := Block; Changed.Transactions := Copy(Block.Transactions);
        Changed.Transactions[0].DocumentHash := Sha256Bytes(TEncoding.UTF8.GetBytes('altered'));
        Document.AddPair('alteredHash', Changed.CalculateHash(Policy));
        Document.AddPair('hashChanged', TJSONBool.Create(Block.Hash <> Changed.CalculateHash(Policy)));
      end
      else
      begin
        // B1 e B2 sao candidatos comuns; a genese permanece intacta.
        OriginalPrevious := Block;
        Previous := OriginalPrevious;
        Block.Height := 2;
        Block.Timestamp := 20;
        Block.PreviousHash := Previous.Hash;
        Block.Hash := Block.CalculateHash(Policy);
        Block.ValidateLink(Policy, Previous); // controle positivo
        Previous.Timestamp := 2; // ainda menor que 20
        Previous.Hash := Previous.CalculateHash(Policy);
        Rejected := False;
        LinkDiagnostic := '';
        try Block.ValidateLink(Policy, Previous); except
          on Error: EDidacticValidation do
          begin Rejected := True; LinkDiagnostic := Error.Message; end;
        end;
        if not Rejected or (LinkDiagnostic <> 'Broken block link.') then
          raise EDidacticValidation.Create('Expected isolated link rejection.');
        Document.AddPair('recomputedOldBlockRejectedByNextLink', TJSONBool.Create(Rejected));
        Document.AddPair('linkDiagnostic', LinkDiagnostic);
        Document.AddPair('timeStillIncreasing', TJSONBool.Create(Block.Timestamp > Previous.Timestamp));
        Previous := OriginalPrevious;
        Changed := Block;
        Changed.Timestamp := Previous.Timestamp; // referencia correta, instante repetido
        Changed.Hash := Changed.CalculateHash(Policy);
        TimeDiagnostic := '';
        try Changed.ValidateLink(Policy, Previous); except
          on Error: EDidacticValidation do TimeDiagnostic := Error.Message;
        end;
        if TimeDiagnostic <> 'Block timestamp must increase.' then
          raise EDidacticValidation.Create('Expected isolated timestamp rejection.');
        Document.AddPair('timeDiagnostic', TimeDiagnostic);
        Document.AddPair('referenceStillMatching', TJSONBool.Create(Changed.PreviousHash = Previous.Hash));
        Document.AddPair('ownHashStillMatching', TJSONBool.Create(Changed.Hash = Changed.CalculateHash(Policy)));
      end;
      Document.AddPair('scope', 'Draft block hash/link demonstration; full ledger also validates signatures, state and proof of work.');
    end
    else if Command = 'pow-demo' then
    begin
      RequireArguments(1, 1);
      Document := TJSONObject.Create; Items := TJSONArray.Create; Document.AddPair('experiments', Items);
      for Difficulty := 2 to 4 do
      begin
        Policy := TDidacticPolicy.Create(Difficulty); Block := GenesisBlock(Policy);
        Mining := MineBlock(Block, Policy, 1000000, 5000);
        Input := TJSONObject.Create;
        Input.AddPair('difficulty', IntToStr(Difficulty)); Input.AddPair('found', TJSONBool.Create(Mining.Found));
        Input.AddPair('attempts', UIntToStr(Mining.Attempts)); Input.AddPair('elapsedMs', IntToStr(Mining.ElapsedMs));
        Input.AddPair('hash', Block.Hash); Items.AddElement(Input); Input := nil;
      end;
    end
    else raise EDidacticValidation.Create('Unknown command.');
    Writeln(Document.ToJSON);
  finally Chain.Free; Input.Free; Document.Free; end;
end;

begin
  try Run; except on Error: Exception do begin Writeln(Error.ClassName, ': ', Error.Message); System.ExitCode := 1; end; end;
end.
