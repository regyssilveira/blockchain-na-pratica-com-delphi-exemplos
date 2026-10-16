[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DelphiRoot)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Test-Primitives.ps1') -DelphiRoot $DelphiRoot -Protocol
