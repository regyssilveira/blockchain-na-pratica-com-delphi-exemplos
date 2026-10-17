unit Blockchain.TrackingAudit;

interface

uses System.JSON, Blockchain.TransactionJournal;

// Exportacao com campos permitidos. Nao anonimiza a transacao nem substitui o checkpoint.
function MinimalTrackingAudit(const ACheckpoint: TTransactionCheckpoint): TJSONObject;

implementation

uses Blockchain.Primitives;

function MinimalTrackingAudit(const ACheckpoint: TTransactionCheckpoint): TJSONObject;
begin
  ACheckpoint.Validate;
  Result := TJSONObject.Create;
  try
    Result.AddPair('schema', TJSONNumber.Create(1));
    Result.AddPair('state', ACheckpoint.State);
    Result.AddPair('chainId', TExactUInt256.FromDecimal(ACheckpoint.ChainId).ToDecimal);
    Result.AddPair('transactionHash', ACheckpoint.Hash);
    if ACheckpoint.BlockNumber <> '' then
      Result.AddPair('blockNumber', TExactUInt256.FromDecimal(ACheckpoint.BlockNumber).ToDecimal);
    // Nunca copiar Diagnostic, RawHex, DocumentHash, Account ou JSON recebido do no.
  except
    Result.Free;
    raise;
  end;
end;

end.
