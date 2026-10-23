[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1024,65535)][int]$Port=20045)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Prepare-Anvil.ps1')
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildRpcDemo
$output = Join-Path $root 'build\Chapter15.Read'
$executable = Join-Path $output 'Chapter15.Read.exe'
function Invoke-Demo([string]$Name,[string[]]$Arguments,[int]$ExpectedExit) {
    $options = @{FilePath=$executable; WorkingDirectory=$root; WindowStyle="Hidden"; PassThru=$true; RedirectStandardOutput=(Join-Path $output "$Name.json"); RedirectStandardError=(Join-Path $output "$Name.stderr.txt")}
    if ($Arguments.Count -gt 0) { $options.ArgumentList=$Arguments }
    $p = Start-Process @options
    $null = $p.Handle
    if (-not $p.WaitForExit(15000)) { $p.Kill(); $p.WaitForExit(); throw 'Prazo do console excedido.' }
    $p.WaitForExit()
    if ($p.ExitCode -ne $ExpectedExit) { throw "Saida inesperada em $Name." }
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try { $listener.Start() } finally { $listener.Stop() }
$node = $null
try {
    $node = Start-Process -FilePath (Join-Path $root 'build\tools\anvil\anvil.exe') -ArgumentList @('--host','127.0.0.1','--port',"$Port",'--chain-id','31337','--hardfork','cancun','--accounts','0','--fund-accounts','0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100','0x7e5f4552091a69125d5dfcb7b8c2659029395bdf:100','--block-base-fee-per-gas','1000000000','--no-mining','--silent') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'node.txt') -RedirectStandardError (Join-Path $output 'node.stderr.txt')
    $ready = $false
    for ($i=0;$i -lt 50;$i++) {
        if ($node.HasExited) { throw 'Anvil encerrou antes da consulta.' }
        $client = [Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1',$Port); $ready=$true; break } catch { Start-Sleep -Milliseconds 100 } finally { $client.Dispose() }
    }
    if (-not $ready) { throw 'Anvil nao abriu a porta.' }
    Invoke-Demo -Name 'environment' -Arguments @("$Port") -ExpectedExit 0
    Invoke-Demo -Name 'missing-arguments' -Arguments @() -ExpectedExit 1
} finally {
    if ($null -ne $node -and -not $node.HasExited) { $node.Kill(); $node.WaitForExit() }
}
Invoke-Demo -Name 'stopped-node' -Arguments @("$Port") -ExpectedExit 1
if ((Get-Content (Join-Path $output 'missing-arguments.stderr.txt') -Raw) -notmatch 'Uso:') { throw 'Erro esperado de argumentos nao observado.' }
if ((Get-Content (Join-Path $output 'stopped-node.stderr.txt') -Raw) -notmatch 'Transport failure') { throw 'Falha esperada de transporte nao observada.' }
$observed = Get-Content (Join-Path $output 'environment.json') -Raw | ConvertFrom-Json
if ($observed.chainId -ne '31337') { throw 'Rede esperada nao observada.' }
[pscustomobject]@{passed=$true; compiler=(Get-Item (Join-Path $DelphiRoot 'bin\dcc64.exe')).VersionInfo.FileVersion; target='Win64'; environment=$observed; expectedProcessErrors=2; readOnlyQueries=$true; ownNodeStopped=$true} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output 'acceptance.json') -Encoding UTF8
Get-Content (Join-Path $output 'environment.json')
