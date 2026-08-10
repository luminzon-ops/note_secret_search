[CmdletBinding()]
param(
  [string]$Serial = 'H8B4C19731000256'
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

function Invoke-InstrumentationWithTimeout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AdbPath,

    [Parameter(Mandatory = $true)]
    [string]$Serial,

    [Parameter(Mandatory = $true)]
    [string]$PackageName,

    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,

    [Parameter(Mandatory = $true)]
    [int]$TimeoutSeconds
  )

  $outputPath = Join-Path $env:TEMP "nss-instrumentation-$([guid]::NewGuid()).out"
  $errorPath = Join-Path $env:TEMP "nss-instrumentation-$([guid]::NewGuid()).err"
  $process = Start-Process `
    -FilePath $AdbPath `
    -ArgumentList $ArgumentList `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outputPath `
    -RedirectStandardError $errorPath

  try {
    $appProcessId = ''
    $pidLookupDeadline = [DateTime]::UtcNow.AddSeconds(
      [Math]::Min(10, $TimeoutSeconds)
    )
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $pidLookupDeadline) {
      $pidOutput = @(
        & $AdbPath -s $Serial shell pidof $PackageName 2>$null
      )
      $pidExitCode = $LASTEXITCODE
      $candidatePid = ($pidOutput -join ' ').Trim()
      if ($pidExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidatePid)) {
        $appProcessId = $candidatePid
        break
      }
      Start-Sleep -Milliseconds 100
    }

    try {
      Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
    }
    catch {
      if (-not $process.HasExited) {
        try {
          Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
        }
      }
      foreach ($cleanupPackage in @($PackageName, "$PackageName.test")) {
        try {
          & $AdbPath -s $Serial shell am force-stop $cleanupPackage 2>$null |
            Out-Null
        }
        catch {
        }
      }
      throw "Instrumentation exceeded the ${TimeoutSeconds}s host timeout."
    }

    $output = @(Get-Content -LiteralPath $outputPath -ErrorAction SilentlyContinue)
    $errors = @(Get-Content -LiteralPath $errorPath -ErrorAction SilentlyContinue)
    if ($errors.Count -gt 0) {
      $errors | Write-Host
    }
    if ($process.ExitCode -ne 0) {
      throw "adb instrumentation exited with code $($process.ExitCode)"
    }
    if ([string]::IsNullOrWhiteSpace($appProcessId)) {
      throw "No PID found for $PackageName during instrumentation."
    }
    if ($appProcessId -notmatch '^\d+$') {
      throw "Expected one numeric PID for $PackageName, got: $appProcessId"
    }
    return [pscustomobject]@{
      ApplicationPid = $appProcessId
      Output = $output
    }
  }
  finally {
    Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cacheRoot = Join-Path (Split-Path $repoRoot -Parent) '.note_secret_search_quality_cache'
$env:GRADLE_USER_HOME = Join-Path $cacheRoot 'gradle'
$env:ANDROID_SERIAL = $Serial

$adb = (Get-Command adb -ErrorAction Stop).Source
$modelPathSentinel = 'PHASE1_MODEL_PATH_SENTINEL_91F37D'
$promptSentinel = 'PHASE1_PROMPT_SENTINEL_4B8C2A'
$mainApk = Join-Path $repoRoot 'build\app\outputs\apk\debug\app-debug.apk'
$testApk = Join-Path $repoRoot 'build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk'

Push-Location (Join-Path $repoRoot 'android')
try {
  Invoke-NativeCommand '.\gradlew.bat' @(
    ':app:assembleDebug',
    ':app:assembleDebugAndroidTest',
    '--no-daemon'
  )
}
finally {
  Pop-Location
}

foreach ($apk in @($mainApk, $testApk)) {
  if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
    throw "Expected APK was not produced: $apk"
  }
  Invoke-NativeCommand $adb @('-s', $Serial, 'install', '-r', $apk)
}

Invoke-NativeCommand $adb @(
  '-s',
  $Serial,
  'shell',
  'am',
  'force-stop',
  'com.example.note_secret_search'
)
Invoke-NativeCommand $adb @(
  '-s',
  $Serial,
  'shell',
  'am',
  'force-stop',
  'com.example.note_secret_search.test'
)
Invoke-NativeCommand $adb @('-s', $Serial, 'logcat', '-c')

$instrumentationFailure = $null
$instrumentationOutput = @()
try {
  $instrumentationResult = Invoke-InstrumentationWithTimeout `
    -AdbPath $adb `
    -Serial $Serial `
    -PackageName 'com.example.note_secret_search' `
    -TimeoutSeconds 120 `
    -ArgumentList @(
      '-s',
      $Serial,
      'shell',
      'am',
      'instrument',
      '-w',
      '-r',
      '-e',
      'class',
      'com.example.note_secret_search.SensitiveRuntimeLogInstrumentationTest',
      'com.example.note_secret_search.test/androidx.test.runner.AndroidJUnitRunner'
    )
  $instrumentationOutput = @($instrumentationResult.Output)
  $appProcessId = $instrumentationResult.ApplicationPid
  $instrumentationOutput | Write-Host
  if ($instrumentationOutput -notcontains 'OK (1 test)') {
    throw 'Sensitive runtime instrumentation did not report a passing test.'
  }
}
catch {
  $instrumentationFailure = $_
}

if ($instrumentationFailure -ne $null) {
  throw $instrumentationFailure
}

$logcat = & $adb -s $Serial logcat -d --pid $appProcessId
if ($LASTEXITCODE -ne 0) {
  throw "adb logcat --pid $appProcessId exited with code $LASTEXITCODE"
}

$forbiddenLogValues = @(
  $modelPathSentinel,
  $promptSentinel,
  'RNLlamaContext',
  'CPU features:',
  'Primary ABI:'
)

foreach ($forbidden in $forbiddenLogValues) {
  if ($logcat | Select-String -SimpleMatch $forbidden -Quiet) {
    throw "Sensitive runtime value appeared in Logcat: $forbidden"
  }
}

Write-Host 'Sensitive runtime Logcat smoke check passed.'
