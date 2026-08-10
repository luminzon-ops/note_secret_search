[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$AndroidSdkRoot = ''
)

$ErrorActionPreference = 'Stop'

function Assert-Test {
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

function Copy-DirectoryContents {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function New-TestCase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$BaseRoot,

    [Parameter(Mandatory = $true)]
    [string]$CasesRoot
  )

  $caseRoot = Join-Path $CasesRoot $Name
  Copy-DirectoryContents -Source $BaseRoot -Destination $caseRoot
  return $caseRoot
}

function Invoke-GateCase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CaseRoot,

    [Parameter(Mandatory = $true)]
    [bool]$ShouldPass,

    [string]$ExpectedMessage = ''
  )

  $gate = Join-Path $CaseRoot 'scripts\quality\Invoke-LlmAarProvenanceGate.ps1'
  $arguments = @(
    '-NoProfile',
    '-File',
    $gate,
    '-RepoRoot',
    $CaseRoot,
    '-SkipRebuild'
  )
  if (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $arguments += @('-AndroidSdkRoot', $AndroidSdkRoot)
  }
  $output = (& pwsh @arguments 2>&1 | Out-String)
  $passed = $LASTEXITCODE -eq 0
  Assert-Test `
    -Condition ($passed -eq $ShouldPass) `
    -Message "Unexpected gate result for $CaseRoot.`n$output"
  if (-not $ShouldPass) {
    Assert-Test `
      -Condition ($output.Contains($ExpectedMessage, [StringComparison]::OrdinalIgnoreCase)) `
      -Message "Gate failure did not contain '$ExpectedMessage'.`n$output"
  }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempParent "nss-llm-gate-tests-$([guid]::NewGuid().ToString('N'))"
$baseRoot = Join-Path $tempRoot 'base'
$casesRoot = Join-Path $tempRoot 'cases'

try {
  New-Item -ItemType Directory -Force -Path $baseRoot, $casesRoot | Out-Null
  Copy-DirectoryContents `
    -Source (Join-Path $RepoRoot 'android\third_party\llamacpp') `
    -Destination (Join-Path $baseRoot 'android\third_party\llamacpp')
  New-Item -ItemType Directory -Force -Path (Join-Path $baseRoot 'android\third_party') | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $RepoRoot 'android\third_party\.gitattributes') `
    -Destination (Join-Path $baseRoot 'android\third_party\.gitattributes') `
    -Force
  Copy-Item `
    -LiteralPath (Join-Path $RepoRoot 'android\third_party\llamacpp-kotlin-0.2.0-nss-arm64-baseline.aar') `
    -Destination (Join-Path $baseRoot 'android\third_party') `
    -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $baseRoot 'android\app') | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $RepoRoot 'android\app\build.gradle.kts') `
    -Destination (Join-Path $baseRoot 'android\app\build.gradle.kts') `
    -Force
  Copy-Item `
    -LiteralPath (Join-Path $RepoRoot 'android\settings.gradle.kts') `
    -Destination (Join-Path $baseRoot 'android\settings.gradle.kts') `
    -Force
  Copy-DirectoryContents `
    -Source (Join-Path $RepoRoot 'scripts\llm') `
    -Destination (Join-Path $baseRoot 'scripts\llm')
  New-Item -ItemType Directory -Force -Path (Join-Path $baseRoot 'scripts\quality') | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $RepoRoot 'scripts\quality\Invoke-LlmAarProvenanceGate.ps1') `
    -Destination (Join-Path $baseRoot 'scripts\quality\Invoke-LlmAarProvenanceGate.ps1') `
    -Force

  $baseline = New-TestCase -Name 'baseline' -BaseRoot $baseRoot -CasesRoot $casesRoot
  Invoke-GateCase -CaseRoot $baseline -ShouldPass $true

  $artifactTamper = New-TestCase -Name 'artifact-tamper' -BaseRoot $baseRoot -CasesRoot $casesRoot
  $artifactPath = Join-Path $artifactTamper `
    'android\third_party\llamacpp-kotlin-0.2.0-nss-arm64-baseline.aar'
  $artifactBytes = [IO.File]::ReadAllBytes($artifactPath)
  $artifactBytes[0] = $artifactBytes[0] -bxor 0xff
  [IO.File]::WriteAllBytes($artifactPath, $artifactBytes)
  Invoke-GateCase `
    -CaseRoot $artifactTamper `
    -ShouldPass $false `
    -ExpectedMessage 'checksum does not match provenance'

  $patchTamper = New-TestCase -Name 'patch-tamper' -BaseRoot $baseRoot -CasesRoot $casesRoot
  $patchLock = Get-Content -LiteralPath (
    Join-Path $patchTamper 'android\third_party\llamacpp\source-lock.json'
  ) -Raw | ConvertFrom-Json -Depth 100
  $lastPatchPath = [string]@($patchLock.patches)[-1].path
  $patchPath = Join-Path $patchTamper $lastPatchPath.Replace('/', '\')
  [IO.File]::AppendAllText($patchPath, "`n", [Text.UTF8Encoding]::new($false))
  Invoke-GateCase `
    -CaseRoot $patchTamper `
    -ShouldPass $false `
    -ExpectedMessage 'patch checksum mismatch'

  $elfAuditTamper = New-TestCase -Name 'elf-audit-tamper' -BaseRoot $baseRoot -CasesRoot $casesRoot
  $elfPath = Join-Path $elfAuditTamper 'android\third_party\llamacpp\elf-audit.json'
  $elfJson = Get-Content -LiteralPath $elfPath -Raw | ConvertFrom-Json -Depth 100
  $elfJson.soname = 'tampered.so'
  [IO.File]::WriteAllText(
    $elfPath,
    (($elfJson | ConvertTo-Json -Depth 100) + "`n"),
    [Text.UTF8Encoding]::new($false)
  )
  Invoke-GateCase `
    -CaseRoot $elfAuditTamper `
    -ShouldPass $false `
    -ExpectedMessage 'ELF audit record checksum does not match provenance'

  $legacyGradle = New-TestCase -Name 'legacy-gradle' -BaseRoot $baseRoot -CasesRoot $casesRoot
  $appGradlePath = Join-Path $legacyGradle 'android\app\build.gradle.kts'
  [IO.File]::AppendAllText(
    $appGradlePath,
    "`n// pickFirsts`n",
    [Text.UTF8Encoding]::new($false)
  )
  Invoke-GateCase `
    -CaseRoot $legacyGradle `
    -ShouldPass $false `
    -ExpectedMessage 'Legacy app Gradle integration'

  $legacyJniPackaging = New-TestCase `
    -Name 'legacy-jni-packaging' `
    -BaseRoot $baseRoot `
    -CasesRoot $casesRoot
  $legacyJniRoot = Join-Path $legacyJniPackaging `
    'android\app\src\main\jniLibs\arm64-v8a'
  New-Item -ItemType Directory -Force -Path $legacyJniRoot | Out-Null
  [IO.File]::WriteAllBytes(
    (Join-Path $legacyJniRoot 'librnllama_v8_4_fp16_dotprod.so'),
    [byte[]](0x7f, 0x45, 0x4c, 0x46)
  )
  Invoke-GateCase `
    -CaseRoot $legacyJniPackaging `
    -ShouldPass $false `
    -ExpectedMessage 'Legacy app JNI library is not excluded from packaging'

  Write-Host 'LLM AAR provenance fixture tests passed: 6 cases'
}
finally {
  $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
  $tempPrefix = $tempParent.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  ) + [IO.Path]::DirectorySeparatorChar
  Assert-Test `
    -Condition ($resolvedTempRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) `
    -Message "Refusing to remove fixture path outside the temp root: $resolvedTempRoot"
  if (Test-Path -LiteralPath $resolvedTempRoot -PathType Container) {
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
  }
}
