[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$dependency = Join-Path $projectRoot 'dependencies\DUnitX'
$logger = Join-Path $dependency 'Source\DUnitX.Loggers.Xml.NUnit.pas'
$outputRoot = Join-Path $projectRoot 'build\DUnitX'
& (Join-Path $PSScriptRoot 'Build-UpstreamSuites.ps1') -DelphiRoot $DelphiRoot -Suite DUnitX
& (Join-Path $PSScriptRoot 'Run-UpstreamSuites.ps1') -Suite DUnitX
$originalBytes = [IO.File]::ReadAllBytes($logger)
$originalText = [IO.File]::ReadAllText($logger)
$needle = "FFormatSettings.DecimalSeparator := '.';"
if ([regex]::Matches($originalText, [regex]::Escape($needle)).Count -ne 1) {
    throw 'Logger não corresponde ao alvo conhecido da mutação.'
}
$detected = $false
try {
    # Mutação deliberadamente incorreta; nunca publicada como patch da biblioteca.
    $mutation = $originalText.Replace($needle, "FFormatSettings.DecimalSeparator := ',';")
    [IO.File]::WriteAllText($logger, $mutation, [Text.UTF8Encoding]::new($false))
    $compiler = Join-Path $DelphiRoot 'bin\dcc64.exe'
    $arguments = @(Get-Content -LiteralPath (Join-Path $outputRoot 'compiler-arguments.txt'))
    Push-Location (Join-Path $dependency 'Tests')
    try {
        & $compiler @arguments 2>&1 | Set-Content -LiteralPath (Join-Path $outputRoot 'mutation-compile.log')
        if ($LASTEXITCODE -ne 0) { throw 'Mutação não compilou; isso não comprova detecção pelo teste.' }
    } finally { Pop-Location }
    $runFailed = $false
    try {
        & (Join-Path $PSScriptRoot 'Run-UpstreamSuites.ps1') -Suite DUnitX
    } catch {
        $runFailed = $true
    }
    $resultsFile = Join-Path $outputRoot 'results.xml'
    $document = [xml](Get-Content -LiteralPath $resultsFile -Raw)
    $cases = @($document.SelectNodes('//test-case') | Where-Object {
        $_.name -like '*OnTestingEnds_Writes_The_Assembly_Time_As_A_Duration.*'
    })
    $detected = $runFailed -and $cases.Count -eq 4 -and
        @($cases | Where-Object {$_.result -eq 'Failure'}).Count -eq 4
    Copy-Item -LiteralPath $resultsFile -Destination (Join-Path $outputRoot 'mutation-results.xml')
    Copy-Item -LiteralPath (Join-Path $outputRoot 'tests.log') -Destination (Join-Path $outputRoot 'mutation-tests.log')
} finally {
    [IO.File]::WriteAllBytes($logger, $originalBytes)
    & (Join-Path $PSScriptRoot 'Build-UpstreamSuites.ps1') -DelphiRoot $DelphiRoot -Suite DUnitX
    & (Join-Path $PSScriptRoot 'Run-UpstreamSuites.ps1') -Suite DUnitX
}
if (-not $detected) { throw 'Os quatro cenários não detectaram a mutação esperada.' }
$hashAlgorithm = [Security.Cryptography.SHA256]::Create()
try {
    $originalHash = ([BitConverter]::ToString($hashAlgorithm.ComputeHash($originalBytes))).Replace('-','')
} finally {
    $hashAlgorithm.Dispose()
}
$restored = (Get-FileHash -LiteralPath $logger -Algorithm SHA256).Hash -eq $originalHash
if (-not $restored) { throw 'A integridade do logger restaurado não foi confirmada.' }
[pscustomobject]@{
    mutationDetected = $true
    failedRegressionCasesDuringMutation = 4
    originalLoggerRestored = $restored
    finalSuiteApproved = $true
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'locale-regression.json') -Encoding UTF8
Write-Output 'Regressão validada: quatro casos detectaram a mutação; logger original restaurado e suíte aprovada.'
