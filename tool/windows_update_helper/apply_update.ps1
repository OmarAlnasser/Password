<#
  apply_update.ps1 - swaps the files of an installed app for a verified update.

  The app starts this script DETACHED (arguments as a list, never through a
  command string), then exits. Everything here runs on the user's own machine,
  with the user's own rights, and touches nothing outside the install folder
  and the two private folders the app created for this run. No network.

  Source of truth: this file. lib/services/update/windows_installer.dart holds a
  byte-identical copy (a test checks it; tool/windows_update_helper/embed_script.py
  refreshes it). Keep this file ASCII only and compatible with Windows
  PowerShell 5.1 (no ternary, no ?., no &&, no [type]::new).

  Order of work:
    1. Check the arguments and the staged files; take a per-folder lock. Any
       problem ends here with NOTHING changed and the app still running (the
       app waits for the ReadyFile before it exits).
    2. Write the ReadyFile, then wait for the app (ProcessId) and for every
       other program that runs from the install folder to exit.
    3. Back up the files the update will overwrite, copy the new files over the
       install folder (no deletes, no purge), verify size and SHA-256.
    4. On any failure after step 3 started: put the backed up files back.
    5. Start the app again (the new one after success, the old one after a
       failed swap), remove the staging and backup folders, write the log.

  The log (LogFile) holds step names, counts and exit codes only. It never holds
  a path, a user name or any secret. The last line is "RESULT <token>".

  Exit codes: 0 updated, 2 bad arguments, 3 another update is running,
  10 the app did not exit in time, 11 staged files or install folder not as
  expected, 12 the app took its go-ahead back (ReadyFile gone or changed),
  20 swap failed and was rolled back, 21 swap failed and the rollback failed
  too, 30 unexpected error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$StagingDir,
    [Parameter(Mandatory = $true)][string]$ExeName,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$ReadyFile = '',
    [string]$LogFile = '',
    [int]$WaitSeconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:LogPath = ''
$script:Robocopy = 'robocopy.exe'

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($script:LogPath)) { return }
    try {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        $line = $stamp + ' ' + $Message + [System.Environment]::NewLine
        [System.IO.File]::AppendAllText($script:LogPath, $line)
    } catch {
        # The log is a courtesy; never let it break the update.
    }
}

# Exception type and HRESULT only: the message text can carry paths.
function Get-ErrorTag {
    param($ErrorRecord)
    try {
        $e = $ErrorRecord.Exception
        return ('{0} 0x{1:X8}' -f $e.GetType().Name, $e.HResult)
    } catch {
        return 'unknown'
    }
}

# An expected failure: a code for the exit status and a fixed tag for the log.
function New-UpdateError {
    param([int]$Code, [string]$Tag)
    $e = New-Object -TypeName System.InvalidOperationException -ArgumentList ('update:' + $Tag)
    $e.Data['code'] = $Code
    return $e
}

function Test-LocalAbsolutePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # UNC paths and device paths (\\server\share, \\?\C:\, \\.\pipe).
    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) { return $false }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return ($Path -match '^[A-Za-z]:[\\/]')
    }
    return $Path.StartsWith('/')
}

function Get-NormalizedDirectory {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-IsRoot {
    param([string]$FullPath)
    return ([System.IO.Path]::GetPathRoot($FullPath).Length -ge $FullPath.Length)
}

# True when $Child is the same folder as $Parent or lies inside it.
function Test-SameOrInside {
    param([string]$Child, [string]$Parent)
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    $c = $Child.TrimEnd($sep) + $sep
    $p = $Parent.TrimEnd($sep) + $sep
    return $c.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-FileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($stream))
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

# Runs a script block, retrying a few times (antivirus scanners and search
# indexers keep files open for a moment).
function Invoke-WithRetry {
    param([scriptblock]$Action, [int]$Attempts = 5, [int]$DelayMs = 1000)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            & $Action | Out-Null
            return
        } catch {
            if ($i -ge $Attempts) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

# Every file below $Root as a relative path (no leading separator).
function Get-RelativeFiles {
    param([string]$Root)
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $result = New-Object -TypeName 'System.Collections.Generic.List[string]'
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)) {
        if (-not $f.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (New-UpdateError 11 'unexpected-file-location')
        }
        $result.Add($f.FullName.Substring($prefix.Length))
    }
    return , $result
}

# Process ids (other than ours) whose program file lies in the install folder.
function Get-InstallDirProcessIds {
    $found = New-Object -TypeName 'System.Collections.Generic.List[int]'
    foreach ($proc in @(Get-Process)) {
        if ($proc.Id -eq $PID) { continue }
        $path = $null
        try { $path = $proc.Path } catch { $path = $null }
        if (-not [string]::IsNullOrEmpty($path)) {
            if (Test-SameOrInside -Child $path -Parent $script:InstallFull) { $found.Add($proc.Id) }
        }
    }
    return , $found
}

# Waits for the app (ProcessId) to exit. A process id can be reused: when it
# now belongs to a program with another name, the app is already gone. An error
# while looking at the process means it went away under our hands (it is
# exiting right now, which is the normal case), so it ends the wait too; the
# check for other programs from the install folder is the safety net.
function Wait-ForApp {
    param([string]$Exe, [int]$Id, [DateTime]$Deadline)
    $exeBase = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
    while ($true) {
        $app = Get-Process -Id $Id -ErrorAction SilentlyContinue
        if ($null -eq $app) { return }
        try {
            $name = $app.ProcessName
            if (($name -ine $exeBase) -and ($name -ine $Exe)) { return }
            if ($app.HasExited) { return }
        } catch {
            return
        }
        if ([DateTime]::UtcNow -ge $Deadline) { throw (New-UpdateError 10 'app-did-not-exit') }
        Start-Sleep -Milliseconds 250
    }
}

function Invoke-Robocopy {
    param([string]$Source, [string]$Destination, [int]$Attempts = 3)
    $code = 16
    for ($i = 1; $i -le $Attempts; $i++) {
        # /E subfolders, /IS /IT also files that look unchanged, /XJ no junctions.
        # No purge or mirror option is used: nothing in the destination is ever
        # deleted.
        & $script:Robocopy $Source $Destination /E /IS /IT /R:2 /W:1 /XJ /NP /NFL /NDL /NJH /NJS | Out-Null
        $code = $global:LASTEXITCODE
        # 0..7 are success codes (nothing copied, copied, extra files, ...).
        if ($code -lt 8) { return $code }
        Write-Log ('robocopy attempt {0} failed with code {1}' -f $i, $code)
        if ($i -lt $Attempts) { Start-Sleep -Seconds 2 }
    }
    return $code
}

# What an update needs: the program, the engine and the data folder in the
# staging folder, and the program in the install folder.
function Test-Layout {
    param([string]$Staging, [string]$Install, [string]$Exe)
    if (-not (Test-Path -LiteralPath (Join-Path $Staging $Exe) -PathType Leaf)) { throw (New-UpdateError 11 'staged-exe-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Staging 'flutter_windows.dll') -PathType Leaf)) { throw (New-UpdateError 11 'staged-engine-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Staging 'data') -PathType Container)) { throw (New-UpdateError 11 'staged-data-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Install $Exe) -PathType Leaf)) { throw (New-UpdateError 11 'installed-exe-missing') }
}

# Plain CreateProcess through .NET: the path is used as given (Start-Process
# treats square brackets in a path as a wildcard in some versions).
function Start-App {
    param([string]$ExePath)
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $ExePath
    $info.WorkingDirectory = $script:InstallFull
    $info.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($info)
}

function Write-ReadyFile {
    param([string]$Content)
    if ([string]::IsNullOrEmpty($ReadyFile)) { return }
    try { [System.IO.File]::WriteAllText($ReadyFile, $Content) } catch { }
}

# The app deletes the ReadyFile when it gives up on this update (it saw no
# go-ahead in time, or it is not going to exit). A script that was just slow
# must not then swap files behind the back of a user who is still working.
function Assert-NotCancelled {
    if ([string]::IsNullOrEmpty($ReadyFile)) { return }
    $text = $null
    try { $text = [System.IO.File]::ReadAllText($ReadyFile) } catch { $text = $null }
    if ($text -ne 'ready') { throw (New-UpdateError 12 'cancelled') }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$exitCode = 30
$result = 'unexpected-error'
$phase = 'validate'     # validate -> waiting -> swap
$touched = $false       # true once a file in the install folder may have changed
$relaunch = $false
$mutex = $null
$haveLock = $false
$script:InstallFull = ''
$stagingFull = ''
$backupFull = ''

try {
    if ([string]::IsNullOrEmpty($LogFile)) {
        $LogFile = Join-Path ([System.IO.Path]::GetTempPath()) 'update-helper.log'
    }
    $script:LogPath = $LogFile
    try { [System.IO.File]::WriteAllText($script:LogPath, '') } catch { $script:LogPath = '' }
    Write-Log 'start'

    # --- 1. arguments ------------------------------------------------------
    foreach ($candidate in @($InstallDir, $StagingDir, $BackupDir)) {
        if (-not (Test-LocalAbsolutePath $candidate)) { throw (New-UpdateError 2 'path-not-local') }
    }
    if ($ProcessId -le 0) { throw (New-UpdateError 2 'bad-process-id') }
    if ($WaitSeconds -lt 1 -or $WaitSeconds -gt 600) { throw (New-UpdateError 2 'bad-wait') }
    if ([string]::IsNullOrEmpty($ExeName) -or
        [System.IO.Path]::GetFileName($ExeName) -ne $ExeName -or
        -not $ExeName.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -or
        $ExeName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw (New-UpdateError 2 'bad-exe-name')
    }

    $script:InstallFull = Get-NormalizedDirectory $InstallDir
    $stagingFull = Get-NormalizedDirectory $StagingDir
    $backupFull = Get-NormalizedDirectory $BackupDir
    foreach ($candidate in @($script:InstallFull, $stagingFull, $backupFull)) {
        if (Test-IsRoot $candidate) { throw (New-UpdateError 2 'path-is-root') }
    }
    # None of the three may contain or equal another: a mistake here could make
    # the clean-up delete the installed app.
    $dirs = @($script:InstallFull, $stagingFull, $backupFull)
    for ($a = 0; $a -lt $dirs.Count; $a++) {
        for ($b = 0; $b -lt $dirs.Count; $b++) {
            if ($a -ne $b -and (Test-SameOrInside -Child $dirs[$a] -Parent $dirs[$b])) {
                throw (New-UpdateError 2 'paths-overlap')
            }
        }
    }

    # --- single update per install folder ---------------------------------
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($script:InstallFull.ToLowerInvariant())
    $nameHash = [System.BitConverter]::ToString($sha.ComputeHash($nameBytes)).Replace('-', '').Substring(0, 32)
    $sha.Dispose()
    $mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, ('Local\update-helper-' + $nameHash)
    try {
        $haveLock = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $haveLock = $true
    }
    if (-not $haveLock) { throw (New-UpdateError 3 'another-update-running') }

    # --- 2. staged files and install folder, before anything is touched ----
    Test-Layout -Staging $stagingFull -Install $script:InstallFull -Exe $ExeName
    if (Test-Path -LiteralPath $backupFull) {
        # A leftover backup could be restored over newer files. Refuse it.
        if ((Test-Path -LiteralPath $backupFull -PathType Leaf) -or @(Get-ChildItem -LiteralPath $backupFull -Force).Count -gt 0) {
            throw (New-UpdateError 11 'backup-folder-not-empty')
        }
    }
    $stagedFiles = Get-RelativeFiles $stagingFull
    if ($stagedFiles.Count -lt 3) { throw (New-UpdateError 11 'staged-too-few-files') }
    if ($env:SystemRoot) {
        $candidatePath = Join-Path (Join-Path $env:SystemRoot 'System32') 'robocopy.exe'
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { $script:Robocopy = $candidatePath }
    }
    Write-Log ('checked {0} staged files' -f $stagedFiles.Count)

    # --- 3. tell the app it may exit, then wait for it ---------------------
    Write-ReadyFile 'ready'
    $phase = 'waiting'
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)

    Wait-ForApp -Exe $ExeName -Id $ProcessId -Deadline $deadline
    Write-Log 'app exited'
    # Other windows of the app (a second instance) keep their files locked.
    while ($true) {
        $others = Get-InstallDirProcessIds
        if ($others.Count -eq 0) { break }
        if ([DateTime]::UtcNow -ge $deadline) { throw (New-UpdateError 10 'another-instance-running') }
        Start-Sleep -Milliseconds 500
    }
    Assert-NotCancelled
    # Handles of the exited process and of antivirus scans need a moment.
    Start-Sleep -Milliseconds 700

    # --- 4. swap -----------------------------------------------------------
    $phase = 'swap'
    Test-Layout -Staging $stagingFull -Install $script:InstallFull -Exe $ExeName

    # Back up only the files the update will overwrite. (A full copy of the
    # install folder could be gigabytes when the app sits in Downloads.)
    $backedUp = 0
    foreach ($rel in $stagedFiles) {
        $target = Join-Path $script:InstallFull $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $copyTo = Join-Path $backupFull $rel
            $copyToDir = [System.IO.Path]::GetDirectoryName($copyTo)
            [void][System.IO.Directory]::CreateDirectory($copyToDir)
            Invoke-WithRetry { [System.IO.File]::Copy($target, $copyTo, $true) }
            $backedUp++
        }
    }
    [void][System.IO.Directory]::CreateDirectory($backupFull)
    Write-Log ('backed up {0} files' -f $backedUp)

    $touched = $true
    # A read-only attribute would make the overwrite fail.
    foreach ($rel in $stagedFiles) {
        $target = Join-Path $script:InstallFull $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $attrs = [int][System.IO.File]::GetAttributes($target)
            if (($attrs -band 1) -ne 0) {
                [System.IO.File]::SetAttributes($target, [System.IO.FileAttributes]($attrs -band (-bnot 1)))
            }
        }
    }

    $copyCode = Invoke-Robocopy -Source $stagingFull -Destination $script:InstallFull
    if ($copyCode -ge 8) { throw (New-UpdateError 20 'copy-failed') }
    Write-Log ('copied, robocopy code {0}' -f $copyCode)

    foreach ($rel in $stagedFiles) {
        $source = Join-Path $stagingFull $rel
        $target = Join-Path $script:InstallFull $rel
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw (New-UpdateError 20 'verify-missing') }
        if ((Get-Item -LiteralPath $source -Force).Length -ne (Get-Item -LiteralPath $target -Force).Length) { throw (New-UpdateError 20 'verify-size') }
        if ((Get-FileSha256 $source) -ne (Get-FileSha256 $target)) { throw (New-UpdateError 20 'verify-hash') }
    }
    Write-Log ('verified {0} files' -f $stagedFiles.Count)

    $exitCode = 0
    $result = 'success'
    $relaunch = $true
} catch {
    $failure = $_.Exception
    $tag = Get-ErrorTag $_
    $code = 30
    if ($failure.Message.StartsWith('update:')) {
        $tag = $failure.Message.Substring(7)
        $code = [int]$failure.Data['code']
    }
    $exitCode = $code
    $result = 'aborted ' + $tag
    Write-Log ('failed in phase {0}: {1}' -f $phase, $tag)

    if ($phase -eq 'validate') {
        # The app is still running and nothing was changed. Tell it so.
        Write-ReadyFile ('abort ' + $tag)
    } elseif ($phase -eq 'waiting') {
        # Nothing was changed. An instance that is still running stays as it is;
        # otherwise the user gets the app back.
        $relaunch = ($tag -ne 'app-did-not-exit' -and $tag -ne 'another-instance-running' -and $tag -ne 'cancelled')
    } else {
        $relaunch = $true
        if ($touched) {
            Write-Log 'rolling back'
            try {
                $restoreCode = 0
                if (Test-Path -LiteralPath $backupFull -PathType Container) {
                    $restoreCode = Invoke-Robocopy -Source $backupFull -Destination $script:InstallFull
                }
                if ($restoreCode -ge 8) { throw 'restore failed' }
                $exitCode = 20
                $result = 'rolled-back ' + $tag
                Write-Log 'rolled back'
            } catch {
                $exitCode = 21
                $result = 'rollback-failed ' + $tag
                Write-Log ('rollback failed: ' + (Get-ErrorTag $_))
            }
        }
    }
} finally {
    try {
        if ($relaunch -and $script:InstallFull -ne '') {
            $exeToStart = Join-Path $script:InstallFull $ExeName
            $running = $false
            try { $running = ((Get-InstallDirProcessIds).Count -gt 0) } catch { $running = $false }
            if ((Test-Path -LiteralPath $exeToStart -PathType Leaf) -and -not $running) {
                Write-Log 'starting the app'
                Start-App $exeToStart
            }
        }
    } catch {
        Write-Log ('start failed: ' + (Get-ErrorTag $_))
    }

    if ($exitCode -eq 0) {
        # The update is in place; the staging and backup folders are not needed.
        foreach ($folder in @($stagingFull, $backupFull)) {
            try {
                if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                    Remove-Item -LiteralPath $folder -Recurse -Force
                }
            } catch {
                Write-Log ('clean-up failed: ' + (Get-ErrorTag $_))
            }
        }
    }

    if ($haveLock -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) { $mutex.Dispose() }
    Write-Log ('RESULT ' + $result)
}

exit $exitCode
