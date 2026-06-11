param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Workspace = Resolve-Path (Join-Path $Root "../..")
$Output = Join-Path $Workspace "outputs/windows"
$PublishDir = Join-Path $Output $Runtime

New-Item -ItemType Directory -Force -Path $Output | Out-Null

$selfContained = (-not $FrameworkDependent).ToString().ToLowerInvariant()
dotnet publish $Root `
    -c Release `
    -r $Runtime `
    --self-contained:$selfContained `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $PublishDir

$zipPath = Join-Path $Output "CartoonCursor-$Runtime.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $PublishDir "*") -DestinationPath $zipPath

Write-Host $PublishDir
Write-Host $zipPath
