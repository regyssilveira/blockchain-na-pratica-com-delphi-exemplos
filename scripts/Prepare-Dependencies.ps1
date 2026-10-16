[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'dependencies.lock.json') -Raw | ConvertFrom-Json
$dependencyRoot = Join-Path $projectRoot 'dependencies'
New-Item -ItemType Directory -Path $dependencyRoot -Force | Out-Null
foreach ($dependency in $lock.dependencies) {
    $destination = Join-Path $dependencyRoot $dependency.name
    if (-not (Test-Path -LiteralPath $destination)) {
        git init $destination
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao inicializar dependência.' }
        git -C $destination remote add origin $dependency.repository
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar origem.' }
        git -C $destination fetch --depth 1 origin $dependency.commit
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter revisão fixada.' }
        git -C $destination checkout --detach FETCH_HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Falha no checkout.' }
    }
    $actual = git -C $destination rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actual -ne $dependency.commit) {
        throw "Revisão divergente em $($dependency.name). Nenhum checkout existente será sobrescrito."
    }
    if ($dependency.name -eq 'Delphi-Mocks') {
        # Patch mínimo: a interface já importa System.Generics.Defaults.
        # A importação não qualificada na implementação duplica a unidade no Delphi 13.
        $source = Join-Path $destination 'Source\Delphi.Mocks.pas'
        $originalLines = @(git -C $destination show 'HEAD:Source/Delphi.Mocks.pas')
        if ($LASTEXITCODE -ne 0) { throw 'Não foi possível conferir fonte original Delphi-Mocks.' }
        $original = ($originalLines -join "`n").TrimEnd()
        $patched = [regex]::Replace($original, '(?m)^  Generics\.Defaults,\n', '')
        $current = ([IO.File]::ReadAllText($source).Replace("`r`n", "`n")).TrimEnd()
        if ($current -eq $original) {
            [IO.File]::WriteAllText($source, $patched.Replace("`n", "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
        } elseif ($current -ne $patched) {
            throw 'Delphi-Mocks contém alterações além do patch de compatibilidade esperado.'
        }
        $changedPaths = @(git -C $destination diff --name-only)
        if ($LASTEXITCODE -ne 0 -or @($changedPaths | Where-Object {$_ -ne 'Source/Delphi.Mocks.pas'}).Count -gt 0) {
            throw 'Alterações inesperadas em Delphi-Mocks.'
        }
    } else {
        $changes = git -C $destination status --porcelain --untracked-files=no
        if ($LASTEXITCODE -ne 0 -or $changes) { throw "Fontes modificados em $($dependency.name)." }
    }
    Write-Output "$($dependency.name): $actual"
}
