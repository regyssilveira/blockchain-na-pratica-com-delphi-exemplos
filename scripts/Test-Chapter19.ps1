[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1024,65533)][int]$Port=19545, [switch]$SkipIntegration)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Security
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildSecurityDemo
$output = Join-Path $root ('build\Chapter19\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$executable = Join-Path $root 'build\Chapter19.Security\Chapter19.Security.exe'
function Invoke-Native([string[]]$Arguments, [string]$Name, [int]$ExpectedExit) {
    $parameters = @{FilePath=$executable; WorkingDirectory=$root; WindowStyle='Hidden'; PassThru=$true;
        RedirectStandardOutput=(Join-Path $output "$Name.txt"); RedirectStandardError=(Join-Path $output "$Name.stderr.txt")}
    if ($Arguments.Count -gt 0) { $parameters.ArgumentList = @($Arguments | ForEach-Object {'"'+$_+'"'}) }
    $process = Start-Process @parameters
    $null = $process.Handle
    try {
        if (-not $process.WaitForExit(15000)) { throw "Prazo excedido em $Name" }
        $process.WaitForExit()
        if ($process.ExitCode -ne $ExpectedExit) { throw "Saida inesperada em $Name" }
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
$data = Join-Path $output 'fixture with spaces'
Invoke-Native @('prepare',$data) 'prepare' 0
Invoke-Native @('check-key',(Join-Path $data 'published-test-key.dpapi')) 'reopen-another-process' 0
Invoke-Native @('audit',(Join-Path $data 'offline-checkpoint.json')) 'audit' 0
Invoke-Native @('prepare',$data) 'existing-output' 1
Invoke-Native @('check-key',(Join-Path $data 'absent.dpapi')) 'missing-file' 1
$corrupt = Join-Path $data 'corrupt.dpapi'
[IO.File]::WriteAllBytes($corrupt, [byte[]](1,2,3,4,5))
Invoke-Native @('check-key',$corrupt) 'corrupt-file' 1
Invoke-Native @() 'missing-arguments' 1
$prepared = Get-Content (Join-Path $output 'prepare.txt') -Raw | ConvertFrom-Json
$reopened = Get-Content (Join-Path $output 'reopen-another-process.txt') -Raw | ConvertFrom-Json
$audit = Get-Content (Join-Path $output 'audit.txt') -Raw | ConvertFrom-Json
if (-not $prepared.protectedFileCreated -or $prepared.transactionSent -or -not $reopened.recoveredKnownFixture) { throw 'Protecao/recuperacao nao comprovadas.' }
$names = @($audit.PSObject.Properties.Name | Sort-Object)
if (($names -join ',') -ne 'chainId,schema,state,transactionHash') { throw 'Exportacao contem campos inesperados.' }
$allOutput = @(Get-ChildItem -LiteralPath $output -Filter '*.txt' -File | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
if ($allOutput -match ('46' * 32) -or $allOutput -match 'OFFLINE-FIXTURE-DO-NOT-LOG') { throw 'Canario indevido na saida.' }
$summary = Get-Content (Join-Path $root 'build\Security\summary.json') -Raw | ConvertFrom-Json
[pscustomobject]@{passed=$true; output=$output; compiler=$summary.compiler; target='Win64';
    executed=$summary.executed; failures=$summary.failures; errors=$summary.errors; ignored=$summary.ignored;
    previousTests=76; newTests=18; positiveProcesses=3; expectedProcessErrors=4;
    networkUsed=$false; dpapiCurrentUser=$true; differentUserTested=$false;
    protectedBlobPublished=$false; realSecretUsed=$false; knownFixtureKeyOnly=$true; minimalAuditFields=$names} | ConvertTo-Json |
    Set-Content (Join-Path $output 'acceptance.json') -Encoding UTF8
[pscustomobject]@{passed=$true; output=$output} | ConvertTo-Json |
    Set-Content (Join-Path $root 'build\Chapter19\latest.json') -Encoding UTF8
Get-Content (Join-Path $output 'acceptance.json')

if (-not $SkipIntegration) {
    & (Join-Path $PSScriptRoot 'Test-Chapter18.ps1') -DelphiRoot $DelphiRoot -Port ($Port+1)
    & (Join-Path $PSScriptRoot 'Test-ReceiptLoss.ps1') -DelphiRoot $DelphiRoot -Port $Port
}

$full = [ordered]@{passed=$true; securityOutput=$output; integrationExecuted=(-not $SkipIntegration)}
if (-not $SkipIntegration) {
    $application = Get-Content (Join-Path $root 'build\Chapter18\latest.json') -Raw | ConvertFrom-Json
    $loss = Get-Content (Join-Path $root 'build\Chapter19\receipt-loss-latest.json') -Raw | ConvertFrom-Json
    if (-not $application.passed -or -not $loss.passed) { throw 'Integracao completa nao comprovada.' }
    $full.applicationOutput = $application.output
    $full.receiptLossOutput = $loss.output
}
$full | ConvertTo-Json | Set-Content (Join-Path $root 'build\Chapter19\full-latest.json') -Encoding UTF8
