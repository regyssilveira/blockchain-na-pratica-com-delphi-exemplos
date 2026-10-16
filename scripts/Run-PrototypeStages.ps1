[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DelphiRoot,
      [Parameter(Mandatory=$true)][int]$Port,
      [Parameter(Mandatory=$true)][string]$DocumentPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -BuildCli
$executable = Join-Path $root 'build\DocumentRegistry.Cli\DocumentRegistry.Cli.exe'
$run = Join-Path $root ('build\Anvil\prototype-runs\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $run | Out-Null
$deploymentPath = Join-Path $run 'deployment.json'
$registrationPath = Join-Path $run 'registration.json'
$operations = [Collections.Generic.List[object]]::new()
function Invoke-Client([string]$Name, [string[]]$ClientArguments, [int]$ExpectedExit=0) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $quoted = @($ClientArguments | ForEach-Object { '"' + $_ + '"' })
    $process = Start-Process -FilePath $executable -ArgumentList $quoted -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run "$Name.log") -RedirectStandardError (Join-Path $run "$Name.stderr.log")
    $null = $process.Handle
    if (-not $process.WaitForExit(35000)) { $process.Kill(); $process.WaitForExit(); throw "Timeout do cliente: $Name" }
    $process.WaitForExit()
    $operations.Add([pscustomobject]@{name=$Name; processId=$process.Id; exitCode=$process.ExitCode; elapsedMs=$clock.ElapsedMilliseconds})
    if ($process.ExitCode -ne $ExpectedExit) { throw "Saida inesperada em $Name; consulte $run" }
}
$oldPort = $env:P04_ANVIL_PORT
try {
    # Clientes retomados usam a configuracao preservada, sem depender dessa variavel.
    $env:P04_ANVIL_PORT = $null
    Invoke-Client '01-deploy' @('deploy',$deploymentPath,"$Port")
    Invoke-Client '02-deployment-pending' @('wait',$deploymentPath,'100') 2
    Invoke-Client '03-mine-deployment' @('mine',"$Port")
    Invoke-Client '04-confirm-deployment' @('wait',$deploymentPath,'2000')
    Invoke-Client '05-register' @('register',$deploymentPath,$DocumentPath,$registrationPath)
    $initial = Get-Content $registrationPath -Raw | ConvertFrom-Json
    Invoke-Client '06-registration-pending' @('wait',$registrationPath,'1000') 2
    $pending = Get-Content $registrationPath -Raw | ConvertFrom-Json
    if ($pending.state -ne 'pending' -or $pending.hash -ne $initial.hash) { throw 'Pendencia nao preservou identificador.' }
    Invoke-Client '07-query-before-mining' @('query',$registrationPath) 4
    Invoke-Client '08-mine-registration' @('mine',"$Port")
    Invoke-Client '09-resume-original-hash' @('wait',$registrationPath,'2000')
    Invoke-Client '10-query-restarted-client' @('query',$registrationPath)
    $first = Get-Content ($registrationPath + '.query.json') -Raw | ConvertFrom-Json
    Invoke-Client '11-query-another-process' @('query',$registrationPath)
    $second = Get-Content ($registrationPath + '.query.json') -Raw | ConvertFrom-Json
    $confirmed = Get-Content $registrationPath -Raw | ConvertFrom-Json
    if (-not $first.found -or -not $second.found -or $first.nonce -ne $second.nonce -or $confirmed.hash -ne $initial.hash -or $confirmed.state -ne 'succeeded') { throw 'Retomada divergiu ou alterou o nonce.' }
    # Referencias padrao: copia reconhecida e documento alterado ausente.
    if ((Get-FileHash $DocumentPath -Algorithm SHA256).Hash -eq (Get-FileHash (Join-Path $root 'fixtures\p02\document-a.txt') -Algorithm SHA256).Hash) {
        Invoke-Client '12-verify-copy' @('verify',$registrationPath,(Join-Path $root 'fixtures\p02\document-a-copy.txt'))
        Invoke-Client '13-verify-changed' @('verify',$registrationPath,(Join-Path $root 'fixtures\p02\document-b.txt')) 4
    }
    [pscustomobject]@{passed=$true; port=$Port; runDirectory=$run; registrationCheckpoint=$registrationPath; hash=$confirmed.hash; state=$confirmed.state; blockNumber=$confirmed.blockNumber; resumedNonce=$first.nonce; queryNonce=$second.nonce; operations=$operations.ToArray()} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root 'build\Anvil\prototype-processes.json') -Encoding UTF8
    Write-Output 'P05-P08: clientes independentes retomaram consulta sem reenviar transacao.'
} finally { $env:P04_ANVIL_PORT = $oldPort }
