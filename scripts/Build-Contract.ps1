[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root 'build\tools\solc'
New-Item -ItemType Directory -Force $directory | Out-Null
$executable = Join-Path $directory 'solc.exe'
$url = 'https://binaries.soliditylang.org/windows-amd64/solc-windows-amd64-v0.8.37+commit.f401782d.exe'
$checksum = '967743b2d12155f59a0ddf9410afe25c7deaa73f4fe3d33c4dc0739f627d9ec9'
if (-not (Test-Path -LiteralPath $executable)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $executable }
if ((Get-FileHash $executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $checksum) { throw 'Checksum solc divergente; remova somente build/tools/solc/solc.exe e repita.' }
$version = & $executable --version
if ($LASTEXITCODE -ne 0 -or ($version -join "`n") -notmatch '0.8.37\+commit.f401782d') { throw 'Versao solc inesperada.' }
$output = Join-Path $root 'build\contract'
New-Item -ItemType Directory -Force $output | Out-Null
$sourcePath = Join-Path $root 'contracts\DocumentRegistry.sol'
$source = [IO.File]::ReadAllText($sourcePath)
$settings = @{evmVersion='cancun'; optimizer=@{enabled=$true; runs=200}; metadata=@{bytecodeHash='none'; appendCBOR=$false}; outputSelection=@{'*'=@{'*'=@('abi','evm.bytecode.object','evm.deployedBytecode.object')}}}
$inputData = @{language='Solidity'; sources=@{'DocumentRegistry.sol'=@{content=$source}}; settings=$settings}
$utf8 = [Text.UTF8Encoding]::new($false)
$inputPath = Join-Path $output 'input.json'
$outputPath = Join-Path $output 'output.json'
[IO.File]::WriteAllText($inputPath, ($inputData | ConvertTo-Json -Depth 30), $utf8)
$process = Start-Process -FilePath $executable -ArgumentList '--standard-json' -RedirectStandardInput $inputPath -RedirectStandardOutput $outputPath -RedirectStandardError (Join-Path $output 'stderr.log') -WindowStyle Hidden -PassThru
$null = $process.Handle # Preservar o handle para ExitCode tambem no Windows PowerShell 5.1.
if (-not $process.WaitForExit(30000)) { $process.Kill(); $process.WaitForExit(); throw 'Timeout solc.' }
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw 'Falha no processo solc.' }
$document = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
$errors = @($document.errors | Where-Object {$_.severity -eq 'error'})
if ($errors.Count -gt 0) { throw ($errors | ConvertTo-Json -Depth 10) }
$compiled = $document.contracts.'DocumentRegistry.sol'.DocumentRegistry
if (-not $compiled.evm.bytecode.object -or -not $compiled.evm.deployedBytecode.object -or -not $compiled.abi) { throw 'Contrato incompleto.' }
function Get-HexTextHash([string]$Text) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::ASCII.GetBytes($Text)))).Replace('-','').ToLowerInvariant() } finally { $algorithm.Dispose() }
}
$manifest = [ordered]@{compiler='0.8.37+commit.f401782d'; compilerSha256=$checksum; compilerUrl=$url; evmVersion='cancun'; optimizerRuns=200; metadata='none; appendCBOR=false'; sourceSha256=(Get-FileHash $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant(); creationHexSha256=(Get-HexTextHash $compiled.evm.bytecode.object); runtimeHexSha256=(Get-HexTextHash $compiled.evm.deployedBytecode.object)}
$artifact = [ordered]@{manifest=$manifest; abi=$compiled.abi; creationBytecode=$compiled.evm.bytecode.object; runtimeBytecode=$compiled.evm.deployedBytecode.object}
[IO.File]::WriteAllText((Join-Path $output 'DocumentRegistry.json'), ($artifact | ConvertTo-Json -Depth 30), $utf8)
$lockPath = Join-Path $root 'contracts\build.lock.json'
if (-not (Test-Path -LiteralPath $lockPath)) { throw 'Manifesto fixado contracts/build.lock.json ausente.' }
$expected = Get-Content $lockPath -Raw | ConvertFrom-Json
foreach ($property in $manifest.Keys) {
    if ($manifest[$property] -cne $expected.$property) { throw "Compilacao divergiu do manifesto: $property" }
}
Write-Output 'Contrato compilado e conferido com o manifesto fixado.'
