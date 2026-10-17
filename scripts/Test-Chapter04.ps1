[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $DelphiRoot 'bin\dcc64.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Compilador Win64 ausente.' }
$version = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
if ($version -notlike '37.*') { throw 'Exigido Delphi 13.' }
$library = Join-Path $DelphiRoot 'lib\win64\release'
if (-not (Test-Path -LiteralPath $library -PathType Container)) { throw 'Biblioteca Win64 ausente.' }
$outputRoot = Join-Path $projectRoot 'build\Chapter04.Start'
$unitOutput = Join-Path $outputRoot 'dcu'
New-Item -ItemType Directory -Path $unitOutput -Force | Out-Null
$arguments = @('--no-config','-B','-Q','-CC', '-NSSystem',
    "-U$library", "-E$outputRoot", "-NU$unitOutput",
    (Join-Path $projectRoot 'demos\Chapter04.Start.dpr'))
$arguments | Set-Content -LiteralPath (Join-Path $outputRoot 'compiler-arguments.txt') -Encoding UTF8
Push-Location (Join-Path $projectRoot 'demos')
try {
    & $compiler @arguments 2>&1 | Tee-Object -FilePath (Join-Path $outputRoot 'compile.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o exemplo inicial.' }
} finally { Pop-Location }
$process = Start-Process -FilePath (Join-Path $outputRoot 'Chapter04.Start.exe') `
    -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $outputRoot 'output.txt') `
    -RedirectStandardError (Join-Path $outputRoot 'stderr.txt')
$null = $process.Handle
if (-not $process.WaitForExit(15000)) {
    $process.Kill(); $process.WaitForExit()
    throw 'Prazo de execucao esgotado; validacao incompleta.'
}
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw 'O exemplo inicial terminou com erro.' }
$observed = @(Get-Content -LiteralPath (Join-Path $outputRoot 'output.txt'))
$expected = @('ambiente_delphi=pronto', 'bits_do_ponteiro=64')
if (($observed -join "`n") -cne ($expected -join "`n")) { throw 'Saida do exemplo inicial divergiu.' }
[pscustomobject]@{passed=$true; compiler=$version; target='Win64'; exitCode=$process.ExitCode;
    output=$observed; thirdPartyDependenciesRequired=$false; externalNodeRequired=$false} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'acceptance.json') -Encoding UTF8
$observed
Write-Output 'Capitulo 4: compilacao e execucao Win64 conferidas.'
