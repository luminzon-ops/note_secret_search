[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$BuildRoot = '',
  [string]$AndroidSdkRoot = '',
  [string]$JavaHome = '',
  [string]$GradleUserHome = '',
  [string]$ResultPath = '',
  [ValidateRange(1, 4)]
  [int]$RebuildCount = 2,
  [switch]$Offline,
  [switch]$UpdateSourceManifest,
  [switch]$UpdateCommittedArtifact,
  [switch]$VerifyCommittedArtifact
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LlmAarCommon.psm1') -Force

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

Assert-LlmCondition `
  -Condition (-not ($UpdateCommittedArtifact -and $VerifyCommittedArtifact)) `
  -Message 'Choose either -UpdateCommittedArtifact or -VerifyCommittedArtifact.'
Assert-LlmCondition `
  -Condition (
    $RebuildCount -ge 2 -or
      (-not $UpdateCommittedArtifact -and -not $VerifyCommittedArtifact)
  ) `
  -Message 'Committed artifact updates and verification require at least two clean rebuilds.'

$workspaceParent = Split-Path $RepoRoot -Parent
if ((Split-Path $workspaceParent -Leaf) -eq 'worktrees') {
  $workspaceParent = Split-Path $workspaceParent -Parent
}
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
  $BuildRoot = Join-Path ([IO.Path]::GetTempPath()) 'nss-llm-aar'
}
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
Assert-LlmCondition `
  -Condition ($BuildRoot.Length -le 96) `
  -Message 'BuildRoot is too long for the Android CMake/Ninja path budget. Use a shorter path.'
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $BuildRoot 'last-build.json'
}
else {
  $ResultPath = [IO.Path]::GetFullPath($ResultPath)
}

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
  $sdkCandidates = @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    'D:\Program\Android\SDK',
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $AndroidSdkRoot = $sdkCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1
}
Assert-LlmCondition `
  -Condition (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) `
  -Message 'Pinned Android SDK was not found. Pass -AndroidSdkRoot.'
$AndroidSdkRoot = (Resolve-Path -LiteralPath $AndroidSdkRoot).Path

if ([string]::IsNullOrWhiteSpace($JavaHome)) {
  $javaCandidates = @(
    $env:JAVA_HOME,
    'C:\Program Files\Java\jdk-17.0.3.1'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $JavaHome = $javaCandidates |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bin\java.exe') -PathType Leaf } |
    Select-Object -First 1
}
Assert-LlmCondition `
  -Condition (-not [string]::IsNullOrWhiteSpace($JavaHome)) `
  -Message 'Pinned JDK 17 was not found. Pass -JavaHome.'
$JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path

if ([string]::IsNullOrWhiteSpace($GradleUserHome)) {
  $GradleUserHome = Join-Path $workspaceParent '.note_secret_search_quality_cache\gradle'
}
$GradleUserHome = [IO.Path]::GetFullPath($GradleUserHome)
New-Item -ItemType Directory -Force -Path $GradleUserHome | Out-Null

$lock = Read-LlmSourceLock -RepoRoot $RepoRoot
Assert-LlmCondition -Condition ($lock.schemaVersion -eq 1) -Message 'Unsupported source lock schema.'
Assert-LlmCondition `
  -Condition ($lock.source.commit -eq 'b576a1ff0a4dc013893c9aee69b1df70b3cc9794') `
  -Message 'Unexpected kotlinllamacpp source commit.'
Assert-LlmCondition `
  -Condition ($lock.source.sourceManifestSha256 -match '^[0-9a-f]{64}$') `
  -Message 'Pinned source manifest checksum is missing or malformed.'

$ndkRoot = Join-Path $AndroidSdkRoot "ndk\$($lock.toolchain.ndk)"
$cmakeRoot = Join-Path $AndroidSdkRoot "cmake\$($lock.toolchain.cmake)"
$ndkProperties = Join-Path $ndkRoot 'source.properties'
$cmake = Join-Path $cmakeRoot 'bin\cmake.exe'
$ninja = Join-Path $cmakeRoot 'bin\ninja.exe'
$clang = Join-Path $ndkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe'
$java = Join-Path $JavaHome 'bin\java.exe'
foreach ($tool in @($ndkProperties, $cmake, $ninja, $clang, $java)) {
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $tool -PathType Leaf) `
    -Message "Pinned build tool is missing: $tool"
}
Assert-LlmCondition `
  -Condition ((Get-LlmSha256 -Path $ndkProperties) -eq $lock.toolchain.ndkSourcePropertiesSha256) `
  -Message 'Pinned NDK source.properties checksum mismatch.'

$javaVersion = (& $java -version 2>&1) -join "`n"
$cmakeVersion = (& $cmake --version 2>&1) -join "`n"
$ninjaVersion = (& $ninja --version 2>&1) -join "`n"
$clangVersion = (& $clang --version 2>&1) -join "`n"
Assert-LlmCondition `
  -Condition $javaVersion.Contains('17.0.3.1', [StringComparison]::Ordinal) `
  -Message 'JDK runtime does not match the source lock.'
Assert-LlmCondition `
  -Condition $cmakeVersion.Contains('3.22.1', [StringComparison]::Ordinal) `
  -Message 'CMake runtime does not match the source lock.'
Assert-LlmCondition `
  -Condition ($ninjaVersion.Trim() -eq $lock.toolchain.ninja) `
  -Message 'Ninja runtime does not match the source lock.'
Assert-LlmCondition `
  -Condition $clangVersion.Contains('clang version 19.0.1', [StringComparison]::Ordinal) `
  -Message 'NDK Clang runtime does not match the source lock.'

$downloads = Join-Path $BuildRoot 'downloads'
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
$archivePath = Join-Path $downloads "kotlinllamacpp-$($lock.source.commit).zip"
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
  Assert-LlmCondition `
    -Condition (-not $Offline) `
    -Message "Offline build cache is missing the pinned source archive: $archivePath"
  Invoke-WebRequest -Uri $lock.source.archiveUrl -OutFile $archivePath
}
Assert-LlmCondition `
  -Condition ((Get-LlmSha256 -Path $archivePath) -eq $lock.source.archiveSha256) `
  -Message 'Pinned kotlinllamacpp archive checksum mismatch.'

$sourceManifestPath = Join-Path $RepoRoot 'android\third_party\llamacpp\source-files.sha256'
$artifactPath = Resolve-LlmRepoPath -RepoRoot $RepoRoot -RelativePath $lock.artifact.path
$patches = foreach ($patch in $lock.patches) {
  $path = Resolve-LlmRepoPath -RepoRoot $RepoRoot -RelativePath $patch.path
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $path -PathType Leaf) `
    -Message "Pinned patch is missing: $($patch.path)"
  Assert-LlmCondition `
    -Condition ((Get-LlmSha256 -Path $path) -eq $patch.sha256) `
    -Message "Pinned patch checksum mismatch: $($patch.path)"
  $path
}

$runResults = @()
for ($index = 1; $index -le $RebuildCount; $index++) {
  $runId = "run-$index-$([guid]::NewGuid().ToString('N'))"
  $runRoot = Join-Path $BuildRoot "runs\$runId"
  $extractRoot = Join-Path $runRoot 'source'
  New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
  $sourceRoot = Get-LlmSourceRoot -ExtractRoot $extractRoot

  $sourceRecords = @(Get-LlmSourceManifestRecords -SourceRoot $sourceRoot)
  Assert-LlmCondition `
    -Condition ($sourceRecords.Count -gt 0) `
    -Message 'No pinned source files were found in the upstream archive.'
  $sourceManifest = ConvertTo-LlmHashManifest -Records $sourceRecords
  if ($UpdateSourceManifest -and $index -eq 1) {
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($sourceManifestPath, $sourceManifest, $encoding)
  }
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) `
    -Message 'Committed source file manifest is missing.'
  $committedSourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw
  Assert-LlmCondition `
    -Condition ($sourceManifest -ceq $committedSourceManifest) `
    -Message 'Upstream source files do not match the committed source manifest.'
  Assert-LlmCondition `
    -Condition ((Get-LlmSha256 -Path $sourceManifestPath) -eq $lock.source.sourceManifestSha256) `
    -Message 'Committed source manifest checksum does not match the source lock.'

  foreach ($patchPath in $patches) {
    Invoke-LlmProcess `
      -FilePath 'git' `
      -Arguments @('apply', '--check', '--no-index', '--whitespace=nowarn', $patchPath) `
      -WorkingDirectory $sourceRoot `
      -LogPath (Join-Path $runRoot "logs\check-$([IO.Path]::GetFileName($patchPath)).log")
    Invoke-LlmProcess `
      -FilePath 'git' `
      -Arguments @('apply', '--no-index', '--whitespace=nowarn', $patchPath) `
      -WorkingDirectory $sourceRoot `
      -LogPath (Join-Path $runRoot "logs\apply-$([IO.Path]::GetFileName($patchPath)).log")
  }

  $localProperties = "sdk.dir=$($AndroidSdkRoot.Replace('\', '\\'))`n"
  [IO.File]::WriteAllText(
    (Join-Path $sourceRoot 'local.properties'),
    $localProperties,
    [Text.UTF8Encoding]::new($false)
  )

  $oldEnvironment = @{
    JAVA_HOME = $env:JAVA_HOME
    ANDROID_HOME = $env:ANDROID_HOME
    ANDROID_SDK_ROOT = $env:ANDROID_SDK_ROOT
    GRADLE_USER_HOME = $env:GRADLE_USER_HOME
    SOURCE_DATE_EPOCH = $env:SOURCE_DATE_EPOCH
  }
  try {
    $env:JAVA_HOME = $JavaHome
    $env:ANDROID_HOME = $AndroidSdkRoot
    $env:ANDROID_SDK_ROOT = $AndroidSdkRoot
    $env:GRADLE_USER_HOME = $GradleUserHome
    $env:SOURCE_DATE_EPOCH = [string]$lock.source.sourceDateEpoch

    $gradleArguments = @(
      $lock.build.gradleTask,
      '--no-daemon',
      '--stacktrace'
    )
    if ($Offline) {
      $gradleArguments += '--offline'
    }
    $gradleWrapper = Join-Path $sourceRoot 'gradlew.bat'
    Invoke-LlmProcess `
      -FilePath $gradleWrapper `
      -Arguments $gradleArguments `
      -WorkingDirectory $sourceRoot `
      -LogPath (Join-Path $runRoot 'logs\gradle-build.log')
  }
  finally {
    foreach ($name in $oldEnvironment.Keys) {
      Set-Item -Path "Env:$name" -Value $oldEnvironment[$name]
    }
  }

  $rawAar = Join-Path $sourceRoot 'llamaCpp\build\outputs\aar\llamaCpp-release.aar'
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $rawAar -PathType Leaf) `
    -Message "Gradle did not produce the expected AAR: $rawAar"
  $normalizedAar = Join-Path $runRoot ([IO.Path]::GetFileName($artifactPath))
  Write-LlmNormalizedZip `
    -InputPath $rawAar `
    -OutputPath $normalizedAar `
    -SourceDateEpoch ([long]$lock.source.sourceDateEpoch)

  $runResults += [pscustomobject]@{
    Run = $index
    Root = $runRoot
    Artifact = $normalizedAar
    Sha256 = Get-LlmSha256 -Path $normalizedAar
    Size = (Get-Item -LiteralPath $normalizedAar).Length
  }
}

$distinctHashes = @($runResults | Select-Object -ExpandProperty Sha256 -Unique)
$distinctSizes = @($runResults | Select-Object -ExpandProperty Size -Unique)
Assert-LlmCondition `
  -Condition ($distinctHashes.Count -eq 1 -and $distinctSizes.Count -eq 1) `
  -Message 'Clean LLM AAR rebuilds were not byte-for-byte reproducible.'
$reproducible = $RebuildCount -ge 2

$builtArtifact = $runResults[0].Artifact
if ($UpdateCommittedArtifact) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $artifactPath) | Out-Null
  Copy-Item -LiteralPath $builtArtifact -Destination $artifactPath -Force
}
if ($VerifyCommittedArtifact) {
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $artifactPath -PathType Leaf) `
    -Message "Committed artifact is missing: $artifactPath"
  Assert-LlmCondition `
    -Condition ((Get-LlmSha256 -Path $artifactPath) -eq $distinctHashes[0]) `
    -Message 'Rebuilt AAR does not match the committed artifact.'
}

$result = [ordered]@{
  schemaVersion = 1
  sourceCommit = $lock.source.commit
  sourceArchiveSha256 = $lock.source.archiveSha256
  sourceManifestSha256 = Get-LlmSha256 -Path $sourceManifestPath
  rebuildCount = $RebuildCount
  reproducible = $reproducible
  artifactSha256 = $distinctHashes[0]
  artifactSize = $distinctSizes[0]
  runs = $runResults
}
$resultJson = $result | ConvertTo-Json -Depth 10
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
[IO.File]::WriteAllText(
  $ResultPath,
  "$resultJson`n",
  [Text.UTF8Encoding]::new($false)
)
$resultJson
