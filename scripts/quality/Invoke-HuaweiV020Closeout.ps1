[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Serial,
  [Parameter(Mandatory = $true)]
  [string]$ExpectedManufacturer,
  [Parameter(Mandatory = $true)]
  [string]$ExpectedModel,
  [Parameter(Mandatory = $true)]
  [string]$DebugApkPath,
  [Parameter(Mandatory = $true)]
  [string]$AndroidTestApkPath,
  [Parameter(Mandatory = $true)]
  [string]$BgeModelPath,
  [Parameter(Mandatory = $true)]
  [string]$BackupRoot,
  [Parameter(Mandatory = $true)]
  [string]$ExpectedVersionName,
  [Parameter(Mandatory = $true)]
  [int]$ExpectedVersionCode,
  [Parameter(Mandatory = $true)]
  [string]$ExpectedCertSha256
)

$ErrorActionPreference = 'Stop'

$packageName = 'com.example.note_secret_search'
$testPackageName = "$packageName.test"
$allowedSerial = 'H8B4C19731000256'
$allowedManufacturer = 'HUAWEI'
$allowedModel = 'SPN-AL00'
$commonScript = Join-Path $PSScriptRoot 'HuaweiV020Closeout.Common.ps1'
. $commonScript

function Assert-TarArchive {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $tar = (Get-Command tar -ErrorAction Stop).Source
  $listingPath = "$Path.list.txt"
  $errorPath = "$Path.list.err"
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $tar -tf $Path > $listingPath 2> $errorPath
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    $errorText = Get-Content -LiteralPath $errorPath -Raw `
      -ErrorAction SilentlyContinue
    throw "tar archive validation failed: $errorText"
  }
  Assert-Condition `
    -Condition ((Get-Item -LiteralPath $listingPath).Length -gt 0) `
    -Message 'Tar archive listing is empty.'
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
  return $listingPath
}

if ([string]::IsNullOrWhiteSpace($Serial) -or $Serial -ne $allowedSerial) {
  throw "Huawei closeout only allows serial $allowedSerial."
}
Assert-Condition `
  -Condition ($ExpectedManufacturer.ToUpperInvariant() -eq $allowedManufacturer) `
  -Message 'ExpectedManufacturer must be HUAWEI.'
Assert-Condition `
  -Condition ($ExpectedModel -eq $allowedModel) `
  -Message 'ExpectedModel must be SPN-AL00.'
Assert-Condition `
  -Condition ($ExpectedVersionName -eq '0.2.0' -and $ExpectedVersionCode -eq 2) `
  -Message 'This closeout gate is fixed to Note Secret Search 0.2.0+2.'
$ExpectedCertSha256 = $ExpectedCertSha256.Replace(':', '').ToLowerInvariant()
Assert-Condition `
  -Condition ($ExpectedCertSha256 -match '^[0-9a-f]{64}$') `
  -Message 'ExpectedCertSha256 must be a 64-character SHA-256 digest.'

$adb = (Get-Command adb -ErrorAction Stop).Source
$aapt = Resolve-AndroidTool -ToolName 'aapt'
$apksigner = Resolve-AndroidTool -ToolName 'apksigner'
$debugApk = Resolve-PathChecked -Path $DebugApkPath -Label 'Debug APK'
$testApk = Resolve-PathChecked -Path $AndroidTestApkPath -Label 'Android test APK'
$bgeModel = Resolve-PathChecked -Path $BgeModelPath -Label 'BGE model'
Assert-ApkContract -ApkPath $debugApk -ExpectedPackage $packageName | Out-Null
$testMetadata = Get-ApkMetadata -ApkPath $testApk
Assert-Condition `
  -Condition ($testMetadata.PackageName -eq $testPackageName) `
  -Message "Android test APK package mismatch: $($testMetadata.PackageName)"

$expectedBackupParent = 'E:\Archive\Flutter\.note_secret_search_device_backups'
Assert-Condition `
  -Condition (([IO.Path]::GetFullPath($BackupRoot)).TrimEnd('\') -eq
    $expectedBackupParent) `
  -Message "BackupRoot must be $expectedBackupParent."
New-Item -ItemType Directory -Force -Path $expectedBackupParent | Out-Null
$backupParent = (Resolve-Path -LiteralPath $expectedBackupParent).Path
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
Invoke-NativeChecked -FilePath 'icacls' -ArgumentList @(
  $backupParent,
  '/inheritance:r',
  '/grant:r',
  ($currentUser + ':(OI)(CI)F')
) | Out-Null
$backupPath = Join-Path $backupParent (
  (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
)
while (Test-Path -LiteralPath $backupPath) {
  Start-Sleep -Seconds 1
  $backupPath = Join-Path $backupParent (
    (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
  )
}

$deviceIdentity = Assert-DeviceIdentity
$backup = Backup-DeviceState -Destination $backupPath
$deviceTempModelPath = ''
$testInstalled = $false
try {
  Invoke-Adb @('install', '-r', $debugApk) | Out-Null
  Invoke-Adb @('install', '-r', $testApk) | Out-Null
  $testInstalled = $true

  Invoke-InstrumentationClass `
    -ClassName "$packageName.ReleaseReadinessSmokeInstrumentationTest" `
    -ExpectedTestCount 1 `
    -TimeoutSeconds 180 | Out-Null

  $deviceDirectory = "/sdcard/Android/data/$packageName/files/v020-closeout"
  $deviceTempModelPath = "$deviceDirectory/BGE_CLOSEOUT_MODEL.onnx"
  Invoke-Adb @('shell', 'mkdir', '-p', $deviceDirectory) | Out-Null
  Invoke-Adb @('push', $bgeModel, $deviceTempModelPath) | Out-Null
  Invoke-InstrumentationClass `
    -ClassName "$packageName.BgeEmbeddingRuntimeInstrumentationTest" `
    -ExpectedTestCount 3 `
    -TimeoutSeconds 420 `
    -ExtraArguments @('-e', 'bgeModelPath', $deviceTempModelPath) | Out-Null

  Invoke-Adb @('logcat', '-c') | Out-Null
  $embeddingLog = Invoke-InstrumentationClass `
    -ClassName "$packageName.EmbeddingSensitiveRuntimeLogInstrumentationTest" `
    -ExpectedTestCount 1 `
    -TimeoutSeconds 240 `
    -ExtraArguments @('-e', 'bgeModelPath', $deviceTempModelPath) `
    -RequireApplicationPid
  Assert-LogcatClean `
    -ApplicationPid $embeddingLog.ApplicationPid `
    -ForbiddenValues @(
      'PHASE5_EMBEDDING_MODEL_PATH_SENTINEL_5D70A1',
      'PHASE5_EMBEDDING_TEXT_SENTINEL_26C94B',
      '69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a'
    )

  Invoke-Adb @('logcat', '-c') | Out-Null
  $llmLog = Invoke-InstrumentationClass `
    -ClassName "$packageName.SensitiveRuntimeLogInstrumentationTest" `
    -ExpectedTestCount 1 `
    -TimeoutSeconds 420 `
    -RequireApplicationPid
  Assert-LogcatClean `
    -ApplicationPid $llmLog.ApplicationPid `
    -ForbiddenValues @(
      'PHASE1_MODEL_PATH_SENTINEL_91F37D',
      'PHASE1_PROMPT_SENTINEL_4B8C2A',
      'RNLlamaContext',
      'CPU features:',
      'Primary ABI:'
    )

  Invoke-Adb @(
    'shell',
    'monkey',
    '-p',
    $packageName,
    '-c',
    'android.intent.category.LAUNCHER',
    '1'
  ) | Out-Null
  Start-Sleep -Seconds 2
  Invoke-Adb @('shell', 'am', 'force-stop', $packageName) | Out-Null
  Invoke-Adb @(
    'shell',
    'monkey',
    '-p',
    $packageName,
    '-c',
    'android.intent.category.LAUNCHER',
    '1'
  ) | Out-Null
  Invoke-Adb @('shell', 'input', 'keyevent', '224') | Out-Null
  Invoke-Adb @('shell', 'wm', 'dismiss-keyguard') | Out-Null
  $keyguard = Invoke-AdbText @('shell', 'dumpsys', 'window')
  if ($keyguard -match 'mShowingLockscreen=true|isStatusBarKeyguard=true') {
    Write-Host 'Manual confirmation required: unlock Huawei, then press Enter.'
    $null = Read-Host
    Invoke-Adb @('shell', 'wm', 'dismiss-keyguard') | Out-Null
    $keyguard = Invoke-AdbText @('shell', 'dumpsys', 'window')
    Assert-Condition `
      -Condition ($keyguard -notmatch 'mShowingLockscreen=true|isStatusBarKeyguard=true') `
      -Message 'Huawei remains locked after manual confirmation.'
  }

  $afterInventory = Get-DeviceInventory
  Save-Json -Value $afterInventory `
    -Path (Join-Path $backupPath 'device-files-after.json')
  $beforeModels = Get-ModelInventory -Inventory $backup.Inventory
  $afterModels = Get-ModelInventory -Inventory $afterInventory
  Assert-Condition `
    -Condition (($beforeModels | ConvertTo-Json -Compress) -eq
      ($afterModels | ConvertTo-Json -Compress)) `
    -Message 'Huawei user model inventory changed during upgrade.'

  $installedAfterPath = Join-Path $backupPath 'installed-after.apk'
  $installedAfterRemote = Invoke-AdbText @('shell', 'pm', 'path', $packageName)
  Assert-Condition `
    -Condition ($installedAfterRemote -match '^package:(.+)$') `
    -Message 'Installed Huawei package path is missing after upgrade.'
  Invoke-Adb @('pull', $matches[1], $installedAfterPath) | Out-Null
  Assert-ApkContract -ApkPath $installedAfterPath -ExpectedPackage $packageName |
    Out-Null
  $installedAfterDigest = Get-CertificateDigest -ApkPath $installedAfterPath
  Assert-Condition `
    -Condition ($installedAfterDigest -eq $ExpectedCertSha256) `
    -Message "Installed Huawei certificate changed: $installedAfterDigest"

  Save-Json -Value ([ordered]@{
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    device = $deviceIdentity
    package = $packageName
    versionName = $ExpectedVersionName
    versionCode = $ExpectedVersionCode
    certificateSha256 = $installedAfterDigest
    modelFiles = $afterModels
    backupPath = $backupPath
  }) -Path (Join-Path $backupPath 'closeout-result.json')
  Write-Host "Huawei v0.2.0+2 closeout passed. Backup: $backupPath"
}
finally {
  if (-not [string]::IsNullOrWhiteSpace($deviceTempModelPath)) {
    & $adb -s $Serial shell rm -f $deviceTempModelPath 2>$null | Out-Null
  }
  if ($testInstalled) {
    & $adb -s $Serial uninstall $testPackageName 2>$null | Out-Null
  }
}
