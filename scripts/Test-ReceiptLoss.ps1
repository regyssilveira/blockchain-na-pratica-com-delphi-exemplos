[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1024,65535)][int]$Port=19545)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Prepare-Anvil.ps1')
& (Join-Path $PSScriptRoot 'Build-Contract.ps1')
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildReceiptLossDemo
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildCli
$output = Join-Path $root ('build\Chapter19\receipt-loss-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } finally { $listener.Stop() }
$node=$null
$process=$null
try {
    $node = Start-Process -FilePath (Join-Path $root 'build\tools\anvil\anvil.exe') -ArgumentList @('--host','127.0.0.1','--port',"$Port",'--chain-id','31337','--hardfork','cancun','--accounts','0','--fund-accounts','0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100','--block-base-fee-per-gas','1000000000','--no-mining','--silent') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'node.txt') -RedirectStandardError (Join-Path $output 'node.stderr.txt')
    $ready=$false
    for ($attempt=0; $attempt -lt 50; $attempt++) {
        $node.Refresh()
        if ($node.HasExited) { throw 'Anvil encerrou antes do experimento.' }
        $client=[Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1',$Port); $ready=$true; break } catch { Start-Sleep -Milliseconds 100 } finally {$client.Dispose()}
    }
    if (-not $ready) { throw 'Anvil nao iniciou no prazo.' }
    $process=Start-Process -FilePath (Join-Path $root 'build\Chapter19.ReceiptLoss\Chapter19.ReceiptLoss.exe') -ArgumentList @("$Port",('"'+$output+'"')) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'experiment.txt') -RedirectStandardError (Join-Path $output 'experiment.stderr.txt')
    $null=$process.Handle
    if (-not $process.WaitForExit(20000)) { throw 'Experimento excedeu o prazo.' }
    $process.WaitForExit()
    [pscustomobject]@{passed=($process.ExitCode -eq 0); output=$output; port=$Port; exitCode=$process.ExitCode;
        simulatedHistoryRollback=$true; publicConsensusTested=$false} | ConvertTo-Json |
        Set-Content (Join-Path $root 'build\Chapter19\receipt-loss-latest.json') -Encoding UTF8
    if ($process.ExitCode -ne 0) { throw "Falha no experimento; evidencias em $output" }
    $cli = Join-Path $root 'build\DocumentRegistry.Cli\DocumentRegistry.Cli.exe'
    $checkpoint = Join-Path $output 'registration.json'
    $experiment = Get-Content (Join-Path $output 'receipt-loss.json') -Raw | ConvertFrom-Json
    $cliResults = @{}
    foreach ($command in @('wait','query')) {
        $args = @($command, ('"'+$checkpoint+'"'))
        if ($command -eq 'wait') { $args += '500' }
        $child = Start-Process -FilePath $cli -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output ("cli-$command.json")) -RedirectStandardError (Join-Path $output ("cli-$command.stderr.txt"))
        $null = $child.Handle
        try {
            if (-not $child.WaitForExit(15000)) { throw 'Prazo do cliente excedido.' }
            $child.WaitForExit()
            $expected = if ($command -eq 'wait') {2} else {4}
            if ($child.ExitCode -ne $expected) { throw 'Saida do cliente divergiu apos perda de recibo.' }
            $cliResults[$command] = Get-Content (Join-Path $output ("cli-$command.json")) -Raw | ConvertFrom-Json
        } finally {
            if (-not $child.HasExited) {$child.Kill();$child.WaitForExit()}
            $child.Dispose()
        }
    }
    if ($cliResults.wait.state -ne 'unknown' -or $cliResults.wait.storedState -ne 'succeeded' -or
        $cliResults.query.found -or $cliResults.query.nonce -ne $experiment.nonceAfterRollback) {
        throw 'Cliente reutilizou sucesso historico ou alterou a contagem de envios.'
    }
    [pscustomobject]@{passed=$true; state=$cliResults.wait.state; storedState=$cliResults.wait.storedState;
        waitExitCode=2; queryExitCode=4; sameNonce=$true; found=$cliResults.query.found} | ConvertTo-Json |
        Set-Content (Join-Path $output 'cli-acceptance.json') -Encoding UTF8
} finally {
    if ($null -ne $process) { if (-not $process.HasExited) {$process.Kill();$process.WaitForExit()};$process.Dispose() }
    if ($null -ne $node) { if (-not $node.HasExited) {$node.Kill();$node.WaitForExit()};$node.Dispose() }
}
Get-Content (Join-Path $output 'receipt-loss.json')
