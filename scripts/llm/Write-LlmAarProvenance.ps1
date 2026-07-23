[CmdletBinding()]
param(
  [string]$RepoRoot = '',

  [Parameter(Mandatory = $true)]
  [string]$RebuildResultPath,

  [string]$AndroidSdkRoot = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LlmAarCommon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'LlmAarAudit.psm1') -Force

function Write-DeterministicJson {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [object]$Value
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $json = $Value | ConvertTo-Json -Depth 100
  $normalized = $json.Replace("`r`n", "`n").Replace("`r", "`n")
  [IO.File]::WriteAllText(
    $Path,
    ($normalized + "`n"),
    [Text.UTF8Encoding]::new($false)
  )
}

function Assert-Value {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Assert-LlmCondition -Condition $Condition -Message $Message
}

function Get-CanonicalArrayJson {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Values
  )

  return ($Values | Sort-Object | ConvertTo-Json -Compress)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
$RebuildResultPath = (Resolve-Path -LiteralPath $RebuildResultPath).Path

$lock = Read-LlmSourceLock -RepoRoot $RepoRoot
$result = Get-Content -LiteralPath $RebuildResultPath -Raw | ConvertFrom-Json -Depth 100
Assert-Value `
  -Condition ($result.reproducible -eq $true -and [int]$result.rebuildCount -ge 2) `
  -Message 'A provenance record requires at least two successful clean rebuilds.'

$artifactPath = Resolve-LlmRepoPath `
  -RepoRoot $RepoRoot `
  -RelativePath $lock.artifact.path
Assert-Value `
  -Condition (Test-Path -LiteralPath $artifactPath -PathType Leaf) `
  -Message "Built artifact is missing: $artifactPath"
$artifactHash = Get-LlmSha256 -Path $artifactPath
$artifactSize = (Get-Item -LiteralPath $artifactPath).Length
Assert-Value `
  -Condition ($artifactHash -eq $result.artifactSha256) `
  -Message 'Rebuild result does not match the committed artifact hash.'
Assert-Value `
  -Condition ($artifactSize -eq [long]$result.artifactSize) `
  -Message 'Rebuild result does not match the committed artifact size.'
Assert-Value `
  -Condition ($artifactHash -match '^[0-9a-f]{64}$') `
  -Message 'Artifact SHA-256 is malformed.'

$metadataRoot = Join-Path $RepoRoot 'android\third_party\llamacpp'
$entryHashesPath = Join-Path $metadataRoot 'aar-entry-hashes.sha256'
$provenancePath = Join-Path $metadataRoot 'provenance.json'
$sbomPath = Join-Path $metadataRoot 'sbom.cdx.json'
$elfAuditPath = Join-Path $metadataRoot 'elf-audit.json'
$sourceManifestPath = Join-Path $metadataRoot 'source-files.sha256'

$entryRecords = @(Get-LlmAarEntryRecords -AarPath $artifactPath | Sort-Object Path)
Assert-Value -Condition ($entryRecords.Count -gt 0) -Message 'AAR has no file entries.'
Write-LlmHashManifest -Path $entryHashesPath -Records $entryRecords
$entryManifestHash = Get-LlmSha256 -Path $entryHashesPath

$nativeRecords = @(
  $entryRecords |
    Where-Object { $_.Path -match '^jni/([^/]+)/([^/]+\.so)$' }
)
Assert-Value `
  -Condition ($nativeRecords.Count -eq 1) `
  -Message 'The pinned AAR must contain exactly one native library.'
$nativePath = $nativeRecords[0].Path
Assert-Value `
  -Condition ($nativePath -eq 'jni/arm64-v8a/librnllama_v8.so') `
  -Message "Unexpected native library path: $nativePath"

$abis = @(
  $nativeRecords |
    ForEach-Object {
      [regex]::Match($_.Path, '^jni/([^/]+)/').Groups[1].Value
    } |
    Sort-Object -Unique
)
Assert-Value `
  -Condition ($abis.Count -eq 1 -and $abis[0] -eq 'arm64-v8a') `
  -Message 'The pinned AAR must contain only the arm64-v8a ABI.'

$classAudit = Get-LlmClassAudit -AarPath $artifactPath
foreach ($requiredClass in @($lock.audit.requiredClasses)) {
  Assert-Value `
    -Condition ($classAudit.ClassNames -contains $requiredClass) `
    -Message "Required class is missing: $requiredClass"
}
foreach ($forbiddenClass in @($lock.audit.forbiddenClasses)) {
  Assert-Value `
    -Condition ($classAudit.ClassNames -notcontains $forbiddenClass) `
    -Message "Forbidden class is present: $forbiddenClass"
}
Assert-Value `
  -Condition (@($classAudit.ForbiddenConstantsFound).Count -eq 0) `
  -Message 'Sensitive Kotlin logging constants are present in classes.jar.'
Assert-Value `
  -Condition (Test-LlmClassArchiveContainsString `
    -AarPath $artifactPath `
    -Value $lock.artifact.buildId) `
  -Message 'classes.jar does not contain the pinned AAR build ID.'

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
Assert-Value `
  -Condition (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) `
  -Message 'Pinned Android SDK was not found for ELF audit.'
$AndroidSdkRoot = (Resolve-Path -LiteralPath $AndroidSdkRoot).Path
$ndkBin = Join-Path $AndroidSdkRoot `
  "ndk\$($lock.toolchain.ndk)\toolchains\llvm\prebuilt\windows-x86_64\bin"
$readElf = Join-Path $ndkBin 'llvm-readelf.exe'
$nm = Join-Path $ndkBin 'llvm-nm.exe'
$stringsTool = Join-Path $ndkBin 'llvm-strings.exe'
$objdump = Join-Path $ndkBin 'llvm-objdump.exe'
foreach ($tool in @($readElf, $nm, $stringsTool, $objdump)) {
  Assert-Value `
    -Condition (Test-Path -LiteralPath $tool -PathType Leaf) `
    -Message "Pinned ELF audit tool is missing: $tool"
}

$nativeBytes = Get-LlmZipEntryBytes -ZipPath $artifactPath -EntryPath $nativePath
$nativeTempPath = Join-Path ([IO.Path]::GetTempPath()) `
  "nss-llm-audit-$([guid]::NewGuid().ToString('N')).so"
try {
  [IO.File]::WriteAllBytes($nativeTempPath, [byte[]]$nativeBytes)
  $elfAudit = Get-LlmElfAudit `
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

Assert-Value -Condition ($elfAudit.Class -eq 'ELF64') -Message 'Native ELF is not ELF64.'
Assert-Value -Condition ($elfAudit.Machine -eq 'AArch64') -Message 'Native ELF is not AArch64.'
Assert-Value -Condition ($elfAudit.Type -eq 'DYN') -Message 'Native ELF is not a shared object.'
Assert-Value `
  -Condition ($elfAudit.Soname -eq 'librnllama_v8.so') `
  -Message 'Native ELF SONAME is not pinned.'
Assert-Value `
  -Condition ((Get-CanonicalArrayJson -Values @($elfAudit.Needed)) -eq
    (Get-CanonicalArrayJson -Values @($lock.audit.allowedNativeDependencies))) `
  -Message 'Native ELF dependencies do not match the allowlist.'
Assert-Value `
  -Condition (@($elfAudit.ForbiddenUndefinedSymbols).Count -eq 0) `
  -Message 'Native ELF imports a forbidden logging or network symbol.'
Assert-Value `
  -Condition (@($elfAudit.ForbiddenInstructions).Count -eq 0) `
  -Message 'Native ELF contains an instruction outside the armv8-a baseline.'
Assert-Value `
  -Condition (@($elfAudit.HostPathStrings).Count -eq 0) `
  -Message 'Native ELF contains a host path string.'
Assert-Value `
  -Condition (@($elfAudit.ForbiddenRuntimeMarkers).Count -eq 0) `
  -Message 'Native ELF contains a forbidden runtime logging marker.'
foreach ($requiredExport in @($lock.audit.requiredJniExports)) {
  Assert-Value `
    -Condition ($elfAudit.JniExports -contains $requiredExport) `
    -Message "Required JNI export is missing: $requiredExport"
}

$sourceManifestHash = Get-LlmSha256 -Path $sourceManifestPath
Assert-Value `
  -Condition ($sourceManifestHash -eq $lock.source.sourceManifestSha256) `
  -Message 'Source manifest does not match source-lock.json.'

$timestamp = [DateTimeOffset]::FromUnixTimeSeconds(
  [long]$lock.source.sourceDateEpoch
).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$artifactFileName = [IO.Path]::GetFileName($artifactPath)
$artifactComponent = [ordered]@{
  type = 'library'
  group = 'com.example.note-secret-search'
  name = $artifactFileName
  version = $lock.artifact.buildId
  hashes = @(
    [ordered]@{
      alg = 'SHA-256'
      content = $artifactHash
    }
  )
  purl = "pkg:generic/$artifactFileName@$artifactHash"
}
$wrapperComponent = [ordered]@{
  type = 'library'
  group = 'github.com/ljcamargo'
  name = 'kotlinllamacpp'
  version = $lock.source.commit
  hashes = @(
    [ordered]@{
      alg = 'SHA-256'
      content = $lock.source.archiveSha256
    }
  )
  purl = "pkg:github/ljcamargo/kotlinllamacpp@$($lock.source.commit)"
}
$llamaComponent = [ordered]@{
  type = 'library'
  name = 'llama.cpp'
  version = $lock.source.vendoredLlamaCppTree
  purl = "pkg:generic/llama.cpp@$($lock.source.vendoredLlamaCppTree)"
}

$elfRecord = [ordered]@{
  schemaVersion = 1
  artifactSha256 = $artifactHash
  libraryPath = $nativePath
  librarySha256 = $nativeRecords[0].Sha256
  librarySize = $nativeRecords[0].Length
  elfClass = $elfAudit.Class
  machine = $elfAudit.Machine
  type = $elfAudit.Type
  soname = $elfAudit.Soname
  needed = @($elfAudit.Needed)
  buildId = $elfAudit.BuildId
  jniExports = @($elfAudit.JniExports)
  forbiddenUndefinedSymbols = @($elfAudit.ForbiddenUndefinedSymbols)
  forbiddenInstructions = @($elfAudit.ForbiddenInstructions)
  hostPathStrings = @($elfAudit.HostPathStrings)
  forbiddenRuntimeMarkers = @($elfAudit.ForbiddenRuntimeMarkers)
}
Write-DeterministicJson -Path $elfAuditPath -Value $elfRecord
$elfAuditHash = Get-LlmSha256 -Path $elfAuditPath

$provenance = [ordered]@{
  schemaVersion = 1
  buildId = $lock.artifact.buildId
  source = [ordered]@{
    repository = $lock.source.repository
    commit = $lock.source.commit
    archiveUrl = $lock.source.archiveUrl
    archiveSha256 = $lock.source.archiveSha256
    vendoredLlamaCppTree = $lock.source.vendoredLlamaCppTree
    manifestSha256 = $sourceManifestHash
    sourceDateEpoch = [long]$lock.source.sourceDateEpoch
    patches = @(
      foreach ($patch in $lock.patches) {
        [ordered]@{
          path = $patch.path
          sha256 = $patch.sha256
        }
      }
    )
  }
  toolchain = $lock.toolchain
  build = $lock.build
  reproducibility = [ordered]@{
    verified = $true
    rebuildCount = [int]$result.rebuildCount
    artifactSha256 = $artifactHash
    artifactSize = [long]$artifactSize
  }
  artifact = [ordered]@{
    path = $lock.artifact.path
    sha256 = $artifactHash
    size = [long]$artifactSize
    abis = @($abis)
    nativeLibraries = @($nativeRecords | ForEach-Object Path)
    entryManifestPath = 'android/third_party/llamacpp/aar-entry-hashes.sha256'
    entryManifestSha256 = $entryManifestHash
    elfAuditPath = 'android/third_party/llamacpp/elf-audit.json'
    elfAuditSha256 = $elfAuditHash
    classes = @($classAudit.ClassNames)
  }
  audit = [ordered]@{
    requiredClasses = @($lock.audit.requiredClasses)
    forbiddenClasses = @($lock.audit.forbiddenClasses)
    requiredJniExports = @($lock.audit.requiredJniExports)
    allowedNativeDependencies = @($lock.audit.allowedNativeDependencies)
    forbiddenUndefinedSymbols = @($lock.audit.forbiddenUndefinedSymbols)
    forbiddenInstructions = @($lock.audit.forbiddenInstructions)
    forbiddenClassConstantsFound = @($classAudit.ForbiddenConstantsFound)
  }
}
Write-DeterministicJson -Path $provenancePath -Value $provenance

$sbom = [ordered]@{
  bomFormat = 'CycloneDX'
  specVersion = '1.5'
  serialNumber = "urn:uuid:$($artifactHash.Substring(0, 8))-$($artifactHash.Substring(8, 4))-5$($artifactHash.Substring(13, 3))-8$($artifactHash.Substring(16, 3))-$($artifactHash.Substring(19, 12))"
  version = 1
  metadata = [ordered]@{
    timestamp = $timestamp
    component = $artifactComponent
  }
  components = @(
    $wrapperComponent
    $llamaComponent
  )
  dependencies = @(
    [ordered]@{
      ref = $artifactComponent.purl
      dependsOn = @(
        $wrapperComponent.purl
        $llamaComponent.purl
      )
    }
  )
}
Write-DeterministicJson -Path $sbomPath -Value $sbom

[ordered]@{
  artifactSha256 = $artifactHash
  artifactSize = [long]$artifactSize
  entryManifestSha256 = $entryManifestHash
  elfAuditSha256 = $elfAuditHash
  provenancePath = 'android/third_party/llamacpp/provenance.json'
  sbomPath = 'android/third_party/llamacpp/sbom.cdx.json'
} | ConvertTo-Json -Depth 10
