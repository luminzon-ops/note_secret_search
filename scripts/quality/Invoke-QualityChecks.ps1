[CmdletBinding()]
param(
  [switch]$SkipAndroid,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [string[]]$ArgumentList = @()
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath exited with code $LASTEXITCODE"
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$workspaceParent = Split-Path $repoRoot -Parent
if ((Split-Path $workspaceParent -Leaf) -eq 'worktrees') {
  $workspaceParent = Split-Path $workspaceParent -Parent
}
$cacheRoot = Join-Path $workspaceParent '.note_secret_search_quality_cache'

New-Item -ItemType Directory -Force -Path `
  (Join-Path $cacheRoot 'gradle'), `
  (Join-Path $cacheRoot 'pub'), `
  (Join-Path $cacheRoot 'tmp') | Out-Null

$env:GRADLE_USER_HOME = Join-Path $cacheRoot 'gradle'
$env:PUB_CACHE = Join-Path $cacheRoot 'pub'
$env:TEMP = Join-Path $cacheRoot 'tmp'
$env:TMP = Join-Path $cacheRoot 'tmp'

Push-Location $repoRoot
try {
  Invoke-NativeCommand 'flutter' @('pub', 'get', '--enforce-lockfile')
  Invoke-NativeCommand 'flutter' @('analyze')
  Invoke-NativeCommand 'flutter' @('test')

  if (-not $SkipAndroid) {
    Push-Location (Join-Path $repoRoot 'android')
    try {
      Invoke-NativeCommand '.\gradlew.bat' @(':app:testDebugUnitTest', '--no-daemon')
    }
    finally {
      Pop-Location
    }
  }

  if (-not $SkipBuild) {
    Invoke-NativeCommand 'flutter' @('build', 'apk', '--debug')
  }
}
finally {
  Pop-Location
}
