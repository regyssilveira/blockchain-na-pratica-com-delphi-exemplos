[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DelphiRoot,
    [ValidateSet('All','SimpleBaseLib4Pascal','HashLib4Pascal','CryptoLib4Pascal','DUnitX')][string]$Suite = 'All'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$dependencyRoot = Join-Path $projectRoot 'dependencies'
$compiler = Join-Path $DelphiRoot 'bin\dcc64.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Compilador Win64 não encontrado.' }
$compilerVersion = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
if ($compilerVersion -notlike '37.*') { throw "Exigido Delphi 13; encontrado $compilerVersion." }
& (Join-Path $PSScriptRoot 'Prepare-Dependencies.ps1')
$projects = [ordered]@{
    SimpleBaseLib4Pascal = 'SimpleBaseLib4Pascal\SimpleBaseLib.Tests\Delphi.Tests\SimpleBaseLib.Tests.dpr'
    HashLib4Pascal = 'HashLib4Pascal\HashLib.Tests\Delphi.Tests\HashLib.Tests.dpr'
    CryptoLib4Pascal = 'CryptoLib4Pascal\CryptoLib.Tests\Delphi.Tests\CryptoLib.Tests.dpr'
    DUnitX = 'DUnitX\Tests\DUnitXTestProject.dpr'
}
$sourceDirectories = @(Get-ChildItem -LiteralPath $dependencyRoot -Recurse -Filter '*.pas' -File |
    Where-Object { $_.FullName -notmatch '\\(Examples|Expert|ConstantTime|Benchmark|BuildConfig)\\' } |
    ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
$includeDirectories = @(
    (Join-Path $dependencyRoot 'DUnitX\Source'),
    (Join-Path $dependencyRoot 'DUnitX\Tests'),
    (Join-Path $dependencyRoot 'CryptoLib4Pascal\CryptoLib\src\Include'),
    (Join-Path $dependencyRoot 'HashLib4Pascal\HashLib\src\Include'),
    (Join-Path $dependencyRoot 'SimpleBaseLib4Pascal\SimpleBaseLib\src\Include')
)
foreach ($name in $projects.Keys) {
    if ($Suite -ne 'All' -and $Suite -ne $name) { continue }
    $project = Join-Path $dependencyRoot $projects[$name]
    $workingDirectory = Split-Path $project -Parent
    $outputRoot = Join-Path $projectRoot "build\$name"
    $unitOutput = Join-Path $outputRoot 'dcu'
    New-Item -ItemType Directory -Path $unitOutput -Force | Out-Null
    $baseUri = [Uri]($workingDirectory + '\')
    $relativeSources = @($sourceDirectories | ForEach-Object {
        [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]($_ + '\')).ToString()).Replace('/','\')
    })
    $unitPath = (@($relativeSources) + @((Join-Path $DelphiRoot 'lib\win64\release'))) -join ';'
    $arguments = @('--no-config','-B','-Q','-CC','-DCONSOLE_TESTRUNNER;CI',
        '-NSSystem;System.Win;Winapi;Vcl;Data;Xml',"-U$unitPath",
        ('-I' + ($includeDirectories -join ';')),"-E$outputRoot","-NU$unitOutput",$project)
    if (($arguments -join ' ').Length -gt 30000) { throw 'Caminho de busca excede limite do processo Windows.' }
    $arguments | Set-Content -LiteralPath (Join-Path $outputRoot 'compiler-arguments.txt') -Encoding UTF8
    Push-Location $workingDirectory
    try {
        & $compiler @arguments 2>&1 | Tee-Object -FilePath (Join-Path $outputRoot 'compile.log')
        $compileExit = $LASTEXITCODE
    } finally { Pop-Location }
    if ($compileExit -ne 0) { throw "Compilação de $name falhou: $compileExit. Consulte build/$name/compile.log." }
    Write-Output "Compilado: $name com Delphi $compilerVersion"
}
