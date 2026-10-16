[CmdletBinding()]
param(
    [ValidateSet('All','SimpleBaseLib4Pascal','HashLib4Pascal','CryptoLib4Pascal','DUnitX')][string]$Suite = 'All',
    [ValidateRange(1,120)][int]$TimeoutMinutes = 30
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$executables = [ordered]@{
    SimpleBaseLib4Pascal = 'SimpleBaseLib.Tests.exe'
    HashLib4Pascal = 'HashLib.Tests.exe'
    CryptoLib4Pascal = 'CryptoLib.Tests.exe'
    DUnitX = 'DUnitXTestProject.exe'
}
$results = @()
foreach ($name in $executables.Keys) {
    if ($Suite -ne 'All' -and $Suite -ne $name) { continue }
    $outputRoot = Join-Path $projectRoot "build\$name"
    $executable = Join-Path $outputRoot $executables[$name]
    if (-not (Test-Path -LiteralPath $executable)) { throw "Compile primeiro a suíte $name." }
    # Os carregadores dos vetores procuram os dados a partir do diretório corrente.
    $workingDirectory = Join-Path $projectRoot "dependencies\$name"
    if ($name -eq 'DUnitX') { $workingDirectory = Join-Path $workingDirectory 'Tests' }
    $stdout = Join-Path $outputRoot 'tests.log'
    $stderr = Join-Path $outputRoot 'tests.stderr.log'
    $parameters = @{
        FilePath = $executable
        WorkingDirectory = $workingDirectory
        WindowStyle = 'Hidden'
        RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr
        PassThru = $true
    }
    if ($name -eq 'DUnitX') {
        $xml = Join-Path $outputRoot 'results.xml'
        $parameters.ArgumentList = @(('"--xml:' + $xml + '"'), '--consolemode:quiet')
    }
    Write-Output "Executando $name; progresso em $stdout"
    $started = Get-Date
    $process = Start-Process @parameters
    $finished = $process.WaitForExit($TimeoutMinutes * 60000)
    if (-not $finished) {
        $process.Kill()
        $process.WaitForExit()
    } else {
        $process.WaitForExit()
    }
    $text = Get-Content -LiteralPath $stdout -Raw
    $errorText = Get-Content -LiteralPath $stderr -Raw
    $passed = $false
    if ($finished -and $process.ExitCode -eq 0) {
        if ($name -eq 'DUnitX') {
            $document = [xml](Get-Content -LiteralPath $xml -Raw)
            $passed = $document.'test-results'.failures -eq '0' -and $document.'test-results'.errors -eq '0'
        } else {
            # DUnit pode terminar com código zero mesmo havendo falhas.
            $passed = $text -match '(?m)^OK:\s+\d+ tests\s*$' -and [string]::IsNullOrWhiteSpace($errorText)
        }
    }
    $results += [pscustomobject]@{
        suite = $name
        started = $started.ToString('o')
        elapsedSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        exitCode = $process.ExitCode
        timedOut = -not $finished
        passed = $passed
        stdout = "build/$name/tests.log"
        stderr = "build/$name/tests.stderr.log"
    }
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $projectRoot 'build\execution-results.json') -Encoding UTF8
    Write-Output "$name : passed=$passed; exit=$($process.ExitCode)"
}
if (@($results | Where-Object {-not $_.passed}).Count -gt 0) {
    throw 'Há suíte reprovada ou incompleta. Consulte build/execution-results.json e os logs.'
}
