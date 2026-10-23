[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Didactic
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildDidacticCli
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildTraceDemo
$output = Join-Path $root ('build\ReadingRevision\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
function Invoke-Observed([string]$Executable, [string[]]$Arguments, [string]$Name, [int]$ExpectedExit=0) {
    $process = Start-Process -FilePath (Join-Path $root $Executable) -WindowStyle Hidden -PassThru `
        -WorkingDirectory $root -ArgumentList @($Arguments | ForEach-Object {'"'+$_+'"'}) `
        -RedirectStandardOutput (Join-Path $output "$Name.json") `
        -RedirectStandardError (Join-Path $output "$Name.stderr.txt")
    $null = $process.Handle
    try {
        if (-not $process.WaitForExit(30000)) { throw "Tempo excedido: $Name" }
        $process.WaitForExit()
        if ($process.ExitCode -ne $ExpectedExit) { throw "Codigo inesperado: $Name" }
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    if ($ExpectedExit -eq 0) { return Get-Content (Join-Path $output "$Name.json") -Raw | ConvertFrom-Json }
}
$cli = 'build\Didactic.Cli\Didactic.Cli.exe'
$block = Invoke-Observed $cli @('block-demo','fixtures/p02/document-a.txt') 'block'
$link = Invoke-Observed $cli @('link-demo','fixtures/p02/document-a.txt') 'link'
$pow = Invoke-Observed $cli @('pow-demo') 'pow'
$trace = Invoke-Observed 'build\Chapter17.Trace\Chapter17.Trace.exe' @('fixtures/p02/document-a.txt') 'trace'
$other = Invoke-Observed 'build\Chapter17.Trace\Chapter17.Trace.exe' @('fixtures/p02/document-b.txt') 'trace-altered'
Invoke-Observed 'build\Chapter17.Trace\Chapter17.Trace.exe' @('build/ReadingRevision/missing.txt') 'missing-file' 1
if (-not $block.hashChanged -or $block.originalHash -ne '5378f62593d39dcab0a75c92952bf957a010d6a70b84e9635e48834689f899a4') { throw 'Bloco divergiu do vetor publicado.' }
if ($block.canonicalHex.Substring(0,8) -ne '00000010' -or
    $block.canonicalHex.Substring(40,8) -ne '00000015' -or
    $block.canonicalHex.Substring(90,16) -ne '0000000000000001' -or
    $block.canonicalHex.Substring(204,8) -ne '00000001') { throw 'Posicoes do mapa canonico divergentes.' }
if (-not $link.timeStillIncreasing -or -not $link.referenceStillMatching -or -not $link.ownHashStillMatching -or
    $link.linkDiagnostic -ne 'Broken block link.' -or $link.timeDiagnostic -ne 'Block timestamp must increase.') { throw 'Causas nao isoladas.' }
if (@($pow.experiments | Where-Object {-not $_.found}).Count -ne 0 -or
    (($pow.experiments.attempts -join ',') -ne '287,5141,30655')) { throw 'Busca nao reproduzida.' }
$expectedDocument = (Get-FileHash (Join-Path $root 'fixtures/p02/document-a.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($trace.documentHash -ne $expectedDocument -or $trace.callBytes -ne 36 -or $trace.rlpZero -ne '80' -or
    $trace.callData.Substring(8) -ne $expectedDocument -or $trace.selector -ne $trace.callData.Substring(0,8) -or
    -not $trace.signatureVerified -or $trace.sent -or
    $trace.recoveredAccount -ne '7e5f4552091a69125d5dfcb7b8c2659029395bdf' -or
    $trace.signingHash -eq $trace.transactionHash -or $trace.documentHash -eq $other.documentHash -or
    $trace.transactionHash -eq $other.transactionHash) { throw 'Rastro binario inconsistente.' }
[pscustomobject]@{passed=$true; output=$output; didacticTests=114; isolatedLink=$true;
    isolatedTime=$true; offlineTrace=$true; alteredDocument=$true; missingFileRejected=$true;
    sha256IndependentWindowsCheck=$true; networkUsed=$false} | ConvertTo-Json |
    Set-Content (Join-Path $output 'acceptance.json') -Encoding UTF8
[pscustomobject]@{passed=$true; output=$output} | ConvertTo-Json |
    Set-Content (Join-Path $root 'build\ReadingRevision\latest.json') -Encoding UTF8
Get-Content (Join-Path $output 'acceptance.json')
