[CmdletBinding()]
param(
  [switch]$SkipAndroid,
  [switch]$SkipBuild,
  [switch]$PackageOnce,
  [string]$ArtifactOutputRoot = ''
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

function Resolve-GradleWrapper {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AndroidRoot
  )

  $wrapperName = if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    'gradlew.bat'
  }
  else {
    'gradlew'
  }
  $wrapper = Join-Path $AndroidRoot $wrapperName
  if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
    throw "Gradle wrapper not found: $wrapper"
  }
  if ($wrapperName -eq 'gradlew') {
    & chmod +x $wrapper
  }
  return $wrapper
}

function Invoke-AndroidGradle {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Tasks
  )

  $androidRoot = Join-Path $repoRoot 'android'
  $gradleWrapper = Resolve-GradleWrapper -AndroidRoot $androidRoot
  Push-Location $androidRoot
  try {
    Invoke-NativeCommand $gradleWrapper ($Tasks + @('--no-daemon', '--stacktrace'))
  }
  finally {
    Pop-Location
  }
}

function Copy-AndroidPackageArtifacts {
  param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot
  )

  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    return
  }
  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
  $paths = @(
    'build\app\outputs\flutter-apk\app-debug.apk',
    'build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk',
    'build\app\outputs\flutter-apk\app-release.apk',
    'build\app\outputs\bundle\release\app-release.aab'
  )
  foreach ($relativePath in $paths) {
    $source = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $source -PathType Leaf) {
      Copy-Item -LiteralPath $source -Destination $OutputRoot -Force
    }
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$prepareVersionScript = Join-Path $repoRoot 'scripts\quality\Prepare-FlutterAndroidVersion.ps1'
$artifactAuditScript = Join-Path $repoRoot 'scripts\quality\Invoke-AndroidArtifactAudit.ps1'
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
  Invoke-NativeCommand 'flutter' @('analyze', '--no-pub')
  Invoke-NativeCommand 'flutter' @('test', '--no-pub')

  if (-not $SkipAndroid -or -not $SkipBuild) {
    & $prepareVersionScript -RepoRoot $repoRoot
    if ($LASTEXITCODE -ne 0) {
      throw "$prepareVersionScript exited with code $LASTEXITCODE"
    }
  }

  if (-not $SkipAndroid) {
    Invoke-AndroidGradle @(':app:testDebugUnitTest')
  }

  if (-not $SkipBuild) {
    $packageTasks = @(
      ':app:assembleDebug',
      ':app:assembleDebugAndroidTest',
      ':app:assembleRelease',
      ':app:bundleRelease'
    )
    if (-not $PackageOnce) {
      Write-Host 'PackageOnce is the default Phase 9 packaging strategy; -PackageOnce is accepted for explicit local runs.'
    }
    Invoke-AndroidGradle $packageTasks
    & $artifactAuditScript `
      -RepoRoot $repoRoot `
      -DebugApkPath (Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-debug.apk') `
      -AndroidTestApkPath (Join-Path $repoRoot 'build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk') `
      -ReleaseApkPath (Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk') `
      -ReleaseAabPath (Join-Path $repoRoot 'build\app\outputs\bundle\release\app-release.aab')
    if ($LASTEXITCODE -ne 0) {
      throw "$artifactAuditScript exited with code $LASTEXITCODE"
    }
    Copy-AndroidPackageArtifacts -OutputRoot $ArtifactOutputRoot
  }
}
finally {
  Pop-Location
}
