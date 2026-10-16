[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1025,65531)][int]$BasePort=18571,
      [string]$RunDirectory)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
if (-not $RunDirectory) { $RunDirectory = Join-Path $root ('build\Didactic\runs\'+[guid]::NewGuid().ToString('N')) }
$RunDirectory = [IO.Path]::GetFullPath($RunDirectory)
if ((Test-Path -LiteralPath $RunDirectory) -and @(Get-ChildItem -LiteralPath $RunDirectory -Force).Count -gt 0) { throw 'Use uma pasta de execucao nova ou vazia.' }
New-Item -ItemType Directory -Force $RunDirectory | Out-Null
$listeners = @()
try {
    foreach ($offset in 0..3) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $BasePort+$offset)
        $listener.Start()
        $listeners += $listener
    }
} finally { foreach ($listener in $listeners) { $listener.Stop() } }
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Didactic
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildDidacticNode
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildDidacticCli
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildDidacticScenario
function Invoke-Native([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$ExpectedExit=0,[int]$Timeout=120000) {
    $quoted = @($Arguments | ForEach-Object { '"'+$_+'"' })
    $process = Start-Process -FilePath $Executable -ArgumentList $quoted -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $RunDirectory "$Name.log") -RedirectStandardError (Join-Path $RunDirectory "$Name.stderr.log")
    $null = $process.Handle
    if (-not $process.WaitForExit($Timeout)) { $process.Kill(); $process.WaitForExit(); throw "Prazo de $Name esgotado; execucao incompleta." }
    $process.WaitForExit()
    if ($process.ExitCode -ne $ExpectedExit) { throw "Falha em $Name; consulte $RunDirectory" }
}
$cli = Join-Path $root 'build\Didactic.Cli\Didactic.Cli.exe'
$document = Join-Path $root 'fixtures\p02\document-a.txt'
Invoke-Native $cli @('block-demo',$document) 'lesson-08'
Invoke-Native $cli @('link-demo',$document) 'lesson-09'
Invoke-Native $cli @('pow-demo') 'lesson-11'
$block = Get-Content (Join-Path $RunDirectory 'lesson-08.log') -Raw | ConvertFrom-Json
$links = Get-Content (Join-Path $RunDirectory 'lesson-09.log') -Raw | ConvertFrom-Json
$pow = Get-Content (Join-Path $RunDirectory 'lesson-11.log') -Raw | ConvertFrom-Json
if (-not $block.hashChanged -or -not $links.recomputedOldBlockRejectedByNextLink -or @($pow.experiments | Where-Object {-not $_.found}).Count -gt 0) { throw 'Experimentos didaticos divergiram.' }
$txPath = Join-Path $RunDirectory 'cli-signed-transaction.json'
Invoke-Native $cli @('make','1',$document,'1',$txPath) 'cli-make'
Invoke-Native $cli @('make','1',$document,'1',(Join-Path $RunDirectory 'invalid-policy.json'),'258') 'cli-invalid-policy' 1
if (Test-Path -LiteralPath (Join-Path $RunDirectory 'invalid-policy.json')) { throw 'Politica invalida produziu arquivo.' }
Invoke-Native (Join-Path $root 'build\Didactic.Scenario\Didactic.Scenario.exe') @($RunDirectory,"$BasePort") 'scenario-process'
$scenario = Get-Content (Join-Path $RunDirectory 'scenario.json') -Raw | ConvertFrom-Json
if (-not $scenario.passed -or $scenario.cases.Count -ne 14 -or @($scenario.cases | Where-Object {-not $_.passed}).Count -gt 0) { throw 'Cenario de nos incompleto.' }
$stores = @(Get-ChildItem -LiteralPath $RunDirectory -Filter '*.json' -File | Where-Object {$_.Name -match '^[ABC]-.*\.json$'})
if ($stores.Count -ne 3) { throw 'Esperados tres snapshots finais.' }
foreach ($store in $stores) {
    $name = 'validate-'+$store.BaseName.Substring(0,1)
    Invoke-Native $cli @('validate',$store.FullName) $name
    $result = Get-Content (Join-Path $RunDirectory "$name.log") -Raw | ConvertFrom-Json
    if (-not $result.valid -or $result.hash -ne $scenario.finalHash -or $result.height -ne '7') { throw 'Validacao offline divergiu.' }
}
Invoke-Native $cli @('validate',(Join-Path $RunDirectory 'corrupt-copy.json')) 'validate-corrupt' 1
$probeRoot = Join-Path $RunDirectory 'lifecycle-probe'
New-Item -ItemType Directory -Force $probeRoot | Out-Null
$probe = Start-Process -FilePath (Join-Path $root 'build\Didactic.Scenario\Didactic.Scenario.exe') -ArgumentList @(('"'+$probeRoot+'"'),"$($BasePort+3)",'lifecycle-probe') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $probeRoot 'probe.log') -RedirectStandardError (Join-Path $probeRoot 'probe.stderr.log')
$null = $probe.Handle
try {
    $readyPath = Join-Path $probeRoot 'lifecycle-ready.json'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $readyPath)) {
        if ($probe.HasExited -or $clock.ElapsedMilliseconds -gt 10000) { throw 'Probe de ciclo de vida nao iniciou.' }
        Start-Sleep -Milliseconds 50
    }
    $ready = Get-Content $readyPath -Raw | ConvertFrom-Json
    $child = [Diagnostics.Process]::GetProcessById([int]$ready.childPid)
    $null = $child.Handle
    $probe.Kill(); $probe.WaitForExit()
    if (-not $child.WaitForExit(3000)) { throw 'Processo filho permaneceu vivo depois de encerrar o pai.' }
    [pscustomobject]@{passed=$true; deliberatelyTerminatedParent=$true; childTerminatedByJob=$true; childPid=$ready.childPid} | ConvertTo-Json | Set-Content (Join-Path $RunDirectory 'lifecycle.json') -Encoding UTF8
} finally { if (-not $probe.HasExited) { $probe.Kill(); $probe.WaitForExit() } }
$summary = Get-Content (Join-Path $root 'build\Didactic\summary.json') -Raw | ConvertFrom-Json
[pscustomobject]@{passed=$true; compiler=$summary.compiler; target='Win64'; executed=$summary.executed; failures=$summary.failures; errors=$summary.errors; ignored=$summary.ignored; nativeScenarioCases=14; finalHash=$scenario.finalHash; finalHeight=$scenario.finalHeight; work=$scenario.work; runDirectory=$RunDirectory; basePort=$BasePort; externalNodeRequired=$false} | ConvertTo-Json | Set-Content (Join-Path $root 'build\Didactic\acceptance.json') -Encoding UTF8
Get-Content (Join-Path $RunDirectory 'scenario-process.log')
Write-Output 'Blockchain didatica: testes, tres nos Delphi e snapshots finais aprovados.'
