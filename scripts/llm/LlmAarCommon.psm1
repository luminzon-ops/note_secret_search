Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-LlmCondition {
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

function Get-LlmSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LlmSha256Bytes {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [byte[]]$Bytes
  )

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToHexString($sha.ComputeHash($Bytes)).ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function Resolve-LlmRepoPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $candidate = [IO.Path]::GetFullPath(
    (Join-Path $RepoRoot $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
  )
  $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  ) + [IO.Path]::DirectorySeparatorChar
  Assert-LlmCondition `
    -Condition $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) `
    -Message "Path escapes repository root: $RelativePath"
  return $candidate
}

function Read-LlmSourceLock {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $path = Join-Path $RepoRoot 'android\third_party\llamacpp\source-lock.json'
  Assert-LlmCondition `
    -Condition (Test-Path -LiteralPath $path -PathType Leaf) `
    -Message "Missing source lock: $path"
  return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
}

function Get-LlmZipRecords {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
  )

  Add-Type -AssemblyName System.IO.Compression
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $records = foreach ($entry in $archive.Entries) {
      if ([string]::IsNullOrEmpty($entry.Name)) {
        continue
      }
      $memory = [IO.MemoryStream]::new()
      try {
        $stream = $entry.Open()
        try {
          $stream.CopyTo($memory)
        }
        finally {
          $stream.Dispose()
        }
        [pscustomobject]@{
          Path = $entry.FullName.Replace('\', '/')
          Bytes = $memory.ToArray()
        }
      }
      finally {
        $memory.Dispose()
      }
    }
    return @($records)
  }
  finally {
    $archive.Dispose()
  }
}

function Write-LlmNormalizedZip {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [long]$SourceDateEpoch
  )

  $records = @(Get-LlmZipRecords -ZipPath $InputPath) |
    Sort-Object Path
  $outputDirectory = Split-Path -Parent $OutputPath
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
  $file = [IO.File]::Open(
    $OutputPath,
    [IO.FileMode]::Create,
    [IO.FileAccess]::Write,
    [IO.FileShare]::None
  )
  $archive = [IO.Compression.ZipArchive]::new(
    $file,
    [IO.Compression.ZipArchiveMode]::Create,
    $false
  )
  try {
    $timestamp = [DateTimeOffset]::FromUnixTimeSeconds($SourceDateEpoch)
    foreach ($record in $records) {
      $entry = $archive.CreateEntry(
        $record.Path,
        [IO.Compression.CompressionLevel]::NoCompression
      )
      $entry.LastWriteTime = $timestamp
      $stream = $entry.Open()
      try {
        $stream.Write($record.Bytes, 0, $record.Bytes.Length)
      }
      finally {
        $stream.Dispose()
      }
    }
  }
  finally {
    $archive.Dispose()
    $file.Dispose()
  }
}

function Get-LlmSourceRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExtractRoot
  )

  $directories = @(Get-ChildItem -LiteralPath $ExtractRoot -Directory)
  if ($directories.Count -eq 1) {
    return $directories[0].FullName
  }
  return $ExtractRoot
}

function Get-LlmSourceManifestRecords {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
  )

  $records = foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($SourceRoot, $file.FullName).Replace('\', '/')
    $include = $relative -eq 'build.gradle.kts' -or
      $relative -eq 'settings.gradle.kts' -or
      $relative -eq 'gradle.properties' -or
      $relative -eq 'gradle/libs.versions.toml' -or
      $relative -eq 'gradle/wrapper/gradle-wrapper.jar' -or
      $relative -eq 'gradle/wrapper/gradle-wrapper.properties' -or
      $relative.StartsWith('llamaCpp/', [StringComparison]::Ordinal)
    if (-not $include) {
      continue
    }
    [pscustomobject]@{
      Path = $relative
      Sha256 = Get-LlmSha256 -Path $file.FullName
    }
  }
  return @($records | Sort-Object Path)
}

function ConvertTo-LlmHashManifest {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Records
  )

  $lines = foreach ($record in $Records) {
    "$($record.Sha256)  $($record.Path)"
  }
  return (($lines -join "`n") + "`n")
}

function Write-LlmHashManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [object[]]$Records
  )

  $encoding = [Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllText($Path, (ConvertTo-LlmHashManifest -Records $Records), $encoding)
}

function Invoke-LlmProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
  Push-Location $WorkingDirectory
  try {
    & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $LogPath
    $exitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
  Assert-LlmCondition `
    -Condition ($exitCode -eq 0) `
    -Message "$FilePath exited with code $exitCode. See $LogPath"
}

Export-ModuleMember -Function @(
  'Assert-LlmCondition',
  'Get-LlmSha256',
  'Get-LlmSha256Bytes',
  'Resolve-LlmRepoPath',
  'Read-LlmSourceLock',
  'Get-LlmZipRecords',
  'Write-LlmNormalizedZip',
  'Get-LlmSourceRoot',
  'Get-LlmSourceManifestRecords',
  'ConvertTo-LlmHashManifest',
  'Write-LlmHashManifest',
  'Invoke-LlmProcess'
)
