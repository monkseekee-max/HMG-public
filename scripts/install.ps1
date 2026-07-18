$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ReleaseBaseUrl = if ($env:HMG_RELEASE_BASE_URL) { $env:HMG_RELEASE_BASE_URL } else { "" }
$PublicReleaseBaseUrl = if ($env:HMG_PUBLIC_RELEASE_BASE_URL) { $env:HMG_PUBLIC_RELEASE_BASE_URL } else { "" }
$OfficialReleaseBaseUrl = "https://github.com/HMG-AI/HMG-public/releases/latest/download"
$MirrorBaseUrl = "https://hmg1ai.com/releases/latest/download"
$MirrorBaseUrl2 = "https://hmg2ai.com/releases/latest/download"
$BinDir = if ($env:HMG_INSTALL_DIR) {
  $env:HMG_INSTALL_DIR
} elseif ($env:LOCALAPPDATA) {
  Join-Path $env:LOCALAPPDATA "Programs\HMG\bin"
} elseif ($env:USERPROFILE) {
  Join-Path $env:USERPROFILE ".local\bin"
} else {
  Join-Path $HOME ".local\bin"
}
$TempDir = Join-Path ([IO.Path]::GetTempPath()) ("hmg-install-" + [Guid]::NewGuid().ToString("N"))
$script:HmgInstallDeferred = $false
$script:ExpectedVersion = $null
$script:InstallTransaction = $null
$script:ProtectedKeyState = @()

function Log([string] $Message) {
  Write-Host $Message
}

function Invoke-Hmg-Command-With-Timeout([string] $FilePath, [string[]] $Arguments, [int] $TimeoutSeconds) {
  $StdoutPath = [IO.Path]::GetTempFileName()
  $StderrPath = [IO.Path]::GetTempFileName()
  $Output = @()
  try {
    $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)
    $ExitCode = $null
    if ($Completed) {
      # Complete redirected-output handling before reading administrative
      # process state. This is required by Process.WaitForExit and avoids a
      # transient null ExitCode on native Windows ARM runners.
      $Process.WaitForExit()
      $Process.Refresh()
      $ExitCode = [int] $Process.ExitCode
    }
    if (-not $Completed) {
      try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch {}
      try { $Process.WaitForExit(5000) | Out-Null } catch {}
    }
    if (Test-Path $StdoutPath) { $Output += Get-Content -Path $StdoutPath -ErrorAction SilentlyContinue }
    if (Test-Path $StderrPath) { $Output += Get-Content -Path $StderrPath -ErrorAction SilentlyContinue }
    return [PSCustomObject]@{
      TimedOut = (-not $Completed)
      ExitCode = $ExitCode
      Output = $Output
    }
  } finally {
    try { Remove-Item -Force $StdoutPath, $StderrPath -ErrorAction SilentlyContinue } catch {}
  }
}

function Need-Cmd([string] $Name) {
  return [bool] (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Normalize-PathEntry([string] $Entry) {
  if ([string]::IsNullOrWhiteSpace($Entry)) {
    return ""
  }

  $Expanded = [Environment]::ExpandEnvironmentVariables($Entry.Trim())
  try {
    return [IO.Path]::GetFullPath($Expanded).TrimEnd([char[]]@('\', '/'))
  } catch {
    return $Expanded.TrimEnd([char[]]@('\', '/'))
  }
}

function Path-Contains([string] $PathValue, [string] $Entry) {
  $NormalizedEntry = Normalize-PathEntry $Entry
  foreach ($PathPart in ($PathValue -split ";")) {
    if ((Normalize-PathEntry $PathPart).Equals($NormalizedEntry, [StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }
  return $false
}

function Add-Hmg-To-Path {
  $NormalizedBinDir = Normalize-PathEntry $BinDir
  $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

  if (-not (Path-Contains $UserPath $NormalizedBinDir)) {
    $NewUserPath = if ([string]::IsNullOrWhiteSpace($UserPath)) {
      $NormalizedBinDir
    } else {
      $UserPath.TrimEnd([char[]]@(';')) + ";" + $NormalizedBinDir
    }
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    Log "  Added to user PATH (persistent)."
  } else {
    Log "  Already in user PATH."
  }

  # Always ensure the current process PATH has the bin dir
  # This is critical — without it hmg setup in the same script will fail
  if (-not (Path-Contains $env:Path $NormalizedBinDir)) {
    $env:Path = if ([string]::IsNullOrWhiteSpace($env:Path)) {
      $NormalizedBinDir
    } else {
      $env:Path.TrimEnd([char[]]@(';')) + ";" + $NormalizedBinDir
    }
    Log "  Added to current process PATH."
  } else {
    Log "  Already in current process PATH."
  }
}

function Target-Triple {
  $Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  switch ($Arch.ToUpperInvariant()) {
    "AMD64" { return "x86_64-pc-windows-msvc" }
    "ARM64" { return "aarch64-pc-windows-msvc" }
    default { return "" }
  }
}

function Target-Triple-GNU {
  $Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  switch ($Arch.ToUpperInvariant()) {
    "AMD64" { return "x86_64-pc-windows-gnu" }
    "ARM64" { return "aarch64-pc-windows-gnu" }
    default { return "" }
  }
}

function Supported-Targets {
  Log "Supported Windows prebuilt packages:"
  Log "  hmg-x86_64-pc-windows-msvc.zip"
  Log "  hmg-x86_64-pc-windows-gnu.zip"
  Log "  hmg-aarch64-pc-windows-msvc.zip"
}

function Download-File([string] $Url, [string] $OutputPath) {
  $LastError = $null
  for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
    $Client = $null
    try {
      $Client = New-Object Net.WebClient
      $Client.DownloadFile($Url, $OutputPath)
      return
    } catch {
      $LastError = $_
      Start-Sleep -Seconds $Attempt
    } finally {
      if ($Client) {
        $Client.Dispose()
      }
    }
  }
  throw $LastError
}

function PowerShell-Command {
  if (Need-Cmd "pwsh") {
    return "pwsh"
  }
  return "powershell"
}

function Quote-ProcessArgument([string] $Value) {
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-Hmg-Store-Roots {
  $Roots = @()
  foreach ($Configured in @($env:HMG_DATA_DIR, $env:HMG_STORE)) {
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
      $Roots += Normalize-PathEntry $Configured
    }
  }
  if ($env:XDG_DATA_HOME) {
    $Roots += Normalize-PathEntry (Join-Path $env:XDG_DATA_HOME "hmg\stores\default")
  } elseif ($env:LOCALAPPDATA) {
    $Roots += Normalize-PathEntry (Join-Path $env:LOCALAPPDATA "HMG\stores\default")
  } elseif ($env:USERPROFILE) {
    $Roots += Normalize-PathEntry (Join-Path $env:USERPROFILE ".local\share\hmg\stores\default")
  }
  return @($Roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Test-Path-Is-Same-Or-Child([string] $Candidate, [string] $Parent) {
  $NormalizedCandidate = Normalize-PathEntry $Candidate
  $NormalizedParent = Normalize-PathEntry $Parent
  if ($NormalizedCandidate.Equals($NormalizedParent, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }
  return $NormalizedCandidate.StartsWith($NormalizedParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-Safe-Hmg-Install-Directory([string] $TargetDir) {
  foreach ($StoreRoot in (Get-Hmg-Store-Roots)) {
    if ((Test-Path-Is-Same-Or-Child $TargetDir $StoreRoot) -or (Test-Path-Is-Same-Or-Child $StoreRoot $TargetDir)) {
      throw "Refusing to install binaries into or above the protected HMG store: $StoreRoot"
    }
  }
}

function Get-Protected-Hmg-Key-State {
  $State = @()
  $ProtectedKeyNames = @("storage.key", "server.key.json", "approval.key", "observation.key")
  foreach ($StoreRoot in (Get-Hmg-Store-Roots)) {
    if (Test-Path -LiteralPath $StoreRoot -PathType Container) {
      foreach ($Path in [IO.Directory]::EnumerateFiles($StoreRoot, "*", [IO.SearchOption]::AllDirectories)) {
        if ($ProtectedKeyNames -notcontains [IO.Path]::GetFileName($Path)) {
          continue
        }
        $Item = Get-Item -LiteralPath $Path
        $State += [PSCustomObject]@{
          Path = $Item.FullName
          Length = $Item.Length
          Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Item.FullName).Hash
        }
      }
    }
  }
  return @($State)
}

function Assert-Protected-Hmg-Key-State([object[]] $Before) {
  foreach ($Entry in @($Before)) {
    if (-not (Test-Path -LiteralPath $Entry.Path -PathType Leaf)) {
      throw "Protected HMG key disappeared during install: $($Entry.Path)"
    }
    $Item = Get-Item -LiteralPath $Entry.Path
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Entry.Path).Hash
    if (($Item.Length -ne $Entry.Length) -or (-not $Hash.Equals($Entry.Sha256, [StringComparison]::OrdinalIgnoreCase))) {
      throw "Protected HMG key changed during install: $($Entry.Path)"
    }
  }
}

function Get-Hmg-Data-Home {
  if ($env:HMG_DATA_HOME) {
    return Normalize-PathEntry $env:HMG_DATA_HOME
  }
  if ($env:XDG_DATA_HOME) {
    return Normalize-PathEntry (Join-Path $env:XDG_DATA_HOME "hmg")
  }
  if ($env:LOCALAPPDATA) {
    return Normalize-PathEntry (Join-Path $env:LOCALAPPDATA "HMG")
  }
  if ($env:USERPROFILE) {
    return Normalize-PathEntry (Join-Path $env:USERPROFILE ".local\share\hmg")
  }
  throw "Cannot resolve the HMG data home for an upgrade backup."
}

function New-Hmg-Store-Upgrade-Backup([string] $StoreRoot, [object[]] $ProtectedKeyState) {
  if (-not (Test-Path -LiteralPath $StoreRoot -PathType Container)) {
    return $null
  }

  $DataHome = Get-Hmg-Data-Home
  $BackupRoot = Join-Path $DataHome "upgrade-backups"
  New-Item -ItemType Directory -Force $BackupRoot | Out-Null
  $StoreName = (Split-Path -Leaf (Normalize-PathEntry $StoreRoot)) -replace '[^A-Za-z0-9_.-]', '_'
  if ([string]::IsNullOrWhiteSpace($StoreName)) { $StoreName = "store" }
  $Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
  $Id = [Guid]::NewGuid().ToString("N")
  $FinalPath = Join-Path $BackupRoot ("hmg-upgrade-$StoreName-$Stamp-$Id.zip")
  $PartialPath = $FinalPath + ".partial"
  $ManifestEntryName = "hmg-upgrade-backup.json"
  $ExcludedNames = @("storage.key", "server.key.json", "approval.key", "observation.key")
  $ExpectedEntries = @{}
  $FileCount = 0
  $TotalBytes = [int64]0

  try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::Open($PartialPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach ($FilePath in [IO.Directory]::EnumerateFiles($StoreRoot, "*", [IO.SearchOption]::AllDirectories)) {
        if (Test-Path-Is-Same-Or-Child $FilePath $BackupRoot) {
          continue
        }
        $Item = Get-Item -LiteralPath $FilePath
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "Refusing to archive reparse-point store file: $FilePath"
        }
        if ($ExcludedNames -contains $Item.Name) {
          continue
        }
        $Relative = $Item.FullName.Substring((Normalize-PathEntry $StoreRoot).Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($Relative)) {
          continue
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $Item.FullName, $Relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $ExpectedEntries[$Relative] = [int64]$Item.Length
        $FileCount++
        $TotalBytes += [int64]$Item.Length
      }

      $KeyHashes = @()
      foreach ($Entry in @($ProtectedKeyState)) {
        if (Test-Path-Is-Same-Or-Child $Entry.Path $StoreRoot) {
          $KeyHashes += [PSCustomObject]@{
            name = Split-Path -Leaf $Entry.Path
            sha256 = $Entry.Sha256
            excluded_from_backup = $true
          }
        }
      }
      $Manifest = [PSCustomObject]@{
        schema_version = "hmg-windows-upgrade-backup/v1"
        created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        store_path = Normalize-PathEntry $StoreRoot
        file_count = $FileCount
        uncompressed_bytes = $TotalBytes
        excluded_sensitive_files = @($KeyHashes)
        data_and_keys_preserved_in_place = $true
      }
      $ManifestEntry = $Archive.CreateEntry($ManifestEntryName, [IO.Compression.CompressionLevel]::Optimal)
      $Utf8NoBom = New-Object Text.UTF8Encoding($false)
      $Writer = New-Object -TypeName IO.StreamWriter -ArgumentList @($ManifestEntry.Open(), $Utf8NoBom)
      try {
        $Writer.Write(($Manifest | ConvertTo-Json -Depth 5))
      } finally {
        $Writer.Dispose()
      }
    } finally {
      $Archive.Dispose()
    }

    # Open and fully read every entry. This validates the central directory,
    # decompression stream, sizes, and CRC rather than trusting archive creation.
    $ReadArchive = [IO.Compression.ZipFile]::OpenRead($PartialPath)
    try {
      $Seen = @{}
      foreach ($Entry in $ReadArchive.Entries) {
        $Leaf = [IO.Path]::GetFileName($Entry.FullName)
        if ($ExcludedNames -contains $Leaf) {
          throw "Upgrade backup unexpectedly contains sensitive key material: $($Entry.FullName)"
        }
        $Stream = $Entry.Open()
        try {
          $Buffer = New-Object byte[] 81920
          $ReadTotal = [int64]0
          while (($Read = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            $ReadTotal += $Read
          }
        } finally {
          $Stream.Dispose()
        }
        if ($Entry.FullName -ne $ManifestEntryName) {
          if (-not $ExpectedEntries.ContainsKey($Entry.FullName)) {
            throw "Upgrade backup contains an unexpected entry: $($Entry.FullName)"
          }
          if ($ReadTotal -ne $ExpectedEntries[$Entry.FullName]) {
            throw "Upgrade backup entry size mismatch: $($Entry.FullName)"
          }
          $Seen[$Entry.FullName] = $true
        }
      }
      if (($Seen.Count -ne $ExpectedEntries.Count) -or ($null -eq $ReadArchive.GetEntry($ManifestEntryName))) {
        throw "Upgrade backup validation found missing store entries or manifest."
      }
    } finally {
      $ReadArchive.Dispose()
    }

    Move-Item -LiteralPath $PartialPath -Destination $FinalPath -Force
    $BackupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FinalPath).Hash
    Log "  Store upgrade backup verified: $FinalPath"
    Log "  Backup SHA256: $BackupHash (keys excluded; existing key hashes preserved separately)."
    return $FinalPath
  } catch {
    Remove-Item -LiteralPath $PartialPath -Force -ErrorAction SilentlyContinue
    throw
  }
}

function Backup-Existing-Hmg-Stores([object[]] $ProtectedKeyState) {
  $Backups = @()
  foreach ($StoreRoot in (Get-Hmg-Store-Roots)) {
    if (Test-Path -LiteralPath $StoreRoot -PathType Container) {
      $Backup = New-Hmg-Store-Upgrade-Backup $StoreRoot $ProtectedKeyState
      if ($Backup) { $Backups += $Backup }
    }
  }
  return @($Backups)
}

function Get-Version-From-Hmg-Output([object[]] $Output) {
  $Text = (@($Output) -join "`n")
  if ($Text -match '(?im)^hmg\s+v?([0-9]+(?:\.[0-9]+){1,3})') {
    return $Matches[1]
  }
  return $null
}

function Assert-Hmg-Version([string] $FilePath, [string[]] $Arguments, [string] $ExpectedVersion, [string] $Label) {
  $Result = Invoke-Hmg-Command-With-Timeout $FilePath $Arguments 20
  $Result.Output | ForEach-Object { Log "  ${Label}: $_" }
  if ($Result.TimedOut) {
    throw "$Label version probe timed out."
  }
  if ($Result.ExitCode -ne 0) {
    throw "$Label version probe exited with code $($Result.ExitCode)."
  }
  $OutputText = (@($Result.Output) -join "`n")
  $ActualVersion = Get-Version-From-Hmg-Output $Result.Output
  if ([string]::IsNullOrWhiteSpace($ActualVersion)) {
    throw "$Label did not report a parseable HMG version."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $Expected = $ExpectedVersion.TrimStart([char[]]@('v', 'V'))
    $ExpectedPattern = [Regex]::Escape($Expected)
    if ($OutputText -notmatch "(?im)^hmg\s+v?$ExpectedPattern(?:-|\s|$)") {
      throw "$Label version mismatch: expected $Expected, got $ActualVersion."
    }
    $ActualVersion = $Expected
  }
  return $ActualVersion
}

function Test-Pe-Binary([string] $Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  $Item = Get-Item -LiteralPath $Path
  if ($Item.Length -lt 4096) {
    return $false
  }
  $Stream = [IO.File]::OpenRead($Path)
  try {
    return (($Stream.ReadByte() -eq 0x4D) -and ($Stream.ReadByte() -eq 0x5A))
  } finally {
    $Stream.Dispose()
  }
}

function Validate-Hmg-Bundle([string] $SourceDir, [string[]] $Bins, [string] $ExpectedVersion) {
  $Manifest = @()
  foreach ($Bin in $Bins) {
    $Path = Join-Path $SourceDir $Bin
    if (-not (Test-Pe-Binary $Path)) {
      throw "Staged HMG binary is missing, truncated, or not a PE executable: $Bin"
    }
    $Item = Get-Item -LiteralPath $Path
    $Manifest += [PSCustomObject]@{
      Name = $Bin
      Length = $Item.Length
      Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    }
  }
  $DistinctHashes = @($Manifest | Select-Object -ExpandProperty Sha256 -Unique)
  if ($DistinctHashes.Count -ne $Bins.Count) {
    throw "Staged HMG bundle contains duplicate binary payloads."
  }

  $CliVersion = Assert-Hmg-Version (Join-Path $SourceDir "hmg.exe") @("version") $ExpectedVersion "staged hmg.exe"
  $ServerVersion = Assert-Hmg-Version (Join-Path $SourceDir "hmg-server.exe") @("--version") $ExpectedVersion "staged hmg-server.exe"
  if (-not $CliVersion.Equals($ServerVersion, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Staged HMG bundle is mixed-version: CLI $CliVersion, server $ServerVersion."
  }
  if ([string]::IsNullOrWhiteSpace($script:ExpectedVersion)) {
    $script:ExpectedVersion = $CliVersion
  }
  Log "  Staged bundle verified: three PE binaries, distinct SHA256 digests, version $CliVersion."
  return @($Manifest)
}

function Stop-Hmg-Daemon-Before-Install([string] $TargetDir) {
  $ExistingHmg = Join-Path $TargetDir "hmg.exe"
  if (-not (Test-Path $ExistingHmg)) {
    return
  }

  Log "  Stopping existing HMG daemon (if running)..."
  # 1. Graceful stop via the daemon named pipe.
  try {
    $StopOutput = & $ExistingHmg daemon stop 2>&1
    $StopExit = $LASTEXITCODE
    if ($StopExit -eq 0) {
      Log "  Existing HMG daemon stopped."
    } else {
      Log "  No running HMG daemon stopped gracefully (exit $StopExit; non-fatal)."
      $StopOutput | ForEach-Object { Log "  $_" }
    }
  } catch {
    Log "  Could not stop existing HMG daemon before install (non-fatal): $($_.Exception.Message)"
  }

  # 2. Forceful recovery for stale/zombie hmg-server.exe that still holds the
  #    store lock but no longer responds on its named pipe. This is the common
  #    Windows failure when a previous install/update was interrupted: the
  #    daemon holds store.lock while `hmg daemon status` reports "not running",
  #    and Windows refuses to overwrite the locked binaries. `daemon stop --force`
  #    terminates the holder PID and waits for the OS to release store.lock.
  try {
    $ForceOutput = & $ExistingHmg daemon stop --force 2>&1
    $ForceExit = $LASTEXITCODE
    if ($ForceExit -eq 0) {
      Log "  Force-stop sweep completed."
    } else {
      Log "  Force-stop sweep exited $ForceExit (non-fatal)."
      $ForceOutput | ForEach-Object { Log "  $_" }
    }
  } catch {
    Log "  Force-stop sweep failed (non-fatal): $($_.Exception.Message)"
  }

  # 3. Last-resort: terminate only processes whose executable is one of the
  #    binaries in this exact install directory. Never kill every process named
  #    hmg/hmg-server on the machine: another user, store, or test installation
  #    may legitimately be running at the same time.
  $OwnedPaths = @(
    (Normalize-PathEntry (Join-Path $TargetDir "hmg-server.exe")),
    (Normalize-PathEntry (Join-Path $TargetDir "hmg-hook-worker.exe"))
  )
  try {
    $Candidates = Get-CimInstance Win32_Process -Filter "Name='hmg-server.exe' OR Name='hmg-hook-worker.exe'" -ErrorAction Stop
    foreach ($Candidate in @($Candidates)) {
      if ([string]::IsNullOrWhiteSpace($Candidate.ExecutablePath)) {
        continue
      }
      $ExecutablePath = Normalize-PathEntry $Candidate.ExecutablePath
      if ($OwnedPaths -contains $ExecutablePath) {
        Log "  Terminating HMG-owned process PID $($Candidate.ProcessId) at $ExecutablePath..."
        Stop-Process -Id $Candidate.ProcessId -Force -ErrorAction Stop
      }
    }
  } catch {
    Log "  Could not complete exact-path HMG process cleanup (non-fatal): $($_.Exception.Message)"
  }

  # 4. Give the OS a moment to release the file handles / store lock before copy.
  Start-Sleep -Milliseconds 500
}

function Assert-Hmg-Daemon-Quiesced([string] $TargetDir) {
  $ExistingServer = Join-Path $TargetDir "hmg-server.exe"
  if (Test-Path -LiteralPath $ExistingServer -PathType Leaf) {
    # Probe the server binary directly for every configured store. Older hmg
    # CLI versions can print an inner `hmg-server --daemon-status` failure while
    # still returning process exit 0, which falsely classifies a stopped daemon
    # as ready and blocks an otherwise safe N-1 upgrade before backup.
    foreach ($StoreRoot in (Get-Hmg-Store-Roots)) {
      $Status = Invoke-Hmg-Command-With-Timeout $ExistingServer @("--daemon-status", $StoreRoot) 15
      $Status.Output | ForEach-Object { Log "  pre-backup-daemon-status [$StoreRoot]: $_" }
      if ($Status.TimedOut) {
        throw "Cannot prove the existing HMG daemon stopped for ${StoreRoot}: status probe timed out."
      }
      if ($null -eq $Status.ExitCode) {
        throw "Cannot classify the existing HMG daemon status for ${StoreRoot}: the probe returned no exit code."
      }
      $StatusText = (@($Status.Output) -join "`n")
      # Public v1.7.7 can explicitly report "not running" while still exiting
      # zero. Treat that exact semantic result as quiesced, then independently
      # require the owned server/worker processes to be absent below. Any other
      # zero exit is a live daemon; any non-zero result without the explicit
      # stopped message is unclassifiable and must fail closed.
      $ReportedNotRunning = $StatusText -match '(?im)^HMG local daemon is not running for .+$'
      if ($ReportedNotRunning) {
        continue
      }
      if ($Status.ExitCode -eq 0) {
        throw "Cannot create a consistent upgrade backup while the existing HMG daemon is still ready for ${StoreRoot}."
      }
      throw "Cannot prove the existing HMG daemon stopped for ${StoreRoot}: status probe exited $($Status.ExitCode) without an explicit not-running result."
    }
  }

  # The CLI process that invoked this installer may still be running, so only
  # require the exact installed server/worker executables to be absent. This is
  # a scoped ownership check, not a machine-wide process-name sweep.
  $OwnedPaths = @(
    (Normalize-PathEntry (Join-Path $TargetDir "hmg-server.exe")),
    (Normalize-PathEntry (Join-Path $TargetDir "hmg-hook-worker.exe"))
  )
  $Candidates = Get-CimInstance Win32_Process -Filter "Name='hmg-server.exe' OR Name='hmg-hook-worker.exe'" -ErrorAction Stop
  foreach ($Candidate in @($Candidates)) {
    if (-not [string]::IsNullOrWhiteSpace($Candidate.ExecutablePath)) {
      $ExecutablePath = Normalize-PathEntry $Candidate.ExecutablePath
      if ($OwnedPaths -contains $ExecutablePath) {
        throw "Cannot create a consistent upgrade backup while PID $($Candidate.ProcessId) still runs $ExecutablePath."
      }
    }
  }
  Log "  Existing HMG daemon is quiesced; store backup can begin."
}

function New-Hmg-Binary-Backup([string] $TargetDir, [string[]] $Bins, [string] $BackupDir) {
  New-Item -ItemType Directory -Force $BackupDir | Out-Null
  $Existing = @{}
  foreach ($Bin in $Bins) {
    $Target = Join-Path $TargetDir $Bin
    $Present = Test-Path -LiteralPath $Target -PathType Leaf
    $Existing[$Bin] = $Present
    if ($Present) {
      Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir $Bin) -Force
    }
  }
  return [PSCustomObject]@{
    TargetDir = $TargetDir
    BackupDir = $BackupDir
    Bins = @($Bins)
    Existing = $Existing
  }
}

function Restore-Hmg-Binaries([object] $Transaction) {
  foreach ($Bin in @($Transaction.Bins)) {
    $Target = Join-Path $Transaction.TargetDir $Bin
    if ($Transaction.Existing[$Bin]) {
      $RestoreTemp = Join-Path $Transaction.TargetDir ("." + $Bin + ".rollback-" + [Guid]::NewGuid().ToString("N"))
      Copy-Item -LiteralPath (Join-Path $Transaction.BackupDir $Bin) -Destination $RestoreTemp -Force
      Move-Item -LiteralPath $RestoreTemp -Destination $Target -Force
    } elseif (Test-Path -LiteralPath $Target) {
      Remove-Item -LiteralPath $Target -Force
    }
  }
}

function Try-Copy-Hmg-Binaries([string] $SourceDir, [string] $TargetDir, [string[]] $Bins) {
  $StagedTemps = @()
  try {
    foreach ($Bin in $Bins) {
      $Source = Join-Path $SourceDir $Bin
      $Target = Join-Path $TargetDir $Bin
      $TempTarget = Join-Path $TargetDir ("." + $Bin + ".new-" + [Guid]::NewGuid().ToString("N"))
      Copy-Item -LiteralPath $Source -Destination $TempTarget -Force
      $StagedTemps += $TempTarget
      $SourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
      $TargetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $TempTarget).Hash
      if (-not $SourceHash.Equals($TargetHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "staged copy checksum mismatch for $Bin"
      }
      Move-Item -LiteralPath $TempTarget -Destination $Target -Force
      $StagedTemps = @($StagedTemps | Where-Object { $_ -ne $TempTarget })
    }
    return $true
  } catch {
    $script:LastBinaryCopyError = $_.Exception.Message
    return $false
  } finally {
    foreach ($Temp in $StagedTemps) {
      try { Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
}

function Stop-Installed-Hmg-Best-Effort([string] $TargetDir) {
  $HmgExe = Join-Path $TargetDir "hmg.exe"
  if (Test-Path -LiteralPath $HmgExe -PathType Leaf) {
    try {
      $Result = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "stop", "--force") 30
      $Result.Output | ForEach-Object { Log "  rollback-stop: $_" }
    } catch {}
  }
}

function Start-Installed-Hmg-Best-Effort([string] $TargetDir, [string] $Context) {
  $HmgExe = Join-Path $TargetDir "hmg.exe"
  if (-not (Test-Path -LiteralPath $HmgExe -PathType Leaf)) {
    return
  }
  try {
    $Start = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "start") 45
    $Start.Output | ForEach-Object { Log "  ${Context}-daemon-start: $_" }
    if ($Start.TimedOut -or $Start.ExitCode -ne 0) {
      Log "  Existing HMG daemon could not be restarted after $Context."
    } else {
      Log "  Existing HMG daemon restarted after $Context."
    }
  } catch {
    Log "  Existing HMG daemon restart failed after ${Context}: $($_.Exception.Message)"
  }
}

function Rollback-Hmg-Install([object] $Transaction, [object[]] $ProtectedKeyState) {
  Log "  Rolling back the HMG binary bundle..."
  Stop-Installed-Hmg-Best-Effort $Transaction.TargetDir
  Restore-Hmg-Binaries $Transaction
  Assert-Protected-Hmg-Key-State $ProtectedKeyState

  Start-Installed-Hmg-Best-Effort $Transaction.TargetDir "rollback"
}

function Initialize-And-Verify-Hmg([string] $TargetDir, [string] $ExpectedVersion, [object[]] $ProtectedKeyState) {
  # Test-only transaction seam used by the exact-package native lifecycle gate.
  # Throwing here proves the catch path restores the previous three-file bundle
  # after a successful binary switch. Normal installation never sets it.
  if ($env:HMG_INSTALL_TEST_FAIL_AFTER_BINARY_SWITCH -eq "1") {
    throw "Injected post-switch installer failure for rollback verification."
  }
  $HmgExe = Join-Path $TargetDir "hmg.exe"
  $ServerExe = Join-Path $TargetDir "hmg-server.exe"
  $CliVersion = Assert-Hmg-Version $HmgExe @("version") $ExpectedVersion "installed hmg.exe"
  $ServerVersion = Assert-Hmg-Version $ServerExe @("--version") $ExpectedVersion "installed hmg-server.exe"
  if (-not $CliVersion.Equals($ServerVersion, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Installed HMG bundle is mixed-version: CLI $CliVersion, server $ServerVersion."
  }

  $SetupArgs = @("setup", "--no-daemon")
  if ($env:HMG_INSTALL_SKIP_MODEL -eq "1") {
    $SetupArgs += "--no-model"
  }
  if ($env:HMG_INSTALL_SKIP_AGENT_ADAPTERS -eq "1") {
    $SetupArgs += "--no-agent-adapters"
  }
  $Setup = Invoke-Hmg-Command-With-Timeout $HmgExe $SetupArgs 90
  $Setup.Output | ForEach-Object { Log "  setup: $_" }
  if ($Setup.TimedOut) {
    throw "hmg setup --no-daemon timed out after 90 seconds."
  }
  if ($Setup.ExitCode -ne 0) {
    throw "hmg setup --no-daemon exited with code $($Setup.ExitCode)."
  }
  Log "  hmg setup --no-daemon completed successfully."

  $DaemonStart = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "start") 45
  $DaemonStart.Output | ForEach-Object { Log "  daemon-start: $_" }
  if ($DaemonStart.TimedOut) {
    throw "hmg daemon start timed out after 45 seconds."
  }
  if ($DaemonStart.ExitCode -ne 0) {
    throw "hmg daemon start exited with code $($DaemonStart.ExitCode)."
  }

  $DaemonStatus = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "status") 30
  $DaemonStatus.Output | ForEach-Object { Log "  daemon-status: $_" }
  if ($DaemonStatus.TimedOut) {
    throw "hmg daemon status timed out after target startup."
  }
  if ($DaemonStatus.ExitCode -ne 0) {
    throw "target HMG daemon did not become ready (status $($DaemonStatus.ExitCode))."
  }

  # Re-probe both installed executables after daemon readiness. Because daemon
  # start resolves hmg-server.exe next to this exact hmg.exe, this proves the
  # active takeover is backed by the verified target bundle rather than PATH.
  Assert-Hmg-Version $HmgExe @("version") $CliVersion "active hmg.exe" | Out-Null
  Assert-Hmg-Version $ServerExe @("--version") $ServerVersion "active hmg-server.exe" | Out-Null
  Assert-Protected-Hmg-Key-State $ProtectedKeyState
  Log "  HMG $CliVersion is installed, initialized, and serving from the target bundle."
}

function Schedule-Deferred-Binary-Install([string] $SourceDir, [string] $TargetDir, [string[]] $Bins, [string] $ExpectedVersion, [object[]] $Manifest) {
  $DeferredRoot = Join-Path ([IO.Path]::GetTempPath()) ("hmg-deferred-install-" + [Guid]::NewGuid().ToString("N"))
  $DeferredPackageDir = Join-Path $DeferredRoot "package"
  $HelperPath = Join-Path $DeferredRoot "finish-hmg-update.ps1"
  $LogPath = Join-Path $DeferredRoot "finish-hmg-update.log"
  $ManifestPath = Join-Path $DeferredRoot "bundle-manifest.json"

  New-Item -ItemType Directory -Force $DeferredPackageDir | Out-Null
  foreach ($Bin in $Bins) {
    Copy-Item -Force (Join-Path $SourceDir $Bin) (Join-Path $DeferredPackageDir $Bin)
  }
  @($Manifest) | ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestPath -Encoding UTF8

  $HelperScript = @'
param(
  [Parameter(Mandatory = $true)][string] $PackageDir,
  [Parameter(Mandatory = $true)][string] $BinDir,
  [Parameter(Mandatory = $true)][string] $BinsCsv,
  [Parameter(Mandatory = $true)][string] $LogPath,
  [Parameter(Mandatory = $true)][string] $ManifestPath,
  [string] $ExpectedVersion
)

$ErrorActionPreference = "Stop"
$RequiredBins = $BinsCsv -split "\|"
$Deadline = (Get-Date).AddMinutes(3)
$LastErrorMessage = ""

function Append-Log([string] $Message) {
  $Timestamp = (Get-Date).ToString("s")
  Add-Content -Path $LogPath -Value "[$Timestamp] $Message"
}

function Invoke-Hmg-Command-With-Timeout([string] $FilePath, [string[]] $Arguments, [int] $TimeoutSeconds) {
  $StdoutPath = [IO.Path]::GetTempFileName()
  $StderrPath = [IO.Path]::GetTempFileName()
  $Output = @()
  try {
    $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)
    $ExitCode = $null
    if ($Completed) {
      $Process.WaitForExit()
      $Process.Refresh()
      $ExitCode = [int] $Process.ExitCode
    }
    if (-not $Completed) {
      try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch {}
      try { $Process.WaitForExit(5000) | Out-Null } catch {}
    }
    if (Test-Path $StdoutPath) { $Output += Get-Content -Path $StdoutPath -ErrorAction SilentlyContinue }
    if (Test-Path $StderrPath) { $Output += Get-Content -Path $StderrPath -ErrorAction SilentlyContinue }
    return [PSCustomObject]@{
      TimedOut = (-not $Completed)
      ExitCode = $ExitCode
      Output = $Output
    }
  } finally {
    try { Remove-Item -Force $StdoutPath, $StderrPath -ErrorAction SilentlyContinue } catch {}
  }
}

function Get-Version([object[]] $Output) {
  $Text = (@($Output) -join "`n")
  if ($Text -match '(?im)^hmg\s+v?([0-9]+(?:\.[0-9]+){1,3})') {
    return $Matches[1]
  }
  return $null
}

function Assert-Version([string] $FilePath, [string[]] $Arguments, [string] $Expected, [string] $Label) {
  $Result = Invoke-Hmg-Command-With-Timeout $FilePath $Arguments 20
  $Result.Output | ForEach-Object { Append-Log "${Label}: $_" }
  if ($Result.TimedOut) { throw "$Label version probe timed out" }
  if ($Result.ExitCode -ne 0) { throw "$Label version probe exited $($Result.ExitCode)" }
  $OutputText = (@($Result.Output) -join "`n")
  $Actual = Get-Version $Result.Output
  if ([string]::IsNullOrWhiteSpace($Actual)) { throw "$Label returned no parseable version" }
  if (-not [string]::IsNullOrWhiteSpace($Expected)) {
    $NormalizedExpected = $Expected.TrimStart([char[]]@('v', 'V'))
    $ExpectedPattern = [Regex]::Escape($NormalizedExpected)
    if ($OutputText -notmatch "(?im)^hmg\s+v?$ExpectedPattern(?:-|\s|$)") {
      throw "$Label version mismatch: expected $NormalizedExpected, got $Actual"
    }
    $Actual = $NormalizedExpected
  }
  return $Actual
}

function Get-Store-Roots {
  $Roots = @()
  foreach ($Configured in @($env:HMG_DATA_DIR, $env:HMG_STORE)) {
    if (-not [string]::IsNullOrWhiteSpace($Configured)) { $Roots += [IO.Path]::GetFullPath($Configured) }
  }
  if ($env:XDG_DATA_HOME) {
    $Roots += Join-Path $env:XDG_DATA_HOME "hmg\stores\default"
  } elseif ($env:LOCALAPPDATA) {
    $Roots += Join-Path $env:LOCALAPPDATA "HMG\stores\default"
  } elseif ($env:USERPROFILE) {
    $Roots += Join-Path $env:USERPROFILE ".local\share\hmg\stores\default"
  }
  return @($Roots | Select-Object -Unique)
}

function Get-Key-State {
  $State = @()
  $ProtectedKeyNames = @("storage.key", "server.key.json", "approval.key", "observation.key")
  foreach ($Root in (Get-Store-Roots)) {
    if (Test-Path -LiteralPath $Root -PathType Container) {
      foreach ($Path in [IO.Directory]::EnumerateFiles($Root, "*", [IO.SearchOption]::AllDirectories)) {
        if ($ProtectedKeyNames -notcontains [IO.Path]::GetFileName($Path)) {
          continue
        }
        $Item = Get-Item -LiteralPath $Path
        $State += [PSCustomObject]@{ Path = $Item.FullName; Length = $Item.Length; Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
      }
    }
  }
  return @($State)
}

function Assert-Key-State([object[]] $Before) {
  foreach ($Entry in @($Before)) {
    if (-not (Test-Path -LiteralPath $Entry.Path -PathType Leaf)) { throw "protected HMG key disappeared: $($Entry.Path)" }
    $Item = Get-Item -LiteralPath $Entry.Path
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Entry.Path).Hash
    if (($Item.Length -ne $Entry.Length) -or (-not $Hash.Equals($Entry.Sha256, [StringComparison]::OrdinalIgnoreCase))) {
      throw "protected HMG key changed: $($Entry.Path)"
    }
  }
}

function Validate-Package {
  $Manifest = @(Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json)
  foreach ($Entry in $Manifest) {
    $Path = Join-Path $PackageDir $Entry.Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "deferred package missing $($Entry.Name)" }
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if (($Item.Length -ne $Entry.Length) -or (-not $Hash.Equals($Entry.Sha256, [StringComparison]::OrdinalIgnoreCase))) {
      throw "deferred package checksum mismatch for $($Entry.Name)"
    }
  }
  $CliVersion = Assert-Version (Join-Path $PackageDir "hmg.exe") @("version") $ExpectedVersion "staged hmg.exe"
  $ServerVersion = Assert-Version (Join-Path $PackageDir "hmg-server.exe") @("--version") $ExpectedVersion "staged hmg-server.exe"
  if (-not $CliVersion.Equals($ServerVersion, [StringComparison]::OrdinalIgnoreCase)) { throw "deferred package is mixed-version" }
  return $CliVersion
}

function Backup-Bins([string] $BackupDir) {
  New-Item -ItemType Directory -Force $BackupDir | Out-Null
  $Existing = @{}
  foreach ($Bin in $RequiredBins) {
    $Target = Join-Path $BinDir $Bin
    $Existing[$Bin] = Test-Path -LiteralPath $Target -PathType Leaf
    if ($Existing[$Bin]) { Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir $Bin) -Force }
  }
  return $Existing
}

function Restore-Bins([string] $BackupDir, [hashtable] $Existing) {
  foreach ($Bin in $RequiredBins) {
    $Target = Join-Path $BinDir $Bin
    if ($Existing[$Bin]) {
      $Temp = Join-Path $BinDir ("." + $Bin + ".rollback-" + [Guid]::NewGuid().ToString("N"))
      Copy-Item -LiteralPath (Join-Path $BackupDir $Bin) -Destination $Temp -Force
      Move-Item -LiteralPath $Temp -Destination $Target -Force
    } elseif (Test-Path -LiteralPath $Target) {
      Remove-Item -LiteralPath $Target -Force
    }
  }
}

function Try-Copy-Bins {
  $Temps = @()
  try {
    foreach ($Bin in $RequiredBins) {
      $Source = Join-Path $PackageDir $Bin
      $Target = Join-Path $BinDir $Bin
      $Temp = Join-Path $BinDir ("." + $Bin + ".new-" + [Guid]::NewGuid().ToString("N"))
      Copy-Item -LiteralPath $Source -Destination $Temp -Force
      $Temps += $Temp
      $SourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
      $TempHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Temp).Hash
      if (-not $SourceHash.Equals($TempHash, [StringComparison]::OrdinalIgnoreCase)) { throw "copy checksum mismatch for $Bin" }
      Move-Item -LiteralPath $Temp -Destination $Target -Force
      $Temps = @($Temps | Where-Object { $_ -ne $Temp })
    }
    return $true
  } catch {
    $script:LastErrorMessage = $_.Exception.Message
    return $false
  } finally {
    foreach ($Temp in $Temps) { try { Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue } catch {} }
  }
}

function Start-Previous-Daemon-Best-Effort {
  $HmgExe = Join-Path $BinDir "hmg.exe"
  if (Test-Path -LiteralPath $HmgExe -PathType Leaf) {
    try {
      $Start = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "start") 45
      $Start.Output | ForEach-Object { Append-Log "rollback-daemon-start: $_" }
    } catch { Append-Log "rollback daemon restart failed: $($_.Exception.Message)" }
  }
}

function Stop-New-Daemon-Best-Effort {
  $HmgExe = Join-Path $BinDir "hmg.exe"
  if (Test-Path -LiteralPath $HmgExe -PathType Leaf) {
    try { Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "stop", "--force") 30 | Out-Null } catch {}
  }
}

$BackupDir = Join-Path (Split-Path $PackageDir -Parent) "rollback"
$Existing = $null
$KeysBefore = Get-Key-State
try {
  $InstalledVersion = Validate-Package
  $Existing = Backup-Bins $BackupDir
  Append-Log "Waiting for the invoking HMG executable to exit before finishing update."
  while ((Get-Date) -lt $Deadline) {
    # The invoking CLI can keep hmg.exe locked briefly, and an external client
    # can reconnect during that handoff. Re-quiesce the exact installed daemon
    # before each final switch attempt; never use a machine-wide name kill.
    $OldHmg = Join-Path $BinDir "hmg.exe"
    if (Test-Path -LiteralPath $OldHmg -PathType Leaf) {
      try {
        $Stop = Invoke-Hmg-Command-With-Timeout $OldHmg @("daemon", "stop", "--force") 30
        $Stop.Output | ForEach-Object { Append-Log "pre-switch-stop: $_" }
      } catch {
        Append-Log "pre-switch exact-binary stop attempt failed: $($_.Exception.Message)"
      }
    }
    if (Try-Copy-Bins) {
      $HmgExe = Join-Path $BinDir "hmg.exe"
      $ServerExe = Join-Path $BinDir "hmg-server.exe"
      $CliVersion = Assert-Version $HmgExe @("version") $InstalledVersion "installed hmg.exe"
      $ServerVersion = Assert-Version $ServerExe @("--version") $InstalledVersion "installed hmg-server.exe"
      if (-not $CliVersion.Equals($ServerVersion, [StringComparison]::OrdinalIgnoreCase)) { throw "installed bundle is mixed-version" }

      Append-Log "Running hmg setup --no-daemon after deferred update."
      $Setup = Invoke-Hmg-Command-With-Timeout $HmgExe @("setup", "--no-daemon") 90
      $Setup.Output | ForEach-Object { Append-Log "setup: $_" }
      if ($Setup.TimedOut) { throw "hmg setup --no-daemon timed out after deferred update" }
      if ($Setup.ExitCode -ne 0) { throw "hmg setup --no-daemon exited $($Setup.ExitCode) after deferred update" }
      Append-Log "hmg setup --no-daemon completed successfully after deferred update."

      $Start = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "start") 45
      $Start.Output | ForEach-Object { Append-Log "daemon-start: $_" }
      if ($Start.TimedOut) { throw "hmg daemon start timed out after deferred update" }
      if ($Start.ExitCode -ne 0) { throw "hmg daemon start exited $($Start.ExitCode) after deferred update" }

      $Status = Invoke-Hmg-Command-With-Timeout $HmgExe @("daemon", "status") 30
      $Status.Output | ForEach-Object { Append-Log "daemon-status: $_" }
      if ($Status.TimedOut) { throw "hmg daemon status timed out after deferred update" }
      if ($Status.ExitCode -ne 0) { throw "target daemon is not ready after deferred update" }
      Assert-Version $HmgExe @("version") $InstalledVersion "active hmg.exe" | Out-Null
      Assert-Version $ServerExe @("--version") $InstalledVersion "active hmg-server.exe" | Out-Null
      Assert-Key-State $KeysBefore

      Append-Log "HMG deferred update completed successfully: version $InstalledVersion is active and ready."
      try { Remove-Item -Recurse -Force $BackupDir, $PackageDir } catch {}
      exit 0
    }
    Start-Sleep -Milliseconds 500
  }
  throw "timed out while replacing HMG binaries: $LastErrorMessage"
} catch {
  Append-Log "Deferred update failed: $($_.Exception.Message)"
  if ($null -ne $Existing) {
    try {
      Stop-New-Daemon-Best-Effort
      Restore-Bins $BackupDir $Existing
      Assert-Key-State $KeysBefore
      Start-Previous-Daemon-Best-Effort
      Append-Log "Previous HMG binary bundle restored after deferred update failure."
    } catch {
      Append-Log "CRITICAL: deferred update rollback failed: $($_.Exception.Message)"
    }
  }
  exit 1
}
'@

  Set-Content -Path $HelperPath -Value $HelperScript -Encoding UTF8

  $PowerShell = PowerShell-Command
  Start-Process -FilePath $PowerShell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Quote-ProcessArgument $HelperPath),
    "-PackageDir",
    (Quote-ProcessArgument $DeferredPackageDir),
    "-BinDir",
    (Quote-ProcessArgument $TargetDir),
    "-BinsCsv",
    (Quote-ProcessArgument ($Bins -join "|")),
    "-LogPath",
    (Quote-ProcessArgument $LogPath),
    "-ManifestPath",
    (Quote-ProcessArgument $ManifestPath),
    "-ExpectedVersion",
    (Quote-ProcessArgument $ExpectedVersion)
  ) | Out-Null

  $script:HmgInstallDeferred = $true
  Log "  Binaries are in use — verified update finalization continues automatically in the background."
  Log "  The update is staged, not yet complete; the helper will roll back on setup/start/readiness failure."
  Log "  Deferred update log: $LogPath"
  return $true
}

function Install-Hmg-Binaries([string] $SourceDir, [string] $TargetDir, [string[]] $Bins, [string] $ExpectedVersion) {
  Assert-Safe-Hmg-Install-Directory $TargetDir
  New-Item -ItemType Directory -Force $TargetDir | Out-Null
  $Manifest = Validate-Hmg-Bundle $SourceDir $Bins $ExpectedVersion
  $script:ProtectedKeyState = Get-Protected-Hmg-Key-State
  try {
    Stop-Hmg-Daemon-Before-Install $TargetDir
    Assert-Hmg-Daemon-Quiesced $TargetDir

    # The daemon is quiesced, so the store/WAL/index tuple is no longer changing.
    # Back up every existing store before touching the installed bundle. Raw key
    # files remain in place and are excluded from the readable verified archive.
    Backup-Existing-Hmg-Stores $script:ProtectedKeyState | Out-Null
    Assert-Protected-Hmg-Key-State $script:ProtectedKeyState

    $BackupDir = Join-Path $TempDir "rollback"
    $script:InstallTransaction = New-Hmg-Binary-Backup $TargetDir $Bins $BackupDir
  } catch {
    $PreSwitchError = $_.Exception.Message
    Start-Installed-Hmg-Best-Effort $TargetDir "blocked pre-switch validation"
    throw "HMG upgrade was blocked before binary replacement: $PreSwitchError"
  }
  if (Try-Copy-Hmg-Binaries $SourceDir $TargetDir $Bins) {
    return $true
  }

  Log "  Could not replace HMG binaries immediately: $script:LastBinaryCopyError"
  try {
    Restore-Hmg-Binaries $script:InstallTransaction
  } catch {
    throw "Failed to restore the existing HMG bundle before deferred update: $($_.Exception.Message)"
  }
  $script:InstallTransaction = $null
  try {
    return Schedule-Deferred-Binary-Install $SourceDir $TargetDir $Bins $script:ExpectedVersion $Manifest
  } catch {
    $DeferredScheduleError = $_.Exception.Message
    Start-Installed-Hmg-Best-Effort $TargetDir "deferred helper scheduling failure"
    throw "Could not schedule the verified deferred HMG update: $DeferredScheduleError"
  }
}

function Install-From-Release-Url([string] $Asset, [string] $BaseUrl) {
  $Url = $BaseUrl.TrimEnd("/") + "/" + $Asset
  $ArchivePath = Join-Path $TempDir $Asset
  $PackageDir = Join-Path $TempDir "package"

  if (Test-Path $PackageDir) {
    Remove-Item -Recurse -Force $PackageDir
  }
  New-Item -ItemType Directory -Force $PackageDir | Out-Null

  Log "  Trying: $Url"
  try {
    Download-File $Url $ArchivePath
  } catch {
    Log "  Download failed: $Url"
    return $false
  }

  try {
    Expand-Archive -Path $ArchivePath -DestinationPath $PackageDir -Force
  } catch {
    Log "  Invalid zip package: $Url"
    return $false
  }

  $RequiredBins = @("hmg.exe", "hmg-server.exe", "hmg-hook-worker.exe")
  foreach ($Bin in $RequiredBins) {
    if (-not (Test-Path (Join-Path $PackageDir $Bin))) {
      Log "  Missing binary: $Bin"
      return $false
    }
  }

  return Install-Hmg-Binaries $PackageDir $BinDir $RequiredBins $script:ExpectedVersion
}

function Release-Base-Urls {
  $BaseUrls = @($ReleaseBaseUrl, $PublicReleaseBaseUrl, $OfficialReleaseBaseUrl, $MirrorBaseUrl, $MirrorBaseUrl2)
  $BaseUrls = $BaseUrls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
  Write-Output $BaseUrls
}

function Resolve-Version-From-Release-Json([string] $BaseUrl) {
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    return $null
  }

  $VersionUrl = $BaseUrl.TrimEnd("/") + "/version.json"
  try {
    $Resp = Invoke-RestMethod -Uri $VersionUrl -TimeoutSec 10
    if ($Resp -and $Resp.version) {
      return [string] $Resp.version
    }
  } catch {}
  return $null
}

function Resolve-Latest-Version {
  foreach ($BaseUrl in (Release-Base-Urls)) {
    $Version = Resolve-Version-From-Release-Json $BaseUrl
    if ($Version) {
      return $Version
    }
  }

  try {
    $ApiUrl = "https://api.github.com/repos/HMG-AI/HMG-public/releases/latest"
    $Resp = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 10
    if ($Resp.tag_name -match '^v?(.+)$') {
      return $Matches[1]
    }
  } catch {}
  return $null
}

function Install-From-Release {
  $Version = Resolve-Latest-Version
  $script:ExpectedVersion = $Version

  # Try MSVC first (preferred), then fall back to GNU toolchain
  $MsvcTarget = Target-Triple
  $GnuTarget = Target-Triple-GNU
  $Targets = @($MsvcTarget, $GnuTarget) | Where-Object { $_ -ne "" } | Select-Object -Unique

  if ($Targets.Count -eq 0) {
    Log "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE"
    Supported-Targets
    return $false
  }

  foreach ($Target in $Targets) {
    Log "Platform: Windows/$env:PROCESSOR_ARCHITECTURE ($Target)"

    # Try versioned name first (e.g. hmg-1.0.0-x86_64-pc-windows-gnu.zip)
    # then fall back to unversioned (e.g. hmg-x86_64-pc-windows-gnu.zip)
    $Assets = @()
    if ($Version) {
      $Assets += "hmg-$Version-$Target.zip"
    }
    $Assets += "hmg-$Target.zip"

    foreach ($Asset in $Assets) {
      foreach ($BaseUrl in (Release-Base-Urls)) {
        if ($BaseUrl -and (Install-From-Release-Url $Asset $BaseUrl)) {
          return $true
        }
      }
    }
  }

  Log "No prebuilt HMG release package found for any supported target."
  Supported-Targets
  return $false
}

# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════

try {
  Log ""
  Log "╔══════════════════════════════════════╗"
  Log "║       HMG Installer for Windows      ║"
  Log "╚══════════════════════════════════════╝"
  Log ""

  # ── Step 1: Download & install binaries ──────────────────
  Log "[1/3] Downloading HMG..."
  New-Item -ItemType Directory -Force $TempDir | Out-Null
  if (-not (Install-From-Release)) {
    throw "HMG install failed: no release package is available for this platform."
  }
  if ($script:HmgInstallDeferred) {
    Log ""
    Log "[2/3] Preserving PATH..."
    Add-Hmg-To-Path
    Log ""
    Log "[3/3] Automatic finalization handed off."
    Log "  HMG is not reported complete yet: the invoking hmg.exe must exit before Windows can switch it."
    Log "  The hidden helper will stop the exact installed daemon, atomically switch all three binaries,"
    Log "  run setup, start and probe the target daemon, verify version takeover and protected keys,"
    Log "  and roll back the previous binaries automatically if any required step fails."
  } else {
    Log "  Candidate bundle switched; completion is pending strict initialization."
    Log ""
    Log "[2/3] Initializing and verifying HMG..."
    try {
      Initialize-And-Verify-Hmg $BinDir $script:ExpectedVersion $script:ProtectedKeyState
    } catch {
      $InitializationError = $_.Exception.Message
      try {
        Rollback-Hmg-Install $script:InstallTransaction $script:ProtectedKeyState
      } catch {
        throw "HMG initialization failed ($InitializationError), and binary rollback also failed: $($_.Exception.Message)"
      }
      throw "HMG initialization failed and the previous binary bundle was restored: $InitializationError"
    }

    Log ""
    Log "[3/3] Configuring PATH..."
    Add-Hmg-To-Path
    Log ""
    Log "╔══════════════════════════════════════╗"
    Log "║          Installation complete!       ║"
    Log "╚══════════════════════════════════════╝"
    Log ""
    Log "  Install dir: $BinDir"
    Log "  Version: $script:ExpectedVersion"
    Log "  Core setup, daemon startup, readiness, bundle identity, and key preservation verified."
    Log ""
    Log "  Quick commands:"
    Log "    hmg doctor           # Check system readiness"
    Log "    hmg daemon status    # Confirm the daemon remains ready"
    Log "    hmg tui              # Open terminal UI"
    Log ""
    Log "  Slow/blocked model downloads (mainland China)?"
    Log "    The daemon is already running; the optional embedding model can be fetched on demand."
    Log "    If HuggingFace is slow or blocked, set a mirror before an on-demand download:"
    Log "      `$env:HF_ENDPOINT = 'https://hf-mirror.com'"
    Log "      `$env:HMG_EMBEDDING_ENDPOINT = 'https://hf-mirror.com'"
    Log "      hmg model embedding download"
    Log ""
    Log "  Update later:"
    Log "    hmg update"
    Log ""
    Log "  Note: Open a new terminal for PATH to take effect in all windows."
  }
} finally {
  if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
  }
}
