[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot, [switch]$Protocol, [switch]$Anvil, [switch]$BuildDemo, [switch]$BuildCli, [switch]$Didactic, [switch]$BuildDidacticNode, [switch]$BuildDidacticCli, [switch]$BuildDidacticScenario, [switch]$BuildSignaturesDemo, [switch]$BuildTransactionsDemo, [switch]$BuildEnvironmentDemo, [switch]$BuildRegistryDesktop, [switch]$BuildRegistryAcceptance, [switch]$Security, [switch]$BuildSecurityDemo, [switch]$BuildReceiptLossDemo, [switch]$BuildTraceDemo, [switch]$BuildRpcDemo)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $DelphiRoot 'bin\dcc64.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Compilador Win64 ausente.' }
$version = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
if ($version -notlike '37.*') { throw 'Exigido Delphi 13.' }
& (Join-Path $PSScriptRoot 'Prepare-Dependencies.ps1')
$buildProgram = $BuildRpcDemo -or $BuildTraceDemo -or $BuildReceiptLossDemo -or $BuildSecurityDemo -or $BuildRegistryDesktop -or $BuildRegistryAcceptance -or $BuildEnvironmentDemo -or $BuildTransactionsDemo -or $BuildSignaturesDemo -or $BuildDemo -or $BuildCli -or $BuildDidacticNode -or $BuildDidacticCli -or $BuildDidacticScenario
$projectName = if ($BuildRpcDemo) { 'Chapter15.Read' } elseif ($BuildTraceDemo) { 'Chapter17.Trace' } elseif ($BuildReceiptLossDemo) { 'Chapter19.ReceiptLoss' } elseif ($BuildSecurityDemo) { 'Chapter19.Security' } elseif ($Security) { 'Security' } elseif ($BuildRegistryDesktop) { 'Chapter18.Desktop' } elseif ($BuildRegistryAcceptance) { 'Chapter18.Acceptance' } elseif ($BuildEnvironmentDemo) { 'Chapter14.Environment' } elseif ($BuildTransactionsDemo) { 'Chapter07.Transactions' } elseif ($BuildSignaturesDemo) { 'Chapter06.Signatures' } elseif ($BuildDidacticScenario) { 'Didactic.Scenario' } elseif ($BuildDidacticNode) { 'Didactic.Node' } elseif ($BuildDidacticCli) { 'Didactic.Cli' } elseif ($Didactic) { 'Didactic' } elseif ($BuildCli) { 'DocumentRegistry.Cli' } elseif ($BuildDemo) { 'DocumentRegistry.Demo' } elseif ($Anvil) { 'Anvil' } elseif ($Protocol) { 'Protocol' } else { 'Primitives' }
$outputRoot = Join-Path $projectRoot "build\$projectName"
$unitOutput = Join-Path $outputRoot 'dcu'
New-Item -ItemType Directory -Path $unitOutput -Force | Out-Null
$dependencyRoot = Join-Path $projectRoot 'dependencies'
$directories = @(
    (Join-Path $projectRoot 'src'),
    (Join-Path $dependencyRoot 'DUnitX\Source')
) + @(Get-ChildItem -LiteralPath $dependencyRoot -Recurse -Filter '*.pas' -File |
    Where-Object {$_.FullName -match '\\(CryptoLib|HashLib|SimpleBaseLib)\\src\\'} |
    ForEach-Object {$_.DirectoryName} | Sort-Object -Unique)
$workingDirectory = Join-Path $projectRoot $(if ($buildProgram) { 'demos' } else { 'tests' })
$projectFile = if ($buildProgram) { "$projectName.dpr" } else { "$projectName.Tests.dpr" }
$baseUri = [Uri]($workingDirectory + '\')
$relative = @($directories | ForEach-Object {
    [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]($_ + '\')).ToString()).Replace('/','\')
})
$includePath = @(
    (Join-Path $dependencyRoot 'DUnitX\Source'),
    (Join-Path $dependencyRoot 'CryptoLib4Pascal\CryptoLib\src\Include'),
    (Join-Path $dependencyRoot 'HashLib4Pascal\HashLib\src\Include'),
    (Join-Path $dependencyRoot 'SimpleBaseLib4Pascal\SimpleBaseLib\src\Include')
) -join ';'
$unitPath = (@($relative) + @((Join-Path $DelphiRoot 'lib\win64\release'))) -join ';'
$subsystem = if ($BuildRegistryDesktop) { '-CG' } else { '-CC' }
$arguments = @('--no-config','-B','-Q',$subsystem,'-DCI',
    '-NSSystem;System.Win;Winapi;Vcl;Data;Xml',"-U$unitPath","-I$includePath",
    "-E$outputRoot","-NU$unitOutput",(Join-Path $workingDirectory $projectFile))
if (($arguments -join ' ').Length -gt 30000) { throw 'Caminhos excedem o limite de comando Windows.' }
$arguments | Set-Content -LiteralPath (Join-Path $outputRoot 'compiler-arguments.txt') -Encoding UTF8
Push-Location $workingDirectory
try {
    & $compiler @arguments 2>&1 | Tee-Object -FilePath (Join-Path $outputRoot 'compile.log')
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar os testes $projectName." }
} finally { Pop-Location }
if ($buildProgram) { return }
$xmlPath = Join-Path $outputRoot 'results.xml'
$process = Start-Process -FilePath (Join-Path $outputRoot "$projectName.Tests.exe") `
    -ArgumentList @(('"--xml:' + $xmlPath + '"'), '--consolemode:quiet') `
    -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $outputRoot 'tests.log') `
    -RedirectStandardError (Join-Path $outputRoot 'tests.stderr.log')
$null = $process.Handle
if (-not $process.WaitForExit(60000)) {
    $process.Kill()
    $process.WaitForExit()
    throw "Tempo limite $projectName excedido; teste incompleto."
}
$process.WaitForExit()
$document = [xml](Get-Content -LiteralPath $xmlPath -Raw)
$root = $document.'test-results'
$passed = $process.ExitCode -eq 0 -and [int]$root.total -gt 0 -and
    [int]$root.failures -eq 0 -and [int]$root.errors -eq 0 -and [int]$root.ignored -eq 0
[pscustomobject]@{
    compiler = $version
    target = 'Win64'
    executed = [int]$root.total
    failures = [int]$root.failures
    errors = [int]$root.errors
    ignored = [int]$root.ignored
    exitCode = $process.ExitCode
    passed = $passed
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'summary.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $outputRoot 'tests.log') | Select-Object -Last 10
if (-not $passed) { throw "Testes $projectName reprovados. Consulte build/$projectName." }
