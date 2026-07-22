[CmdletBinding()]
param(
  [string]$Serial = 'H8B4C19731000256',
  [string]$ModelPath = ''
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

  $outputPath = Join-Path $env:TEMP "nss-embedding-instrumentation-$([guid]::NewGuid()).out"
  $errorPath = Join-Path $env:TEMP "nss-embedding-instrumentation-$([guid]::NewGuid()).err"
  $process = Start-Process `
    -FilePath $AdbPath `
    -ArgumentList $ArgumentList `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outputPath `
    -RedirectStandardError $errorPath

  try {
    $applicationPid = ''
    $pidDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(15, $TimeoutSeconds))
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $pidDeadline) {
      $pidOutput = @(& $AdbPath -s $Serial shell pidof $PackageName 2>$null)
      $candidatePid = ($pidOutput -join ' ').Trim()
      if ($LASTEXITCODE -eq 0 -and $candidatePid -match '^\d+$') {
        $applicationPid = $candidatePid
        break
      }
      Start-Sleep -Milliseconds 100
    }

    try {
      Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
    }
    catch {
      if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      }
      foreach ($cleanupPackage in @($PackageName, "$PackageName.test")) {
        & $AdbPath -s $Serial shell am force-stop $cleanupPackage 2>$null | Out-Null
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
    if ([string]::IsNullOrWhiteSpace($applicationPid)) {
      throw "No PID found for $PackageName during instrumentation."
    }
    return [pscustomobject]@{
      ApplicationPid = $applicationPid
      Output = $output
    }
  }
  finally {
    Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-EmbeddingInstrumentationClass {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AdbPath,

    [Parameter(Mandatory = $true)]
    [string]$Serial,

    [Parameter(Mandatory = $true)]
    [string]$ClassName,

    [Parameter(Mandatory = $true)]
    [string]$DeviceModelPath,

    [Parameter(Mandatory = $true)]
    [int]$ExpectedTestCount,

    [Parameter(Mandatory = $true)]
    [int]$TimeoutSeconds
  )

  foreach ($package in @('com.example.note_secret_search', 'com.example.note_secret_search.test')) {
    Invoke-NativeCommand $AdbPath @('-s', $Serial, 'shell', 'am', 'force-stop', $package)
  }
  $result = Invoke-InstrumentationWithTimeout `
    -AdbPath $AdbPath `
    -Serial $Serial `
    -PackageName 'com.example.note_secret_search' `
    -TimeoutSeconds $TimeoutSeconds `
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
      $ClassName,
      '-e',
      'bgeModelPath',
      $DeviceModelPath,
      'com.example.note_secret_search.test/androidx.test.runner.AndroidJUnitRunner'
    )
  $result.Output | Write-Host
  $testLabel = if ($ExpectedTestCount -eq 1) { 'test' } else { 'tests' }
  if ($result.Output -notcontains "OK ($ExpectedTestCount $testLabel)") {
    throw "$ClassName did not report $ExpectedTestCount passing tests."
  }
  return $result
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$workspaceParent = Split-Path $repoRoot -Parent
if ((Split-Path $workspaceParent -Leaf) -eq 'worktrees') {
  $workspaceParent = Split-Path $workspaceParent -Parent
}
$cacheRoot = Join-Path $workspaceParent '.note_secret_search_quality_cache'
$expectedHash = '69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a'
if ([string]::IsNullOrWhiteSpace($ModelPath)) {
  $ModelPath = Join-Path $cacheRoot 'models\bge-small-zh-v1.5\model.onnx'
}
$ModelPath = (Resolve-Path -LiteralPath $ModelPath).Path
$actualHash = (Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
  throw "Pinned BGE checksum mismatch."
}

New-Item -ItemType Directory -Force -Path `
  (Join-Path $cacheRoot 'gradle'), `
  (Join-Path $cacheRoot 'tmp') | Out-Null
$env:GRADLE_USER_HOME = Join-Path $cacheRoot 'gradle'
$env:TEMP = Join-Path $cacheRoot 'tmp'
$env:TMP = Join-Path $cacheRoot 'tmp'
$env:ANDROID_SERIAL = $Serial

$adb = (Get-Command adb -ErrorAction Stop).Source
$mainApk = Join-Path $repoRoot 'build\app\outputs\apk\debug\app-debug.apk'
$testApk = Join-Path $repoRoot 'build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk'
$deviceDirectory = '/sdcard/Android/data/com.example.note_secret_search/files/phase5-embedding'
$modelPathSentinel = 'PHASE5_EMBEDDING_MODEL_PATH_SENTINEL_5D70A1'
$textSentinel = 'PHASE5_EMBEDDING_TEXT_SENTINEL_26C94B'
$deviceModelPath = "$deviceDirectory/$modelPathSentinel.onnx"

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

try {
  Invoke-NativeCommand $adb @('-s', $Serial, 'shell', 'mkdir', '-p', $deviceDirectory)
  Invoke-NativeCommand $adb @('-s', $Serial, 'push', $ModelPath, $deviceModelPath)

  Invoke-EmbeddingInstrumentationClass `
    -AdbPath $adb `
    -Serial $Serial `
    -ClassName 'com.example.note_secret_search.BgeEmbeddingRuntimeInstrumentationTest' `
    -DeviceModelPath $deviceModelPath `
    -ExpectedTestCount 3 `
    -TimeoutSeconds 420 | Out-Null

  Invoke-NativeCommand $adb @('-s', $Serial, 'logcat', '-c')
  $logResult = Invoke-EmbeddingInstrumentationClass `
    -AdbPath $adb `
    -Serial $Serial `
    -ClassName 'com.example.note_secret_search.EmbeddingSensitiveRuntimeLogInstrumentationTest' `
    -DeviceModelPath $deviceModelPath `
    -ExpectedTestCount 1 `
    -TimeoutSeconds 180

  $logcat = & $adb -s $Serial logcat -d --pid $logResult.ApplicationPid
  if ($LASTEXITCODE -ne 0) {
    throw "adb logcat --pid $($logResult.ApplicationPid) exited with code $LASTEXITCODE"
  }
  $forbiddenLogValues = @(
    $modelPathSentinel,
    $textSentinel,
    $expectedHash,
    '704, 3152, 3017, 5164',
    '0.007602385'
  )
  foreach ($forbidden in $forbiddenLogValues) {
    if ($logcat | Select-String -SimpleMatch $forbidden -Quiet) {
      throw "Sensitive embedding runtime value appeared in Logcat: $forbidden"
    }
  }
}
finally {
  & $adb -s $Serial shell rm -f $deviceModelPath 2>$null | Out-Null
}

Write-Host 'Phase 5 embedding runtime device gate passed.'
