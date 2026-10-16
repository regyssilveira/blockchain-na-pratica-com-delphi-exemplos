[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Protocol.ps1') -DelphiRoot $DelphiRoot
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildSignaturesDemo
$outputRoot = Join-Path $root 'build\Chapter06.Signatures'
$executable = Join-Path $outputRoot 'Chapter06.Signatures.exe'
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
$expected = @('original=True','mensagem_alterada=False','outra_chave=False',
    'assinatura_de_outra_mensagem=False','alterada_assinada_novamente=True')
$observed = @(Get-Content (Join-Path $outputRoot 'experiment.txt'))
if (($observed -join "`n") -cne ($expected -join "`n")) { throw 'Experimento de assinatura divergiu.' }
Invoke-Demo @() 'missing-arguments' 1
$absent = Join-Path $outputRoot ([guid]::NewGuid().ToString('N')+'.absent')
if (Test-Path -LiteralPath $absent) { throw 'Entrada ausente inesperadamente existe.' }
Invoke-Demo @($original,$absent) 'missing-file' 1
$summary = Get-Content (Join-Path $root 'build\Protocol\summary.json') -Raw | ConvertFrom-Json
[pscustomobject]@{passed=$true; compiler=$summary.compiler; target='Win64';
    unitTests=$summary.executed; failures=$summary.failures; errors=$summary.errors;
    ignored=$summary.ignored; signatureCases=5; expectedProcessErrors=2;
    externalNodeRequired=$false; output=$observed} | ConvertTo-Json |
    Set-Content (Join-Path $outputRoot 'acceptance.json') -Encoding UTF8
$observed
Write-Output 'Capitulo 6: protocolo e cinco experimentos de assinatura aprovados.'
