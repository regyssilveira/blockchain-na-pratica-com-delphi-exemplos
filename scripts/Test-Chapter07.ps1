[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Didactic
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildTransactionsDemo
$outputRoot = Join-Path $root 'build\Chapter07.Transactions'
$executable = Join-Path $outputRoot 'Chapter07.Transactions.exe'
$original = Join-Path $root 'fixtures\p02\document-a.txt'
$changed = Join-Path $root 'fixtures\p02\document-b.txt'
function Invoke-Demo([string[]]$Arguments, [string]$Name, [int]$ExpectedExit) {
    $parameters = @{FilePath=$executable; WorkingDirectory=$root; WindowStyle='Hidden'; PassThru=$true;
        RedirectStandardOutput=(Join-Path $outputRoot "$Name.txt");
        RedirectStandardError=(Join-Path $outputRoot "$Name.stderr.txt")}
    if ($Arguments.Count -gt 0) { $parameters.ArgumentList = @($Arguments | ForEach-Object { '"'+$_+'"' }) }
    $process = Start-Process @parameters
    $null = $process.Handle
    if (-not $process.WaitForExit(15000)) {
        $process.Kill(); $process.WaitForExit()
        throw "Prazo de $Name esgotado; execucao incompleta."
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne $ExpectedExit) { throw "Codigo de saida inesperado em $Name." }
}
Invoke-Demo @($original,$changed) 'experiment' 0
$expected = @('validacao_sem_aplicacao=True','primeiro_registro=True',
    'formato_invalido_rejeitado=True','adulteracao_rejeitada=True','reenvio_rejeitado=True',
    'sequencia_reutilizada_rejeitada=True','salto_rejeitado=True',
    'documento_duplicado_rejeitado=True','outra_rede_rejeitada=True',
    'estado_apos_rejeicoes_preservado=True','mesmo_documento_outra_conta=True',
    'proxima_sequencia=True','reconstrucao_do_estado=True','ordem_invertida_rejeitada=True')
$observed = @(Get-Content (Join-Path $outputRoot 'experiment.txt'))
if (($observed -join "`n") -cne ($expected -join "`n")) { throw 'Experimento de transacao divergiu.' }
Invoke-Demo @() 'missing-arguments' 1
$absent = Join-Path $outputRoot ([guid]::NewGuid().ToString('N')+'.absent')
if (Test-Path -LiteralPath $absent) { throw 'Entrada ausente inesperadamente existe.' }
Invoke-Demo @($original,$absent) 'missing-file' 1
Invoke-Demo @($original,$original) 'identical-inputs' 1
$summary = Get-Content (Join-Path $root 'build\Didactic\summary.json') -Raw | ConvertFrom-Json
[pscustomobject]@{passed=$true; compiler=$summary.compiler; target='Win64';
    unitTests=$summary.executed; failures=$summary.failures; errors=$summary.errors;
    ignored=$summary.ignored; stateCases=14; expectedProcessErrors=3;
    externalNodeRequired=$false; output=$observed} | ConvertTo-Json |
    Set-Content (Join-Path $outputRoot 'acceptance.json') -Encoding UTF8
$observed
Write-Output 'Capitulo 7: testes e catorze verificacoes de transacoes/estado aprovados.'
