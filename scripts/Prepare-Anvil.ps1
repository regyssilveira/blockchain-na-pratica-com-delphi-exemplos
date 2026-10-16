[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root 'build\tools\anvil'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$archive = Join-Path $directory 'foundry.zip'
$url = 'https://github.com/foundry-rs/foundry/releases/download/v1.8.5/foundry_v1.8.5_win32_amd64.zip'
$expected = '21f86b563d87404a68481f513bf3e419780ee536307b89c658215ae6f8f5aa45'
if (-not (Test-Path -LiteralPath $archive)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive }
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Checksum do Anvil divergente. Remova somente o arquivo foundry.zip e repita.' }
# Reextrair do arquivo verificado evita confiar em um executavel local modificado.
Expand-Archive -LiteralPath $archive -DestinationPath $directory -Force
$executable = Join-Path $directory 'anvil.exe'
$version = & $executable --version
if ($LASTEXITCODE -ne 0 -or ($version -join "`n") -notmatch '51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f') { throw 'Versao inesperada do Anvil.' }
[pscustomobject]@{version='1.8.5'; commit='51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f'; url=$url; archiveSha256=$expected; executableSha256=(Get-FileHash $executable -Algorithm SHA256).Hash.ToLowerInvariant(); versionOutput=$version} | ConvertTo-Json | Set-Content (Join-Path $directory 'manifest.json') -Encoding UTF8
$version
