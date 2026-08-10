[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [Parameter(Mandatory = $true)]
  [string]$DebugApkPath,
  [Parameter(Mandatory = $true)]
  [string]$AndroidTestApkPath,
  [Parameter(Mandatory = $true)]
  [string]$ReleaseApkPath,
  [Parameter(Mandatory = $true)]
  [string]$ReleaseAabPath,
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

function Assert-Condition {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Resolve-Artifact {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Label is missing: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-AndroidTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ToolName
  )

  $command = Get-Command $ToolName -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $sdkRoot = $env:ANDROID_SDK_ROOT
  if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    $sdkRoot = $env:ANDROID_HOME
  }
  if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    $localPropertiesPath = Join-Path $RepoRoot 'android\local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf) {
      $sdkLine = Get-Content -LiteralPath $localPropertiesPath |
        Where-Object { $_ -match '^sdk\.dir=' } |
        Select-Object -First 1
      if ($sdkLine -match '^sdk\.dir=(.*)$') {
        $sdkRoot = $matches[1].Trim().Replace('\:', ':')
      }
    }
  }
  if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    throw "$ToolName is not on PATH and Android SDK root is unknown."
  }

  $toolCandidates = Get-ChildItem `
    -LiteralPath (Join-Path $sdkRoot 'build-tools') `
    -Filter "$ToolName*" `
    -File `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $ToolName -or $_.Name -eq "$ToolName.exe" } |
    Sort-Object FullName
  if ($toolCandidates.Count -eq 0) {
    throw "Android SDK tool not found: $ToolName"
  }
  return $toolCandidates[-1].FullName
}

function Invoke-Aapt {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AaptPath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $output = @(& $AaptPath @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "aapt $($Arguments -join ' ') exited with code $LASTEXITCODE"
  }
  return [string[]]$output
}

function Get-ApkMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AaptPath,
    [Parameter(Mandatory = $true)]
    [string]$ApkPath
  )

  $badging = Invoke-Aapt -AaptPath $AaptPath -Arguments @('dump', 'badging', $ApkPath)
  $packageLine = $badging | Where-Object { $_ -match "^package:" } |
    Select-Object -First 1
  Assert-Condition `
    -Condition ($null -ne $packageLine) `
    -Message "aapt did not report package metadata for $ApkPath"
  $match = [regex]::Match(
    $packageLine,
    "name='([^']+)' versionCode='([^']+)' versionName='([^']+)'"
  )
  Assert-Condition `
    -Condition $match.Success `
    -Message "Unable to parse package metadata for $ApkPath"

  $sdkLine = $badging | Where-Object { $_ -match "^sdkVersion:" } |
    Select-Object -First 1
  $targetLine = $badging | Where-Object { $_ -match "^targetSdkVersion:" } |
    Select-Object -First 1
  $sdkMatch = [regex]::Match($sdkLine, "sdkVersion:'([0-9]+)'")
  $targetMatch = [regex]::Match($targetLine, "targetSdkVersion:'([0-9]+)'")
  Assert-Condition $sdkMatch.Success "Unable to parse min SDK for $ApkPath"
  Assert-Condition $targetMatch.Success "Unable to parse target SDK for $ApkPath"

  return [pscustomobject]@{
    PackageName = $match.Groups[1].Value
    VersionCode = [int]$match.Groups[2].Value
    VersionName = $match.Groups[3].Value
    MinSdk = [int]$sdkMatch.Groups[1].Value
    TargetSdk = [int]$targetMatch.Groups[1].Value
    Badging = $badging
  }
}

function Get-ZipEntries {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    return [string[]]@(
      $archive.Entries | ForEach-Object { $_.FullName }
    )
  }
  finally {
    $archive.Dispose()
  }
}

function Assert-TestApkContract {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedPackageName,
    [Parameter(Mandatory = $true)]
    [string]$AaptPath,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Policy
  )

  $badging = Invoke-Aapt -AaptPath $AaptPath -Arguments @(
    'dump',
    'badging',
    $ApkPath
  )
  $packageLine = $badging | Where-Object { $_ -match "^package:" } |
    Select-Object -First 1
  $packageMatch = [regex]::Match($packageLine, "name='([^']+)'")
  Assert-Condition `
    -Condition $packageMatch.Success `
    -Message "Unable to parse Android test package metadata for $ApkPath"
  Assert-Condition `
    -Condition ($packageMatch.Groups[1].Value -eq $ExpectedPackageName) `
    -Message "Android test package mismatch: $($packageMatch.Groups[1].Value)"

  $sdkMatch = [regex]::Match(
    ($badging | Where-Object { $_ -match "^sdkVersion:" } |
      Select-Object -First 1),
    "sdkVersion:'([0-9]+)'"
  )
  $targetMatch = [regex]::Match(
    ($badging | Where-Object { $_ -match "^targetSdkVersion:" } |
      Select-Object -First 1),
    "targetSdkVersion:'([0-9]+)'"
  )
  Assert-Condition $sdkMatch.Success "Unable to parse test APK min SDK."
  Assert-Condition $targetMatch.Success "Unable to parse test APK target SDK."
  Assert-Condition `
    -Condition ([int]$sdkMatch.Groups[1].Value -eq [int]$Policy.minSdk) `
    -Message 'Android test APK minSdk does not match policy.'
  Assert-Condition `
    -Condition ([int]$targetMatch.Groups[1].Value -eq [int]$Policy.targetSdk) `
    -Message 'Android test APK targetSdk does not match policy.'

  return [pscustomobject]@{
    Label = 'Android test APK'
    Path = $ApkPath
    Sha256 = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    PackageName = $packageMatch.Groups[1].Value
    MinSdk = [int]$sdkMatch.Groups[1].Value
    TargetSdk = [int]$targetMatch.Groups[1].Value
  }
}

function Assert-ApkContract {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedPackageName,
    [Parameter(Mandatory = $true)]
    [bool]$ReleaseArtifact,
    [Parameter(Mandatory = $true)]
    [string]$AaptPath,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Policy
  )

  $metadata = Get-ApkMetadata -AaptPath $AaptPath -ApkPath $ApkPath
  Assert-Condition `
    -Condition ($metadata.PackageName -eq $ExpectedPackageName) `
    -Message "$Label package mismatch: $($metadata.PackageName)"
  Assert-Condition `
    -Condition ($metadata.VersionName -eq $Policy.versionName) `
    -Message "$Label versionName mismatch: $($metadata.VersionName)"
  Assert-Condition `
    -Condition ($metadata.VersionCode -eq [int]$Policy.versionCode) `
    -Message "$Label versionCode mismatch: $($metadata.VersionCode)"
  Assert-Condition `
    -Condition ($metadata.MinSdk -eq [int]$Policy.minSdk) `
    -Message "$Label minSdk mismatch: $($metadata.MinSdk)"
  Assert-Condition `
    -Condition ($metadata.TargetSdk -eq [int]$Policy.targetSdk) `
    -Message "$Label targetSdk mismatch: $($metadata.TargetSdk)"

  $entries = Get-ZipEntries -Path $ApkPath
  $abiEntries = @(
    $entries |
      ForEach-Object {
        if ($_ -match '^lib/([^/]+)/') {
          $matches[1]
        }
      } |
      Sort-Object -Unique
  )
  foreach ($abi in @($Policy.apkAbis)) {
    Assert-Condition `
      -Condition ($abiEntries -contains $abi) `
      -Message "$Label is missing expected ABI: $abi"
  }
  foreach ($abi in $abiEntries) {
    Assert-Condition `
      -Condition (@($Policy.apkAbis) -contains $abi) `
      -Message "$Label contains unsupported ABI: $abi"
  }

  foreach ($asset in @($Policy.requiredTokenizerAssets)) {
    Assert-Condition `
      -Condition ($entries -contains $asset) `
      -Message "$Label is missing tokenizer asset: $asset"
  }
  foreach ($prefix in @($Policy.forbiddenAssetPrefixes)) {
    Assert-Condition `
      -Condition (-not ($entries | Where-Object { $_.StartsWith($prefix) })) `
      -Message "$Label contains forbidden asset prefix: $prefix"
  }
  foreach ($library in @($Policy.requiredNativeLibraries)) {
    $hasLibrary = @(
      $entries | Where-Object {
        $_ -match "(^|/)$([regex]::Escape($library))$"
      }
    ).Count -gt 0
    Assert-Condition `
      -Condition $hasLibrary `
      -Message "$Label is missing required native library: $library"
  }
  if ($ReleaseArtifact) {
    foreach ($library in @($Policy.forbiddenReleaseNativeLibraries)) {
      $hasForbiddenLibrary = @(
        $entries | Where-Object {
          $_ -match "(^|/)$([regex]::Escape($library))$"
        }
      ).Count -gt 0
      Assert-Condition `
        -Condition (-not $hasForbiddenLibrary) `
        -Message "$Label contains forbidden release native library: $library"
    }
  }

  $manifest = Invoke-Aapt `
    -AaptPath $AaptPath `
    -Arguments @('dump', 'xmltree', $ApkPath, 'AndroidManifest.xml')
  $manifestText = $manifest -join "`n"
  if ($ReleaseArtifact) {
    Assert-Condition `
      -Condition (-not ($metadata.Badging -match 'application-debuggable')) `
      -Message "$Label is debuggable."
    Assert-Condition `
      -Condition ($manifestText -notmatch 'usesCleartextTraffic[^\n]*(true|0xffffffff)') `
      -Message "$Label allows cleartext traffic."
    Assert-Condition `
      -Condition ($manifestText -notmatch 'allowBackup[^\n]*(true|0xffffffff)') `
      -Message "$Label enables backup."
    Assert-Condition `
      -Condition ($manifestText -notmatch 'debuggable[^\n]*(true|0xffffffff)') `
      -Message "$Label manifest enables debugging."
  }

  return [pscustomobject]@{
    Label = $Label
    Path = $ApkPath
    Sha256 = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    PackageName = $metadata.PackageName
    VersionName = $metadata.VersionName
    VersionCode = $metadata.VersionCode
    MinSdk = $metadata.MinSdk
    TargetSdk = $metadata.TargetSdk
    Abis = $abiEntries
  }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$policyPath = Join-Path $RepoRoot 'config\release\release_artifact_policy.json'
Assert-Condition (Test-Path -LiteralPath $policyPath -PathType Leaf) `
  "Release artifact policy is missing: $policyPath"
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -Depth 100
$aapt = Resolve-AndroidTool -ToolName 'aapt'

$debugApk = Resolve-Artifact -Path $DebugApkPath -Label 'Debug APK'
$testApk = Resolve-Artifact -Path $AndroidTestApkPath -Label 'Android test APK'
$releaseApk = Resolve-Artifact -Path $ReleaseApkPath -Label 'Release APK'
$releaseAab = Resolve-Artifact -Path $ReleaseAabPath -Label 'Release AAB'

$debugReport = Assert-ApkContract `
  -Label 'Debug APK' `
  -ApkPath $debugApk `
  -ExpectedPackageName $policy.applicationId `
  -ReleaseArtifact $false `
  -AaptPath $aapt `
  -Policy $policy
$testReport = Assert-TestApkContract `
  -ApkPath $testApk `
  -ExpectedPackageName "$($policy.applicationId).test" `
  -AaptPath $aapt `
  -Policy $policy
$releaseReport = Assert-ApkContract `
  -Label 'Release APK' `
  -ApkPath $releaseApk `
  -ExpectedPackageName $policy.applicationId `
  -ReleaseArtifact $true `
  -AaptPath $aapt `
  -Policy $policy

$aabEntries = Get-ZipEntries -Path $releaseAab
Assert-Condition `
  -Condition ($aabEntries -contains 'base/manifest/AndroidManifest.xml') `
  -Message 'Release AAB is missing the base manifest.'
Assert-Condition `
  -Condition (@(
    $aabEntries | Where-Object { $_ -match '^base/assets/flutter_assets/' }
  ).Count -gt 0) `
  -Message 'Release AAB is missing Flutter assets.'

$report = [ordered]@{
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
  policyVersionName = $policy.versionName
  policyVersionCode = [int]$policy.versionCode
  debug = $debugReport
  androidTest = $testReport
  release = $releaseReport
  releaseAab = [ordered]@{
    path = $releaseAab
    sha256 = (Get-FileHash -LiteralPath $releaseAab -Algorithm SHA256).Hash.ToLowerInvariant()
    entries = $aabEntries.Count
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot 'build\android-artifact-audit.json'
}
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host "Android artifact audit passed: $($policy.versionName)+$($policy.versionCode)"
