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

function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @()
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath exited with code $LASTEXITCODE"
  }
}

function Invoke-Adb {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $fullArguments = @('-s', $Serial) + $Arguments
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& $adb @fullArguments 2>&1)
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "adb -s $Serial $($Arguments -join ' ') exited with code $exitCode"
  }
  return [string[]]$output
}

function Invoke-AdbText {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  return ((Invoke-Adb -Arguments $Arguments) -join "`n").Trim()
}

function Invoke-AdbToFile {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  $errorPath = "$OutputPath.err"
  $process = Start-Process `
    -FilePath $adb `
    -ArgumentList (@('-s', $Serial) + $Arguments) `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $OutputPath `
    -RedirectStandardError $errorPath
  try {
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
      $errorText = Get-Content -LiteralPath $errorPath -Raw `
        -ErrorAction SilentlyContinue
      $outputBytes = if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        (Get-Item -LiteralPath $OutputPath).Length
      }
      else {
        0
      }
      if ($outputBytes -le 0 -or -not [string]::IsNullOrWhiteSpace($errorText)) {
        throw "adb binary capture failed: $errorText"
      }
      Write-Warning `
        "adb returned $($process.ExitCode) after writing $outputBytes bytes; validating archive."
    }
  }
  finally {
    Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
  }
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
    $localPropertiesPath = Join-Path $PSScriptRoot '..\..\android\local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf) {
      $sdkLine = Get-Content -LiteralPath $localPropertiesPath |
        Where-Object { $_ -match '^sdk\.dir=' } |
        Select-Object -First 1
      if ($sdkLine -match '^sdk\.dir=(.*)$') {
        $sdkRoot = $matches[1].Trim().Replace('\:', ':')
      }
    }
  }
  Assert-Condition `
    -Condition (-not [string]::IsNullOrWhiteSpace($sdkRoot)) `
    -Message "Android SDK root is not configured for $ToolName."
  $tools = @(
    Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') `
      -Filter "$ToolName*" -File -Recurse -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Name -eq $ToolName -or
        $_.Name -eq "$ToolName.exe" -or
        $_.Name -eq "$ToolName.bat" -or
        $_.Name -eq "$ToolName.cmd"
      } |
      Sort-Object FullName
  )
  Assert-Condition ($tools.Count -gt 0) "Android tool not found: $ToolName"
  return $tools[-1].FullName
}

function Resolve-PathChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  Assert-Condition `
    -Condition (Test-Path -LiteralPath $Path -PathType Leaf) `
    -Message "$Label is missing: $Path"
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-ApkMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath
  )

  $output = @(& $aapt dump badging $ApkPath 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "aapt dump badging failed for $ApkPath"
  }
  $packageLine = $output | Where-Object { $_ -match '^package:' } |
    Select-Object -First 1
  $match = [regex]::Match(
    $packageLine,
    "name='([^']+)' versionCode='([^']*)' versionName='([^']*)'"
  )
  Assert-Condition $match.Success "Could not parse APK metadata: $ApkPath"
  $versionCodeText = $match.Groups[2].Value
  $versionCode = if ([string]::IsNullOrEmpty($versionCodeText)) {
    $null
  }
  else {
    [int]$versionCodeText
  }
  return [pscustomobject]@{
    PackageName = $match.Groups[1].Value
    VersionCode = $versionCode
    VersionName = $match.Groups[3].Value
  }
}

function Get-CertificateDigest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath
  )

  $output = @(& $apksigner verify --print-certs $ApkPath 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "apksigner verification failed for $ApkPath"
  }
  $digestLine = $output | Where-Object {
    $_ -match 'certificate SHA-256 digest'
  } | Select-Object -First 1
  Assert-Condition `
    -Condition ($null -ne $digestLine) `
    -Message "APK certificate digest is missing: $ApkPath"
  $digest = ($digestLine -replace '.*:\s*', '').Trim()
  return $digest.Replace(':', '').ToLowerInvariant()
}

function Assert-ApkContract {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedPackage
  )

  $metadata = Get-ApkMetadata -ApkPath $ApkPath
  Assert-Condition `
    -Condition ($metadata.PackageName -eq $ExpectedPackage) `
    -Message "APK package mismatch: $($metadata.PackageName)"
  Assert-Condition `
    -Condition ($metadata.VersionName -eq $ExpectedVersionName) `
    -Message "APK versionName mismatch: $($metadata.VersionName)"
  Assert-Condition `
    -Condition ($metadata.VersionCode -eq $ExpectedVersionCode) `
    -Message "APK versionCode mismatch: $($metadata.VersionCode)"
  $digest = Get-CertificateDigest -ApkPath $ApkPath
  Assert-Condition `
    -Condition ($digest -eq $ExpectedCertSha256.ToLowerInvariant()) `
    -Message "APK certificate mismatch: $digest"
  return $metadata
}

function Get-DeviceInventory {
  $paths = @(
    Invoke-Adb @('shell', 'run-as', $packageName, 'find', '.', '-type', 'f', '-print')
  ) | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\./' }
  $inventory = foreach ($path in $paths) {
    $sizeText = Invoke-AdbText @(
      'shell',
      'run-as',
      $packageName,
      'stat',
      '-c',
      '%s',
      $path
    )
    $hashLine = Invoke-AdbText @(
      'shell',
      'run-as',
      $packageName,
      'sha256sum',
      $path
    )
    $hash = ($hashLine -split '\s+')[0].ToLowerInvariant()
    [ordered]@{
      path = $path.Substring(2)
      bytes = [int64]$sizeText
      sha256 = $hash
    }
  }
  return @($inventory | Sort-Object path)
}

function Save-Json {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Value,
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path `
    -Encoding utf8
}

function Get-ModelInventory {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Inventory
  )

  return @(
    $Inventory | Where-Object {
      $_.path -match '(?i)\.gguf$'
    } | Sort-Object path
  )
}

function Invoke-InstrumentationClass {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ClassName,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedTestCount,
    [int]$TimeoutSeconds = 300,
    [string[]]$ExtraArguments = @(),
    [switch]$RequireApplicationPid
  )

  foreach ($targetPackage in @($packageName, $testPackageName)) {
    Invoke-Adb @('shell', 'am', 'force-stop', $targetPackage) | Out-Null
  }
  $outputPath = Join-Path $env:TEMP "nss-huawei-$([guid]::NewGuid()).out"
  $errorPath = Join-Path $env:TEMP "nss-huawei-$([guid]::NewGuid()).err"
  $arguments = @(
    '-s',
    $Serial,
    'shell',
    'am',
    'instrument',
    '-w',
    '-r',
    '-e',
    'class',
    $ClassName
  ) + $ExtraArguments + @(
    "$testPackageName/androidx.test.runner.AndroidJUnitRunner"
  )
  $process = Start-Process `
    -FilePath $adb `
    -ArgumentList $arguments `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outputPath `
    -RedirectStandardError $errorPath
  try {
    $appPid = ''
    $pidDeadline = [DateTime]::UtcNow.AddSeconds(
      [Math]::Min(15, $TimeoutSeconds)
    )
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $pidDeadline) {
      try {
        $pidText = Invoke-AdbText @('shell', 'pidof', $packageName)
      }
      catch {
        $pidText = ''
      }
      if ($pidText -match '^\d+$') {
        $appPid = $pidText
        break
      }
      Start-Sleep -Milliseconds 250
    }
    try {
      Wait-Process -Id $process.Id -Timeout $TimeoutSeconds `
        -ErrorAction Stop
    }
    catch {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      throw "Instrumentation timed out: $ClassName"
    }
    $output = @(Get-Content -LiteralPath $outputPath `
      -ErrorAction SilentlyContinue)
    $errors = @(Get-Content -LiteralPath $errorPath `
      -ErrorAction SilentlyContinue)
    $errors | Write-Host
    if ($process.ExitCode -ne 0) {
      throw "Instrumentation failed: $ClassName"
    }
    $joinedOutput = $output -join "`n"
    Assert-Condition `
      -Condition ($joinedOutput -match "OK \($ExpectedTestCount tests?\)") `
      -Message "$ClassName did not report $ExpectedTestCount passing tests."
    if ($RequireApplicationPid) {
      Assert-Condition `
        -Condition ($appPid -match '^\d+$') `
        -Message "No application PID observed for $ClassName."
    }
    $output | Write-Host
    return [pscustomobject]@{
      ApplicationPid = $appPid
      Output = $output
    }
  }
  finally {
    Remove-Item -LiteralPath $outputPath, $errorPath -Force `
      -ErrorAction SilentlyContinue
  }
}

function Assert-LogcatClean {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationPid,
    [Parameter(Mandatory = $true)]
    [string[]]$ForbiddenValues
  )

  $logcat = Invoke-Adb @('logcat', '-d', '--pid', $ApplicationPid)
  foreach ($value in $ForbiddenValues) {
    Assert-Condition `
      -Condition (-not ($logcat | Select-String -SimpleMatch $value -Quiet)) `
      -Message "Sensitive value appeared in Huawei Logcat: $value"
  }
}

function Assert-DeviceIdentity {
  $state = (Invoke-AdbText @('get-state')).Trim()
  Assert-Condition ($state -eq 'device') `
    "Huawei serial is not ready; adb state is $state."

  $actualManufacturer = (Invoke-AdbText @(
    'shell',
    'getprop',
    'ro.product.manufacturer'
  )).ToUpperInvariant()
  $actualModel = Invoke-AdbText @('shell', 'getprop', 'ro.product.model')
  $actualApi = Invoke-AdbText @('shell', 'getprop', 'ro.build.version.sdk')
  $actualAbi = Invoke-AdbText @('shell', 'getprop', 'ro.product.cpu.abi')
  Assert-Condition `
    -Condition ($actualManufacturer -eq $ExpectedManufacturer.ToUpperInvariant()) `
    -Message "Manufacturer mismatch: $actualManufacturer"
  Assert-Condition `
    -Condition ($actualModel -eq $ExpectedModel) `
    -Message "Model mismatch: $actualModel"
  Assert-Condition ($actualApi -eq '29') "Huawei API mismatch: $actualApi"
  Assert-Condition ($actualAbi -eq 'arm64-v8a') `
    "Huawei ABI mismatch: $actualAbi"
  return [ordered]@{
    serial = $Serial
    manufacturer = $actualManufacturer
    model = $actualModel
    api = [int]$actualApi
    abi = $actualAbi
  }
}

function Backup-DeviceState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  Invoke-NativeChecked -FilePath 'icacls' -ArgumentList @(
    $Destination,
    '/inheritance:r',
    '/grant:r',
    ($currentUser + ':(OI)(CI)F')
  ) | Out-Null
  $identity = Assert-DeviceIdentity
  Save-Json -Value $identity -Path (Join-Path $Destination 'device.json')
  (Invoke-Adb @('shell', 'dumpsys', 'package', $packageName)) |
    Set-Content -LiteralPath (Join-Path $Destination 'package-before.txt') `
      -Encoding utf8
  (Invoke-Adb @('shell', 'getprop')) |
    Set-Content -LiteralPath (Join-Path $Destination 'getprop-before.txt') `
      -Encoding utf8

  $installedApkPath = Invoke-AdbText @('shell', 'pm', 'path', $packageName)
  Assert-Condition `
    -Condition ($installedApkPath -match '^package:(.+)$') `
    -Message 'The Huawei main package is not installed.'
  $remoteApkPath = $matches[1]
  $localApkPath = Join-Path $Destination 'installed-before.apk'
  Invoke-Adb @('pull', $remoteApkPath, $localApkPath) | Out-Null
  $beforeDigest = Get-CertificateDigest -ApkPath $localApkPath
  Assert-Condition `
    -Condition ($beforeDigest -eq $ExpectedCertSha256.ToLowerInvariant()) `
    -Message "Installed Huawei certificate mismatch: $beforeDigest"
  (Get-CertificateDigest -ApkPath $localApkPath) |
    Set-Content -LiteralPath (Join-Path $Destination 'installed-before-cert.txt')

  $inventory = Get-DeviceInventory
  Assert-Condition `
    -Condition ((Get-ModelInventory -Inventory $inventory).Count -gt 0) `
    -Message 'No existing GGUF user models were found before installation.'
  Save-Json -Value $inventory `
    -Path (Join-Path $Destination 'device-files-before.json')

  $tarPath = Join-Path $Destination 'app-private-before.tar'
  Invoke-AdbToFile `
    -Arguments @('exec-out', 'run-as', $packageName, 'tar', '-cf', '-', '.') `
    -OutputPath $tarPath
  Assert-Condition `
    -Condition ((Get-Item -LiteralPath $tarPath).Length -gt 0) `
    -Message 'App-private backup archive is empty.'
  $tarListingPath = Assert-TarArchive -Path $tarPath
  $manifest = [ordered]@{
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    packageName = $packageName
    device = $identity
    tarPath = $tarPath
    tarSha256 = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    tarListingPath = $tarListingPath
    files = $inventory
  }
  Save-Json -Value $manifest `
    -Path (Join-Path $Destination 'backup-manifest.json')
  return [pscustomobject]@{
    Path = $Destination
    Inventory = $inventory
  }
}
