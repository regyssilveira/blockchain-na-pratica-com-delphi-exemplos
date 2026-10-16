[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot, [ValidateRange(1024,65535)][int]$Port=18545)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Prepare-Anvil.ps1')
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } finally { $listener.Stop() }
$output = Join-Path $root 'build\Anvil'
New-Item -ItemType Directory -Force $output | Out-Null
$oldPort = $env:P04_ANVIL_PORT
$oldEvidence = $env:P04_EVIDENCE
$node = $null
try {
    $env:P04_ANVIL_PORT = "$Port"
    $env:P04_EVIDENCE = Join-Path $output 'acceptance.json'
    $node = Start-Process -FilePath (Join-Path $root 'build\tools\anvil\anvil.exe') -ArgumentList @('--host','127.0.0.1','--port',"$Port",'--chain-id','31337','--hardfork','cancun','--accounts','0','--fund-accounts','0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100','--block-base-fee-per-gas','1000000000','--no-mining','--silent') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'node.log') -RedirectStandardError (Join-Path $output 'node.stderr.log')
    $ready = $false
    for ($attempt=0; $attempt -lt 50; $attempt++) {
        $node.Refresh()
        if ($node.HasExited) { throw 'Anvil encerrou antes dos testes.' }
        $client = [System.Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1', $Port); $ready=$true; break } catch { Start-Sleep -Milliseconds 100 } finally { $client.Dispose() }
    }
    if (-not $ready) { throw 'Anvil nao abriu a porta no prazo.' }
    & (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Anvil
} finally {
    if ($null -ne $node -and -not $node.HasExited) { $node.Kill(); $node.WaitForExit() }
    $env:P04_ANVIL_PORT = $oldPort
    $env:P04_EVIDENCE = $oldEvidence
}
