[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [switch]$SkipRebuild,
  [switch]$Offline,
  [string]$BuildRoot = '',
  [string]$AndroidSdkRoot = ''
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\llm\LlmAarCommon.psm1'
Import-Module $modulePath -Force
Import-Module (Join-Path $PSScriptRoot '..\llm\LlmAarAudit.psm1') -Force

function Read-Json {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $Path -PathType Leaf) `
    -Message "Required provenance file is missing: $Path"
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Assert-Text {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Assert-LlmCondition -Condition $Condition -Message $Message
}

function Assert-ArraysEqual {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Actual,

    [Parameter(Mandatory = $true)]
    [object[]]$Expected,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $actualJson = ($Actual | Sort-Object | ConvertTo-Json -Compress)
  $expectedJson = ($Expected | Sort-Object | ConvertTo-Json -Compress)
  Assert-Text -Condition ($actualJson -eq $expectedJson) -Message $Message
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$metadataRoot = Join-Path $RepoRoot 'android\third_party\llamacpp'
$attributesPath = Join-Path $RepoRoot 'android\third_party\.gitattributes'
$sourceLockPath = Join-Path $metadataRoot 'source-lock.json'
$provenancePath = Join-Path $metadataRoot 'provenance.json'
$sbomPath = Join-Path $metadataRoot 'sbom.cdx.json'
$elfAuditPath = Join-Path $metadataRoot 'elf-audit.json'
$entryHashesPath = Join-Path $metadataRoot 'aar-entry-hashes.sha256'
$sourceManifestPath = Join-Path $metadataRoot 'source-files.sha256'

$lock = Read-Json -Path $sourceLockPath
$provenance = Read-Json -Path $provenancePath
$sbom = Read-Json -Path $sbomPath
$committedElfAudit = Read-Json -Path $elfAuditPath

Assert-Text -Condition (Test-Path -LiteralPath $attributesPath -PathType Leaf) `
  -Message 'Pinned LLM artifacts are missing local Git attributes.'
$attributes = Get-Content -LiteralPath $attributesPath -Raw
foreach ($requiredAttribute in @(
  '*.aar binary',
  'llamacpp/*.json text eol=lf',
  'llamacpp/*.sha256 text eol=lf',
  'llamacpp/patches/*.patch text eol=lf -whitespace'
)) {
  Assert-Text `
    -Condition ($attributes.Contains($requiredAttribute, [StringComparison]::Ordinal)) `
    -Message "Required LLM Git attribute is missing: $requiredAttribute"
}

Assert-Text -Condition ($lock.schemaVersion -eq 1) -Message 'Unsupported source lock schema.'
Assert-Text -Condition ($provenance.schemaVersion -eq 1) -Message 'Unsupported provenance schema.'
Assert-Text -Condition ($lock.source.commit -eq 'b576a1ff0a4dc013893c9aee69b1df70b3cc9794') `
  -Message 'The kotlinllamacpp wrapper commit is not pinned to the Phase 6 baseline.'
Assert-Text -Condition ($lock.source.vendoredLlamaCppTree -match '^[0-9a-f]{40}$') `
  -Message 'The vendored llama.cpp tree hash is missing or malformed.'
Assert-Text -Condition ($lock.source.archiveSha256 -match '^[0-9a-f]{64}$') `
  -Message 'The upstream archive SHA-256 is missing or malformed.'
Assert-Text -Condition ($lock.source.sourceManifestSha256 -match '^[0-9a-f]{64}$') `
  -Message 'The source manifest SHA-256 is missing or malformed.'
Assert-Text -Condition ($lock.source.sourceDateEpoch -is [long] -or $lock.source.sourceDateEpoch -is [int]) `
  -Message 'SOURCE_DATE_EPOCH is not pinned.'
Assert-Text -Condition ($lock.artifact.buildId -match '^nss-llamacpp-[0-9a-f]{8}-[0-9a-f]{8}-lc[0-9]+-arm64-v8a$') `
  -Message 'The AAR build ID is missing or malformed.'

$requiredToolchain = [ordered]@{
  jdk = '17'
  gradle = '8.11.1'
  agp = '8.9.1'
  kotlin = '2.2.20'
  ndk = '28.2.13676358'
  cmake = '3.22.1'
  abi = 'arm64-v8a'
  minSdk = '24'
  architecture = 'armv8-a'
}
foreach ($key in $requiredToolchain.Keys) {
  Assert-Text `
    -Condition ([string]$lock.toolchain.$key -eq $requiredToolchain[$key]) `
    -Message "Toolchain pin mismatch for $key."
}
$pinnedPatches = @($lock.patches)
Assert-Text -Condition ($pinnedPatches.Count -eq 4) `
  -Message 'Exactly four numbered audit patches are required.'
for ($patchIndex = 0; $patchIndex -lt $pinnedPatches.Count; $patchIndex++) {
  $patch = $pinnedPatches[$patchIndex]
  $expectedPrefix = '{0:D4}-' -f ($patchIndex + 1)
  Assert-Text -Condition ($patch.path -match "/patches/$expectedPrefix[^/]+\.patch$") `
    -Message "Patch path is not numbered: $($patch.path)"
  Assert-Text -Condition ($patch.sha256 -match '^[0-9a-f]{64}$') `
    -Message "Patch SHA-256 is malformed: $($patch.path)"
  $patchPath = Resolve-LlmRepoPath -RepoRoot $RepoRoot -RelativePath $patch.path
  Assert-Text -Condition (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    -Message "Pinned patch is missing: $($patch.path)"
  Assert-Text -Condition ((Get-LlmSha256 -Path $patchPath) -eq $patch.sha256) `
    -Message "Pinned patch checksum mismatch: $($patch.path)"
  $provenancePatch = @(
    $provenance.source.patches |
      Where-Object { $_.path -eq $patch.path }
  )
  Assert-Text `
    -Condition ($provenancePatch.Count -eq 1 -and
      $provenancePatch[0].sha256 -eq $patch.sha256) `
    -Message "Provenance patch record does not match source-lock.json: $($patch.path)"
}

Assert-Text -Condition (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) `
  -Message 'The source file hash manifest is missing.'
$sourceManifestHash = Get-LlmSha256 -Path $sourceManifestPath
Assert-Text -Condition ($sourceManifestHash -eq $lock.source.sourceManifestSha256) `
  -Message 'Source manifest checksum does not match source-lock.json.'
Assert-Text -Condition ($sourceManifestHash -eq $provenance.source.manifestSha256) `
  -Message 'Source manifest checksum does not match provenance.'

Assert-Text -Condition ($provenance.buildId -eq $lock.artifact.buildId) `
  -Message 'Provenance build ID does not match source-lock.json.'
Assert-Text -Condition ($provenance.source.commit -eq $lock.source.commit) `
  -Message 'Provenance source commit does not match source-lock.json.'
Assert-Text -Condition ($provenance.source.archiveSha256 -eq $lock.source.archiveSha256) `
  -Message 'Provenance source archive checksum does not match source-lock.json.'
Assert-Text -Condition ([bool]$provenance.reproducibility.verified) `
  -Message 'Provenance does not attest a verified reproducible build.'
Assert-Text -Condition ([int]$provenance.reproducibility.rebuildCount -ge 2) `
  -Message 'Provenance has fewer than two clean rebuilds.'

$artifactPath = Resolve-LlmRepoPath `
  -RepoRoot $RepoRoot `
  -RelativePath $lock.artifact.path
Assert-Text -Condition ($provenance.artifact.path -eq $lock.artifact.path) `
  -Message 'Provenance artifact path does not match source-lock.json.'
Assert-Text -Condition (Test-Path -LiteralPath $artifactPath -PathType Leaf) `
  -Message "Pinned AAR is missing: $($lock.artifact.path)"
$artifactHash = Get-LlmSha256 -Path $artifactPath
$artifactSize = (Get-Item -LiteralPath $artifactPath).Length
Assert-Text -Condition ($artifactHash -eq $provenance.artifact.sha256) `
  -Message 'Pinned AAR checksum does not match provenance.'
Assert-Text -Condition ($artifactSize -eq [long]$provenance.artifact.size) `
  -Message 'Pinned AAR size does not match provenance.'
Assert-Text -Condition ($artifactHash -eq $provenance.reproducibility.artifactSha256) `
  -Message 'Reproducibility artifact checksum does not match the AAR.'
Assert-Text -Condition ($artifactSize -eq [long]$provenance.reproducibility.artifactSize) `
  -Message 'Reproducibility artifact size does not match the AAR.'

$entryRecords = @(Get-LlmAarEntryRecords -AarPath $artifactPath)
$duplicates = @(
  $entryRecords |
    Group-Object { $_.Path.ToLowerInvariant() } |
    Where-Object Count -gt 1
)
Assert-Text -Condition ($duplicates.Count -eq 0) -Message 'AAR contains duplicate entries.'
$nativeRecords = @(
  $entryRecords |
    Where-Object { $_.Path -match '^jni/[^/]+/[^/]+\.so$' }
)
Assert-Text `
  -Condition ($nativeRecords.Count -eq 1 -and
    $nativeRecords[0].Path -eq 'jni/arm64-v8a/librnllama_v8.so') `
  -Message 'AAR does not contain exactly the pinned arm64 native library.'
Assert-ArraysEqual `
  -Actual @($provenance.artifact.abis) `
  -Expected @('arm64-v8a') `
  -Message 'Provenance ABI list is not the pinned baseline.'
Assert-ArraysEqual `
  -Actual @($provenance.artifact.nativeLibraries) `
  -Expected @('jni/arm64-v8a/librnllama_v8.so') `
  -Message 'Provenance native library list is not the pinned baseline.'

Assert-Text -Condition (Test-Path -LiteralPath $entryHashesPath -PathType Leaf) `
  -Message 'AAR entry hash manifest is missing.'
$entryManifestHash = Get-LlmSha256 -Path $entryHashesPath
Assert-Text `
  -Condition ($entryManifestHash -eq $provenance.artifact.entryManifestSha256) `
  -Message 'AAR entry hash manifest checksum does not match provenance.'
$expectedEntries = @{}
foreach ($line in Get-Content -LiteralPath $entryHashesPath) {
  if ([string]::IsNullOrWhiteSpace($line)) {
    continue
  }
  Assert-Text -Condition ($line -match '^([0-9a-f]{64})  (.+)$') `
    -Message "Malformed AAR entry hash line: $line"
  $expectedEntries[$Matches[2]] = $Matches[1]
}
Assert-Text -Condition ($expectedEntries.Count -eq $entryRecords.Count) `
  -Message 'AAR entry hash manifest entry count differs from the artifact.'
foreach ($entry in $entryRecords) {
  Assert-Text -Condition ($expectedEntries.ContainsKey($entry.Path)) `
    -Message "AAR entry is not pinned: $($entry.Path)"
  Assert-Text -Condition ($expectedEntries[$entry.Path] -eq $entry.Sha256) `
    -Message "AAR entry checksum mismatch: $($entry.Path)"
}

$classAudit = Get-LlmClassAudit -AarPath $artifactPath
foreach ($requiredClass in @($lock.audit.requiredClasses)) {
  Assert-Text -Condition ($classAudit.ClassNames -contains $requiredClass) `
    -Message "Required AAR class is missing: $requiredClass"
}
foreach ($forbiddenClass in @($lock.audit.forbiddenClasses)) {
  Assert-Text -Condition ($classAudit.ClassNames -notcontains $forbiddenClass) `
    -Message "Forbidden AAR class is present: $forbiddenClass"
}
Assert-Text -Condition (@($classAudit.ForbiddenConstantsFound).Count -eq 0) `
  -Message 'Sensitive Kotlin logging constant found in classes.jar.'
Assert-Text `
  -Condition (Test-LlmClassArchiveContainsString -AarPath $artifactPath -Value $lock.artifact.buildId) `
  -Message 'classes.jar does not contain the pinned AAR build ID.'
Assert-ArraysEqual `
  -Actual @($provenance.artifact.classes) `
  -Expected @($classAudit.ClassNames) `
  -Message 'Provenance class list does not match classes.jar.'

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
Assert-Text -Condition (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) `
  -Message 'Pinned Android SDK was not found for ELF audit.'
$AndroidSdkRoot = (Resolve-Path -LiteralPath $AndroidSdkRoot).Path
$ndkBin = Join-Path $AndroidSdkRoot `
  "ndk\$($lock.toolchain.ndk)\toolchains\llvm\prebuilt\windows-x86_64\bin"
$readElf = Join-Path $ndkBin 'llvm-readelf.exe'
$nm = Join-Path $ndkBin 'llvm-nm.exe'
$stringsTool = Join-Path $ndkBin 'llvm-strings.exe'
$objdump = Join-Path $ndkBin 'llvm-objdump.exe'
foreach ($tool in @($readElf, $nm, $stringsTool, $objdump)) {
  Assert-Text -Condition (Test-Path -LiteralPath $tool -PathType Leaf) `
    -Message "Pinned ELF audit tool is missing: $tool"
}
$nativeBytes = Get-LlmZipEntryBytes `
  -ZipPath $artifactPath `
  -EntryPath $nativeRecords[0].Path
$nativeTempPath = Join-Path ([IO.Path]::GetTempPath()) `
  "nss-llm-gate-$([guid]::NewGuid().ToString('N')).so"
try {
  [IO.File]::WriteAllBytes($nativeTempPath, [byte[]]$nativeBytes)
  $actualElf = Get-LlmElfAudit `
    -NativePath $nativeTempPath `
    -ReadElfPath $readElf `
    -NmPath $nm `
    -StringsPath $stringsTool `
    -ObjdumpPath $objdump `
    -ForbiddenSymbolNames @($lock.audit.forbiddenUndefinedSymbols) `
    -ForbiddenInstructionNames @($lock.audit.forbiddenInstructions)
}
finally {
  if (Test-Path -LiteralPath $nativeTempPath -PathType Leaf) {
    Remove-Item -LiteralPath $nativeTempPath -Force
  }
}
Assert-Text -Condition ($actualElf.Sha256 -eq $nativeRecords[0].Sha256) `
  -Message 'ELF audit input does not match the pinned AAR entry.'
Assert-Text -Condition ($actualElf.Class -eq 'ELF64' -and
  $actualElf.Machine -eq 'AArch64' -and $actualElf.Type -eq 'DYN') `
  -Message 'ELF ABI or object type is not the pinned baseline.'
Assert-Text -Condition ($actualElf.Soname -eq 'librnllama_v8.so') `
  -Message 'ELF SONAME is not pinned.'
Assert-ArraysEqual -Actual @($actualElf.Needed) `
  -Expected @($lock.audit.allowedNativeDependencies) `
  -Message 'ELF dependency list is outside the allowlist.'
Assert-Text -Condition (@($actualElf.ForbiddenUndefinedSymbols).Count -eq 0) `
  -Message 'ELF imports a forbidden logging or network symbol.'
Assert-Text -Condition (@($actualElf.ForbiddenInstructions).Count -eq 0) `
  -Message 'ELF contains an instruction outside the armv8-a baseline.'
Assert-Text -Condition (@($actualElf.HostPathStrings).Count -eq 0) `
  -Message 'ELF contains a host path string.'
Assert-Text -Condition (@($actualElf.ForbiddenRuntimeMarkers).Count -eq 0) `
  -Message 'ELF contains a forbidden runtime log marker.'
foreach ($requiredExport in @($lock.audit.requiredJniExports)) {
  Assert-Text -Condition ($actualElf.JniExports -contains $requiredExport) `
    -Message "Required JNI export is missing: $requiredExport"
}

Assert-Text -Condition (Test-Path -LiteralPath $elfAuditPath -PathType Leaf) `
  -Message 'ELF audit record is missing.'
Assert-Text `
  -Condition ((Get-LlmSha256 -Path $elfAuditPath) -eq $provenance.artifact.elfAuditSha256) `
  -Message 'ELF audit record checksum does not match provenance.'
Assert-Text -Condition ($committedElfAudit.artifactSha256 -eq $artifactHash) `
  -Message 'Committed ELF audit artifact checksum does not match the AAR.'
Assert-Text -Condition ($committedElfAudit.librarySha256 -eq $actualElf.Sha256) `
  -Message 'Committed ELF audit library checksum does not match the AAR.'
foreach ($key in @('elfClass', 'machine', 'type', 'soname', 'buildId')) {
  $actualKey = switch ($key) {
    'elfClass' { 'Class' }
    'machine' { 'Machine' }
    'type' { 'Type' }
    'soname' { 'Soname' }
    'buildId' { 'BuildId' }
  }
  Assert-Text `
    -Condition ([string]$committedElfAudit.$key -eq [string]$actualElf.$actualKey) `
    -Message "Committed ELF audit field does not match the artifact: $key"
}
Assert-ArraysEqual -Actual @($committedElfAudit.needed) -Expected @($actualElf.Needed) `
  -Message 'Committed ELF dependency audit does not match the artifact.'
Assert-ArraysEqual -Actual @($committedElfAudit.jniExports) -Expected @($actualElf.JniExports) `
  -Message 'Committed ELF JNI audit does not match the artifact.'
Assert-Text -Condition (@($committedElfAudit.forbiddenUndefinedSymbols).Count -eq 0) `
  -Message 'Committed ELF audit contains forbidden imports.'
Assert-Text -Condition (@($committedElfAudit.forbiddenInstructions).Count -eq 0) `
  -Message 'Committed ELF audit contains forbidden baseline instructions.'
Assert-Text -Condition (@($committedElfAudit.hostPathStrings).Count -eq 0) `
  -Message 'Committed ELF audit contains host paths.'
Assert-Text -Condition (@($committedElfAudit.forbiddenRuntimeMarkers).Count -eq 0) `
  -Message 'Committed ELF audit contains forbidden runtime markers.'

Assert-Text -Condition ($sbom.bomFormat -eq 'CycloneDX' -and $sbom.specVersion -eq '1.5') `
  -Message 'Committed SBOM is not CycloneDX 1.5.'
Assert-Text `
  -Condition ($sbom.metadata.component.hashes[0].content -eq $artifactHash) `
  -Message 'SBOM artifact checksum does not match the AAR.'
Assert-Text `
  -Condition ($sbom.metadata.component.version -eq $lock.artifact.buildId) `
  -Message 'SBOM artifact build ID does not match source-lock.json.'
Assert-Text `
  -Condition ($sbom.components[0].version -eq $lock.source.commit) `
  -Message 'SBOM wrapper component is not pinned to the source commit.'
Assert-Text `
  -Condition ($sbom.components[0].hashes[0].content -eq $lock.source.archiveSha256) `
  -Message 'SBOM wrapper checksum does not match source-lock.json.'
Assert-Text `
  -Condition ($sbom.components[1].version -eq $lock.source.vendoredLlamaCppTree) `
  -Message 'SBOM llama.cpp component is not pinned to the source tree.'

$legacyPaths = @(
  'android\third_party\llamacpp-kotlin-0.2.0-huawei-safe.aar',
  'android\third_party\llamacpp_patch_work',
  'android\silent_llama_bridge'
)
foreach ($legacyRelativePath in $legacyPaths) {
  Assert-Text `
    -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $legacyRelativePath)) ) `
    -Message "Legacy LLM artifact or bridge is still present: $legacyRelativePath"
}
$appGradle = Get-Content -LiteralPath (Join-Path $RepoRoot 'android\app\build.gradle.kts') -Raw
$settingsGradle = Get-Content -LiteralPath (Join-Path $RepoRoot 'android\settings.gradle.kts') -Raw
$artifactFileName = [IO.Path]::GetFileName($artifactPath)
Assert-Text -Condition $appGradle.Contains($artifactFileName, [StringComparison]::Ordinal) `
  -Message 'App Gradle does not consume the pinned LLM AAR.'
foreach ($legacyMarker in @('silent_llama_bridge', 'pickFirsts')) {
  Assert-Text -Condition (-not $appGradle.Contains($legacyMarker, [StringComparison]::Ordinal)) `
    -Message "Legacy app Gradle integration is still present: $legacyMarker"
  Assert-Text -Condition (-not $settingsGradle.Contains($legacyMarker, [StringComparison]::Ordinal)) `
    -Message "Legacy settings Gradle integration is still present: $legacyMarker"
}
$jniPackaging = [regex]::Match(
  $appGradle,
  '(?s)packaging\s*\{\s*jniLibs\s*\{(?<body>.*?)\}\s*\}'
)
$legacyAppJniRoot = Join-Path $RepoRoot 'android\app\src\main\jniLibs'
if (Test-Path -LiteralPath $legacyAppJniRoot -PathType Container) {
  $legacyAppJniLibraries = @(
    Get-ChildItem -LiteralPath $legacyAppJniRoot -Recurse -File -Filter 'librnllama*.so'
  )
  foreach ($legacyLibrary in $legacyAppJniLibraries) {
    $relativeLibraryPath = [IO.Path]::GetRelativePath(
      $legacyAppJniRoot,
      $legacyLibrary.FullName
    ).Replace('\', '/')
    $packagedLibraryPath = "lib/$relativeLibraryPath"
    $isExplicitlyExcluded = $jniPackaging.Success -and
      $jniPackaging.Groups['body'].Value.Contains(
        'excludes',
        [StringComparison]::Ordinal
      ) -and
      $jniPackaging.Groups['body'].Value.Contains(
        "`"$packagedLibraryPath`"",
        [StringComparison]::Ordinal
      )
    Assert-Text -Condition $isExplicitlyExcluded `
      -Message "Legacy app JNI library is not excluded from packaging: $packagedLibraryPath"
  }
}

if (-not $SkipRebuild) {
  $buildScript = Join-Path $RepoRoot 'scripts\llm\Build-LlmAar.ps1'
  Assert-Text -Condition (Test-Path -LiteralPath $buildScript -PathType Leaf) `
    -Message 'Reproducible LLM AAR build script is missing.'
  $arguments = @(
    '-NoProfile',
    '-File',
    $buildScript,
    '-VerifyCommittedArtifact',
    '-RebuildCount',
    '2'
  )
  if ($Offline) {
    $arguments += '-Offline'
  }
  if (-not [string]::IsNullOrWhiteSpace($BuildRoot)) {
    $arguments += @('-BuildRoot', $BuildRoot)
  }
  & pwsh @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "LLM AAR rebuild verification exited with code $LASTEXITCODE"
  }
}

Write-Host "Phase 6 LLM AAR provenance gate passed: $artifactHash"
