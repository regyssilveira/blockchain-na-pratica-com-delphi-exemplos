[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [ValidateRange(1024,65535)][int]$Port=18545, [string]$DocumentPath)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Anvil.ps1') -DelphiRoot $DelphiRoot -Port $Port -DocumentPath $DocumentPath -FullPrototype
# A instancia real criada acima foi encerrada no finally. Consultar nao pode retornar sucesso.
$processes = Get-Content (Join-Path $root 'build\Anvil\prototype-processes.json') -Raw | ConvertFrom-Json
$clock = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath (Join-Path $root 'build\DocumentRegistry.Cli\DocumentRegistry.Cli.exe') -ArgumentList @('query',('"' + $processes.registrationCheckpoint + '"')) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'build\Anvil\stopped-node.log') -RedirectStandardError (Join-Path $root 'build\Anvil\stopped-node.stderr.log')
$null = $process.Handle
if (-not $process.WaitForExit(12000)) { $process.Kill(); $process.WaitForExit(); throw 'Prazo do teste de no parado excedido.' }
$process.WaitForExit()
$log = Get-Content (Join-Path $root 'build\Anvil\stopped-node.log') -Raw
if ($process.ExitCode -ne 1 -or $log -notmatch 'Transport failure') { throw 'No parado nao produziu a falha de transporte esperada.' }
[pscustomobject]@{realNodeStopped=$true; exitCode=$process.ExitCode; elapsedMs=$clock.ElapsedMilliseconds; originalHash=$processes.hash; passed=$true} | ConvertTo-Json | Set-Content (Join-Path $root 'build\Anvil\stopped-node.json') -Encoding UTF8
Write-Output 'Prototipo completo: testes, retomada entre processos e falha com no real parado aprovados.'
