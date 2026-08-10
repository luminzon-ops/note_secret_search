[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ExpectedVersionName = '',
  [int]$ExpectedVersionCode = 0
)

$ErrorActionPreference = 'Stop'

function Read-ProductVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $content = Get-Content -LiteralPath $Path -Raw
  $match = [regex]::Match(
    $content,
    '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
  )
  if (-not $match.Success) {
    throw "pubspec.yaml does not contain a valid product version: $Path"
  }
  return [pscustomobject]@{
    Name = $match.Groups[1].Value
    Code = [int]$match.Groups[2].Value
  }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
$localPropertiesPath = Join-Path $RepoRoot 'android\local.properties'
$productVersion = Read-ProductVersion -Path $pubspecPath

if ([string]::IsNullOrWhiteSpace($ExpectedVersionName)) {
  $ExpectedVersionName = $productVersion.Name
}
if ($ExpectedVersionCode -eq 0) {
  $ExpectedVersionCode = $productVersion.Code
}
if ($ExpectedVersionName -ne $productVersion.Name -or
    $ExpectedVersionCode -ne $productVersion.Code) {
  throw (
    "Expected version $ExpectedVersionName+$ExpectedVersionCode does not match " +
    "pubspec.yaml $($productVersion.Name)+$($productVersion.Code)."
  )
}

$flutter = Get-Command flutter -ErrorAction Stop
Push-Location $RepoRoot
try {
  & $flutter.Source build apk --config-only --no-pub
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build apk --config-only --no-pub exited with code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf)) {
  throw "Flutter did not generate android/local.properties: $localPropertiesPath"
}

$properties = New-Object System.Collections.Specialized.OrderedDictionary
$loadedProperties = New-Object System.IO.FileInfo $localPropertiesPath
$javaProperties = New-Object System.Collections.Specialized.NameValueCollection
$reader = New-Object System.IO.StreamReader($localPropertiesPath)
try {
  while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ($line -match '^\s*([^#=!:\s]+)\s*=\s*(.*)\s*$') {
      $javaProperties[$matches[1]] = $matches[2].Trim()
    }
  }
}
finally {
  $reader.Dispose()
}

$actualName = $javaProperties['flutter.versionName']
$actualCode = $javaProperties['flutter.versionCode']
if ([string]::IsNullOrWhiteSpace($actualName) -or
    [string]::IsNullOrWhiteSpace($actualCode)) {
  throw 'android/local.properties is missing Flutter version metadata.'
}
if ($actualName -eq '1.0' -or $actualCode -eq '1') {
  throw 'Flutter version metadata still contains the Gradle default 1.0/1.'
}
if ($actualName -ne $ExpectedVersionName -or
    $actualCode -ne [string]$ExpectedVersionCode) {
  throw (
    "android/local.properties contains $actualName+$actualCode; expected " +
    "$ExpectedVersionName+$ExpectedVersionCode."
  )
}

Write-Host "Flutter Android version prepared: $actualName+$actualCode"
