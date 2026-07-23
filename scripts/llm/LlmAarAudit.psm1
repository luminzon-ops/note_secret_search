Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LlmAarCommon.psm1')

function Get-LlmZipEntryBytes {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [Parameter(Mandatory = $true)]
    [string]$EntryPath
  )

  Add-Type -AssemblyName System.IO.Compression
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $archive.GetEntry($EntryPath)
    Assert-LlmCondition `
      -Condition ($null -ne $entry) `
      -Message "ZIP entry is missing: $EntryPath"
    $memory = [IO.MemoryStream]::new()
    try {
      $stream = $entry.Open()
      try {
        $stream.CopyTo($memory)
      }
      finally {
        $stream.Dispose()
      }
      return ,$memory.ToArray()
    }
    finally {
      $memory.Dispose()
    }
  }
  finally {
    $archive.Dispose()
  }
}

function Get-LlmAarEntryRecords {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AarPath
  )

  return @(
    foreach ($record in Get-LlmZipRecords -ZipPath $AarPath) {
      [pscustomobject]@{
        Path = $record.Path
        Length = [long]$record.Bytes.Length
        Sha256 = Get-LlmSha256Bytes -Bytes $record.Bytes
      }
    }
  )
}

function Get-LlmClassAudit {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AarPath
  )

  $classesBytes = Get-LlmZipEntryBytes -ZipPath $AarPath -EntryPath 'classes.jar'
  $memory = [IO.MemoryStream]::new($classesBytes, $false)
  $classes = [IO.Compression.ZipArchive]::new(
    $memory,
    [IO.Compression.ZipArchiveMode]::Read,
    $false
  )
  try {
    $classNames = @(
      $classes.Entries |
        Where-Object { $_.FullName.EndsWith('.class', [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object FullName |
        Sort-Object
    )
    $forbidden = @(
      'android/util/Log',
      'completion $id of $params',
      'CPU features:',
      'Primary ABI:',
      'will start llama context with config:',
      'Context loaded successfully with ID:',
      'RNLlamaContext',
      'RNLLAMA_ANDROID_JNI'
    )
    $found = [Collections.Generic.List[string]]::new()
    foreach ($entry in $classes.Entries) {
      if (-not $entry.FullName.EndsWith('.class', [StringComparison]::OrdinalIgnoreCase)) {
        continue
      }
      $stream = $entry.Open()
      $reader = [IO.BinaryReader]::new($stream)
      try {
        $text = [Text.Encoding]::Latin1.GetString(
          $reader.ReadBytes([int]$entry.Length)
        )
      }
      finally {
        $reader.Dispose()
        $stream.Dispose()
      }
      foreach ($marker in $forbidden) {
        if ($text.Contains($marker, [StringComparison]::Ordinal)) {
          $found.Add("$($entry.FullName):$marker")
        }
      }
    }
    return [pscustomobject]@{
      ClassNames = $classNames
      RequiredClasses = @(
        'com/example/nssllama/SilentLlamaContext.class',
        'org/nehuatl/llamacpp/LlamaContext.class'
      )
      ForbiddenClasses = @(
        'org/nehuatl/llamacpp/LlamaAndroid.class',
        'org/nehuatl/llamacpp/LlamaHelper.class'
      )
      ForbiddenConstantsFound = @($found)
    }
  }
  finally {
    $classes.Dispose()
    $memory.Dispose()
  }
}

function Test-LlmClassArchiveContainsString {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AarPath,
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $classesBytes = Get-LlmZipEntryBytes -ZipPath $AarPath -EntryPath 'classes.jar'
  $memory = [IO.MemoryStream]::new($classesBytes, $false)
  $classes = [IO.Compression.ZipArchive]::new(
    $memory,
    [IO.Compression.ZipArchiveMode]::Read,
    $false
  )
  try {
    foreach ($entry in $classes.Entries) {
      if (-not $entry.FullName.EndsWith('.class', [StringComparison]::OrdinalIgnoreCase)) {
        continue
      }
      $stream = $entry.Open()
      $reader = [IO.BinaryReader]::new($stream)
      try {
        $text = [Text.Encoding]::Latin1.GetString(
          $reader.ReadBytes([int]$entry.Length)
        )
      }
      finally {
        $reader.Dispose()
        $stream.Dispose()
      }
      if ($text.Contains($Value, [StringComparison]::Ordinal)) {
        return $true
      }
    }
    return $false
  }
  finally {
    $classes.Dispose()
    $memory.Dispose()
  }
}

function Invoke-LlmToolCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $output = (& $FilePath @Arguments 2>&1 | Out-String)
  $exitCode = $LASTEXITCODE
  Assert-LlmCondition `
    -Condition ($exitCode -eq 0) `
    -Message "$FilePath exited with code $exitCode."
  return $output
}

function Get-LlmElfAudit {
  param(
    [Parameter(Mandatory = $true)]
    [string]$NativePath,
    [Parameter(Mandatory = $true)]
    [string]$ReadElfPath,
    [Parameter(Mandatory = $true)]
    [string]$NmPath,
    [Parameter(Mandatory = $true)]
    [string]$StringsPath,
    [Parameter(Mandatory = $true)]
    [string]$ObjdumpPath,
    [string[]]$ForbiddenSymbolNames = @(),
    [string[]]$ForbiddenInstructionNames = @()
  )

  $header = Invoke-LlmToolCapture `
    -FilePath $ReadElfPath `
    -Arguments @('-h', '-d', '-n', $NativePath)
  $defined = Invoke-LlmToolCapture `
    -FilePath $NmPath `
    -Arguments @('-D', '--defined-only', '--format=posix', $NativePath)
  $undefined = Invoke-LlmToolCapture `
    -FilePath $NmPath `
    -Arguments @('-D', '--undefined-only', '--format=posix', $NativePath)
  $strings = Invoke-LlmToolCapture `
    -FilePath $StringsPath `
    -Arguments @('-a', $NativePath)
  $disassembly = Invoke-LlmToolCapture `
    -FilePath $ObjdumpPath `
    -Arguments @('-d', $NativePath)

  $needed = @(
    [regex]::Matches($header, '\(NEEDED\).*?\[([^\]]+)\]') |
      ForEach-Object { $_.Groups[1].Value } |
      Sort-Object -Unique
  )
  $sonameMatch = [regex]::Match($header, '\(SONAME\).*?\[([^\]]+)\]')
  $buildIdMatch = [regex]::Match(
    $header,
    'Build ID:\s*([0-9a-f]+)',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
  $jniExports = @(
    $defined -split "`r?`n" |
      Where-Object { $_ -match '\bJava_[A-Za-z0-9_]+' } |
      ForEach-Object { ($_ -split '\s+')[0] } |
      Sort-Object -Unique
  )
  $undefinedSymbols = @(
    $undefined -split "`r?`n" |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object {
        (($_ -split '\s+')[0] -split '@')[0]
      } |
      Sort-Object -Unique
  )
  $forbiddenUndefined = @(
    $undefinedSymbols |
      Where-Object { $ForbiddenSymbolNames -contains $_ } |
      Sort-Object -Unique
  )
  $instructionMnemonics = @(
    $disassembly -split "`r?`n" |
      ForEach-Object {
        $match = [regex]::Match(
          $_,
          '^\s*[0-9a-f]+:\s+(?:[0-9a-f]{8}\s+)?([a-z][a-z0-9.]*)\b',
          [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
          $match.Groups[1].Value.ToLowerInvariant()
        }
      } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Sort-Object -Unique
  )
  $forbiddenInstructions = @(
    $instructionMnemonics |
      Where-Object { $ForbiddenInstructionNames -contains $_ } |
      Sort-Object -Unique
  )
  $hostPaths = @(
    $strings -split "`r?`n" |
      Where-Object {
        $_ -match '^[A-Za-z]:[\\/]' -or
          $_ -match '^/(Users|home|private|tmp)/' -or
          $_ -match 'nss-llm-aar' -or
          $_ -match '\.note_secret_search_quality_cache'
      } |
      Sort-Object -Unique
  )
  $forbiddenRuntimeMarkers = @(
    $strings -split "`r?`n" |
      Where-Object {
        $_ -match '__android_log_(print|write|vprint)' -or
          $_ -eq 'completion $id of $params' -or
          $_ -eq 'will start llama context with config:'
      } |
      Sort-Object -Unique
  )

  return [pscustomobject]@{
    Sha256 = Get-LlmSha256 -Path $NativePath
    Size = (Get-Item -LiteralPath $NativePath).Length
    Class = if ($header -match 'Class:\s+ELF64') { 'ELF64' } else { '' }
    Machine = if ($header -match 'Machine:\s+AArch64') { 'AArch64' } else { '' }
    Type = if ($header -match 'Type:\s+DYN') { 'DYN' } else { '' }
    Soname = if ($sonameMatch.Success) { $sonameMatch.Groups[1].Value } else { '' }
    Needed = $needed
    BuildId = if ($buildIdMatch.Success) {
      $buildIdMatch.Groups[1].Value.ToLowerInvariant()
    }
    else {
      ''
    }
    JniExports = $jniExports
    UndefinedSymbols = $undefinedSymbols
    ForbiddenUndefinedSymbols = $forbiddenUndefined
    InstructionMnemonics = $instructionMnemonics
    ForbiddenInstructions = $forbiddenInstructions
    HostPathStrings = $hostPaths
    ForbiddenRuntimeMarkers = $forbiddenRuntimeMarkers
  }
}

Export-ModuleMember -Function @(
  'Get-LlmZipEntryBytes',
  'Get-LlmAarEntryRecords',
  'Get-LlmClassAudit',
  'Test-LlmClassArchiveContainsString',
  'Invoke-LlmToolCapture',
  'Get-LlmElfAudit'
)
