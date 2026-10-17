[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1024,65535)][int]$Port=19345, [switch]$SkipPrototype)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $SkipPrototype) {
    $regressionPort = if ($Port -eq 65535) { $Port - 1 } else { $Port + 1 }
    & (Join-Path $PSScriptRoot 'Test-Prototype.ps1') -DelphiRoot $DelphiRoot -Port $regressionPort
} else {
    & (Join-Path $PSScriptRoot 'Prepare-Anvil.ps1')
    & (Join-Path $PSScriptRoot 'Build-Contract.ps1')
}
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildRegistryAcceptance
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildRegistryDesktop
$output = Join-Path $root ('build\Chapter18\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } finally { $listener.Stop() }
function Invoke-Native([string]$Executable, [string[]]$Arguments, [string]$Name, [string]$WorkingDirectory=$root) {
    $process = Start-Process -FilePath $Executable -ArgumentList @($Arguments | ForEach-Object { '"' + $_ + '"' }) -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output "$Name.log") -RedirectStandardError (Join-Path $output "$Name.stderr.log")
    $null = $process.Handle
    try {
        if (-not $process.WaitForExit(30000)) { throw "Prazo excedido: $Name" }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Falha em $Name. Consulte $output" }
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
$node = $null
try {
    $node = Start-Process -FilePath (Join-Path $root 'build\tools\anvil\anvil.exe') -ArgumentList @('--host','127.0.0.1','--port',"$Port",'--chain-id','31337','--hardfork','cancun','--accounts','0','--fund-accounts','0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100','--block-base-fee-per-gas','1000000000','--no-mining','--silent') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'node.log') -RedirectStandardError (Join-Path $output 'node.stderr.log')
    $ready = $false
    for ($attempt=0; $attempt -lt 50; $attempt++) {
        $node.Refresh()
        if ($node.HasExited) { throw 'Anvil encerrou antes dos testes.' }
        $client = [Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1',$Port); $ready=$true; break } catch { Start-Sleep -Milliseconds 100 } finally { $client.Dispose() }
    }
    if (-not $ready) { throw 'Anvil nao abriu a porta.' }
    $acceptance = Join-Path $root 'build\Chapter18.Acceptance\Chapter18.Acceptance.exe'
    Invoke-Native $acceptance @("$Port",$output) 'workflow'
    $summary = Get-Content -LiteralPath (Join-Path $output 'acceptance.json') -Raw | ConvertFrom-Json
    Invoke-Native (Join-Path $root 'build\Chapter18.Desktop\Chapter18.Desktop.exe') @("$Port",$output,$summary.pendingDeploymentPath) 'ui' $output
    $ui = Get-Content -LiteralPath (Join-Path $output 'ui-acceptance.json') -Raw | ConvertFrom-Json
    if (-not $ui.passed) { throw 'Autoteste VCL nao aprovou.' }
    Invoke-Native $acceptance @("$Port",$output,'check-ui') 'resume'
} finally {
    if ($null -ne $node) {
        if (-not $node.HasExited) { $node.Kill(); $node.WaitForExit() }
        $node.Dispose()
    }
}
Invoke-Native $acceptance @("$Port",$output,'stopped') 'stopped'
[pscustomobject]@{passed=$true; port=$Port; output=$output; workflowChecks=$summary.checksCount;
    uiTimerTicks=$ui.busyTimerTicks; closeDeferred=$ui.closeAttemptsDeferred;
    prototypeExecuted=(-not $SkipPrototype); nodeStopped=$true} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $root 'build\Chapter18\latest.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $root 'build\Chapter18\latest.json')
