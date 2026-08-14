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
$commonScript = Join-Path $PSScriptRoot 'HuaweiReleaseCloseout.Common.ps1'
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
function Assert-ExtractedBackupMatchesInventory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TarPath,
    [Parameter(Mandatory = $true)]
    [object[]]$Inventory,
    [Parameter(Mandatory = $true)]
    [string]$Destination
  )
  $extractRoot = Join-Path ([IO.Path]::GetTempPath()) `
    "nss-private-backup-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
  try {
    Invoke-NativeChecked -FilePath 'tar' -ArgumentList @(
      '-xf', $TarPath, '-C', $extractRoot
    )
    $extracted = @(
      Get-ChildItem -LiteralPath $extractRoot -File -Recurse |
        ForEach-Object {
          [pscustomobject]@{
            path = ([IO.Path]::GetRelativePath(
              $extractRoot,
              $_.FullName
            )).Replace('\', '/')
            bytes = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).
              Hash.ToLowerInvariant()
          }
        } | Sort-Object path
    )
    $expected = @(
      $Inventory |
        ForEach-Object {
          [pscustomobject]@{
            path = [string]$_.path
            bytes = [int64]$_.bytes
            sha256 = ([string]$_.sha256).ToLowerInvariant()
          }
        } | Sort-Object path
    )
    Save-Json -Value $extracted `
      -Path (Join-Path $Destination 'device-files-extracted.json')
    $expectedJson = ConvertTo-Json -InputObject $expected -Depth 5 -Compress
    $extractedJson = ConvertTo-Json -InputObject $extracted -Depth 5 -Compress
    Assert-Condition `
      -Condition ($expectedJson -ceq $extractedJson) `
      -Message 'Extracted private backup does not match the device inventory.'
  }
  finally {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force `
      -ErrorAction SilentlyContinue
  }
}
function Get-UiHierarchy {
  $remotePath = '/sdcard/nss-window-dump.xml'
  $localPath = Join-Path $env:TEMP "nss-ui-$([guid]::NewGuid()).xml"
  try {
    Invoke-Adb @('shell', 'uiautomator', 'dump', '--compressed', $remotePath) |
      Out-Null
    Invoke-Adb @('pull', $remotePath, $localPath) | Out-Null
    return [xml](Get-Content -LiteralPath $localPath -Raw)
  }
  finally {
    Remove-Item -LiteralPath $localPath -Force -ErrorAction SilentlyContinue
    & $adb -s $Serial shell rm -f $remotePath 2>$null | Out-Null
  }
}
function Find-UiTextNode {
  param([Parameter(Mandatory = $true)][string]$Text)
  $hierarchy = Get-UiHierarchy
  return @($hierarchy.SelectNodes('//node')) | Where-Object {
    ([string]$_.text).Contains($Text) -or
      ([string]$_.'content-desc').Contains($Text)
  } | Select-Object -First 1
}
function Wait-UiText {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [int]$TimeoutSeconds = 30
  )
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      $node = Find-UiTextNode -Text $Text
      if ($null -ne $node) {
        return $node
      }
    }
    catch {
      $node = $null
    }
    Start-Sleep -Milliseconds 500
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Huawei UI text did not appear: $Text"
}
function Tap-UiText {
  param([Parameter(Mandatory = $true)][string]$Text)
  $node = Wait-UiText -Text $Text
  $bounds = [regex]::Match($node.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
  Assert-Condition $bounds.Success "Unable to parse UI bounds for: $Text"
  $x = ([int]$bounds.Groups[1].Value + [int]$bounds.Groups[3].Value) / 2
  $y = ([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value) / 2
  Invoke-Adb @('shell', 'input', 'tap', [int]$x, [int]$y) | Out-Null
}
function Ensure-HuaweiInteractive {
  Invoke-Adb @('shell', 'input', 'keyevent', '224') | Out-Null
  Invoke-Adb @('shell', 'wm', 'dismiss-keyguard') | Out-Null
  $deadline = [DateTime]::UtcNow.AddMinutes(10)
  $prompted = $false
  do {
    Invoke-Adb @('shell', 'input', 'keyevent', '224') | Out-Null
    Invoke-Adb @('shell', 'wm', 'dismiss-keyguard') | Out-Null
    $window = Invoke-AdbText @('shell', 'dumpsys', 'window')
    if ($window -notmatch 'mShowingLockscreen=true|isStatusBarKeyguard=true') {
      return
    }
    if (-not $prompted) {
      Write-Host 'MANUAL_UNLOCK_REQUIRED:huawei'
      $prompted = $true
    }
    Start-Sleep -Seconds 2
  } while ([DateTime]::UtcNow -lt $deadline)
  throw 'Huawei remains behind the system keyguard.'
}
function Start-MainApplication {
  Ensure-HuaweiInteractive
  Invoke-Adb @('shell', 'am', 'force-stop', $packageName) | Out-Null
  Invoke-Adb @(
    'shell', 'monkey', '-p', $packageName,
    '-c', 'android.intent.category.LAUNCHER', '1'
  ) | Out-Null
  Start-Sleep -Seconds 1
  Ensure-HuaweiInteractive
}
function Assert-BiometricHotfixFlow {
  param([Parameter(Mandatory = $true)][string]$EvidencePath)
  Invoke-Adb @('logcat', '-c') | Out-Null
  Start-MainApplication
  Wait-UiText -Text '应用已锁定' | Out-Null
  Assert-Condition `
    -Condition ($null -eq (Find-UiTextNode -Text 'NSS_PRIVACY_SHIELD_ACTIVE')) `
    -Message 'Huawei privacy shield still covers the lock screen.'
  Tap-UiText -Text '使用生物识别解锁'
  Start-Sleep -Seconds 1
  Invoke-Adb @('shell', 'input', 'keyevent', '4') | Out-Null
  Wait-UiText -Text '身份验证已取消' | Out-Null
  Wait-UiText -Text '应用已锁定' | Out-Null
  Assert-Condition `
    -Condition ($null -eq (Find-UiTextNode -Text 'NSS_PRIVACY_SHIELD_ACTIVE')) `
    -Message 'Huawei privacy shield remained after authentication cancellation.'
  Tap-UiText -Text '使用生物识别解锁'
  Write-Host 'FINGERPRINT_REQUIRED:first-unlock'
  Wait-UiText -Text '保险库' -TimeoutSeconds 60 | Out-Null
  Assert-Condition `
    -Condition ($null -eq (Find-UiTextNode -Text 'NSS_PRIVACY_SHIELD_ACTIVE')) `
    -Message 'Huawei privacy shield still covers the vault after fingerprint unlock.'
  Start-MainApplication
  Wait-UiText -Text '应用已锁定' | Out-Null
  Tap-UiText -Text '使用生物识别解锁'
  Write-Host 'FINGERPRINT_REQUIRED:cold-start-unlock'
  Wait-UiText -Text '保险库' -TimeoutSeconds 60 | Out-Null
  Assert-Condition `
    -Condition ($null -eq (Find-UiTextNode -Text 'NSS_PRIVACY_SHIELD_ACTIVE')) `
    -Message 'Huawei privacy shield still covers the vault after cold-start unlock.'
  $logcat = Invoke-Adb @('logcat', '-d')
  $logcat | Set-Content -LiteralPath $EvidencePath -Encoding utf8
  foreach ($forbidden in @(
    '_UnmodifiableUint8ArrayView',
    'NativeUnlockResult.clear',
    'Unsupported operation: Cannot modify an unmodifiable list',
    'FATAL EXCEPTION',
    "Process: $packageName"
  )) {
    Assert-Condition `
      -Condition (-not ($logcat | Select-String -SimpleMatch $forbidden -Quiet)) `
      -Message "Biometric hotfix Logcat contains: $forbidden"
  }
}
function Test-DevicePathMissing {
  param([Parameter(Mandatory = $true)][string]$Path)
  & $adb -s $Serial shell test '!' -e $Path 2>$null
  return $LASTEXITCODE -eq 0
}
function Test-PackageMissing {
  param([Parameter(Mandatory = $true)][string]$PackageName)
  $output = @(& $adb -s $Serial shell pm path $PackageName 2>&1)
  $exitCode = $LASTEXITCODE
  $text = ($output -join "`n").Trim()
  if ($text -match '(?i)error:|offline|unauthorized|no devices|cannot connect|failed|device .* not found') {
    throw "Unable to verify package cleanup: $text"
  }
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    throw "Unable to verify package cleanup: $text"
  }
  return $true
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
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$policyPath = Join-Path $repoRoot 'config\release\release_artifact_policy.json'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
Assert-Condition `
  -Condition ($ExpectedVersionName -eq $policy.versionName -and
    $ExpectedVersionCode -eq [int]$policy.versionCode) `
  -Message 'Expected version does not match release_artifact_policy.json.'
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
Assert-Condition `
  -Condition ($pubspec -match "(?m)^version:\s*$([regex]::Escape($ExpectedVersionName))\+$ExpectedVersionCode\s*$") `
  -Message 'Expected version does not match pubspec.yaml.'
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
$testDigest = Get-CertificateDigest -ApkPath $testApk
Assert-Condition `
  -Condition ($testDigest -eq $ExpectedCertSha256) `
  -Message "Android test APK certificate mismatch: $testDigest"
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
Invoke-Adb @('shell', 'am', 'force-stop', $packageName) | Out-Null
$backup = Backup-DeviceState -Destination $backupPath
$beforeMetadata = Get-ApkMetadata -ApkPath (
  Join-Path $backup.Path 'installed-before.apk'
)
$targetVersion = [version]$ExpectedVersionName
$installedVersion = [version]$beforeMetadata.VersionName
$isOlderOrSameTarget = $installedVersion -lt $targetVersion -or (
  $installedVersion -eq $targetVersion -and
  $beforeMetadata.VersionCode -le $ExpectedVersionCode
)
Assert-Condition `
  -Condition $isOlderOrSameTarget `
  -Message "Huawei installed version must not be newer than $ExpectedVersionName+$ExpectedVersionCode; found $($beforeMetadata.VersionName)+$($beforeMetadata.VersionCode)."
$baselineDataPresence = @('databases/', 'shared_prefs/', 'no_backup/security/') |
  ForEach-Object {
    $prefix = $_
    [ordered]@{
      prefix = $prefix
      present = @($backup.Inventory | Where-Object {
        $_.path.StartsWith($prefix)
      }).Count -gt 0
    }
  }
Assert-Condition ([bool]($baselineDataPresence | Where-Object {
  $_.prefix -eq 'no_backup/security/' -and $_.present
})) 'Huawei backup is missing the native security keyset.'
Save-Json $baselineDataPresence (Join-Path $backupPath 'private-data-presence-before.json')
$expectedModels = @(
  [pscustomobject]@{ path = 'files/models/qwen2.5-0.5b-instruct-q4_k_m.gguf'; bytes = [int64]491400032; sha256 = '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db' },
  [pscustomobject]@{ path = 'files/models/phase8-device-gate/smollm2-360m-instruct-q8_0.gguf'; bytes = [int64]386404992; sha256 = '48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201' }
)
$beforeModels = Get-ModelInventory -Inventory $backup.Inventory
Assert-Condition `
  -Condition ((ConvertTo-Json -InputObject $beforeModels -Compress) -ceq
    (ConvertTo-Json -InputObject $expectedModels -Compress)) `
  -Message 'Huawei GGUF inventory does not match the two approved user models.'
$deviceDirectory = ''
$deviceTempModelPath = ''
$testInstalled = $false
$primaryError = $null
$cleanupErrors = [Collections.Generic.List[string]]::new()
try {
  Invoke-Adb @('install', '-r', $debugApk) | Out-Null
  Invoke-Adb @('install', '-r', $testApk) | Out-Null
  $testInstalled = $true
  Invoke-InstrumentationClass `
    -ClassName "$packageName.ReleaseReadinessSmokeInstrumentationTest" `
    -ExpectedTestCount 1 `
    -TimeoutSeconds 180 | Out-Null
  $versionSlug = $ExpectedVersionName.Replace('.', '-')
  $deviceDirectory = "/sdcard/Android/data/$packageName/files/v$versionSlug-closeout"
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
  Assert-BiometricHotfixFlow `
    -EvidencePath (Join-Path $backupPath 'biometric-hotfix-logcat.txt')
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
  Ensure-HuaweiInteractive
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
  Write-Host "Huawei $ExpectedVersionName+$ExpectedVersionCode closeout passed. Backup: $backupPath"
}
catch {
  $primaryError = $_
}
finally {
  if (-not [string]::IsNullOrWhiteSpace($deviceDirectory)) {
    try {
      Invoke-Adb @('shell', 'rm', '-rf', $deviceDirectory) | Out-Null
    }
    catch {
      $cleanupErrors.Add("Temporary model cleanup failed: $($_.Exception.Message)")
    }
  }
  if ($testInstalled) {
    try {
      Invoke-Adb @('uninstall', $testPackageName) | Out-Null
    }
    catch {
      $cleanupErrors.Add("Test package cleanup failed: $($_.Exception.Message)")
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($deviceDirectory)) {
    if (-not (Test-DevicePathMissing -Path $deviceDirectory)) {
      $cleanupErrors.Add('Huawei closeout temporary directory was not removed.')
    }
  }
  if ($testInstalled -and -not (Test-PackageMissing -PackageName $testPackageName)) {
    $cleanupErrors.Add('Huawei instrumentation package remains installed.')
  }
}
if ($null -ne $primaryError) {
  throw $primaryError
}
if ($cleanupErrors.Count -gt 0) { throw ($cleanupErrors -join ' ') }
