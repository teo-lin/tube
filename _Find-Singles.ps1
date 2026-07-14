param(
    [string]$InputFolder = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [string]$TrackFolder = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'SINGLES' } else { Join-Path (Get-Location).Path 'SINGLES' }),
    [long]$MaxSingleTrackSizeBytes = 12MB,
    [double]$SilenceThresholdDb = -32,
    [double]$MinSilenceDurationSeconds = 1.0,
    [int]$ThrottleLimit = [math]::Max(1, [math]::Min(4, [Environment]::ProcessorCount - 1))
)

$ErrorActionPreference = 'Stop'

function Move-FileSafely {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$DestinationFolder
    )

    $destination = Join-Path $DestinationFolder $File.Name
    $counter = 1
    while (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $DestinationFolder ('{0} ({1}){2}' -f $File.BaseName, $counter, $File.Extension)
        $counter++
    }

    Move-Item -LiteralPath $File.FullName -Destination $destination
    return $destination
}

New-Item -ItemType Directory -Force -Path $TrackFolder | Out-Null

$sourceFiles = Get-ChildItem -LiteralPath $InputFolder -File -Filter '*.mp3' | Sort-Object Name
if (-not $sourceFiles) {
    Write-Host "No MP3 files found in '$InputFolder'."
    exit 0
}

$totalFiles = $sourceFiles.Count
$movedCount = 0
$keptCount = 0
$index = 0

foreach ($file in $sourceFiles) {
    $index++
    $percent = [math]::Round(($index / [double]$totalFiles) * 100, 1)
    Write-Progress -Id 1 -Activity 'Finding singles by size' -Status ("{0}/{1} {2}" -f $index, $totalFiles, $file.Name) -PercentComplete $percent

    if ($file.Length -lt $MaxSingleTrackSizeBytes) {
        $destination = Move-FileSafely -File $file -DestinationFolder $TrackFolder
        $movedCount++
        Write-Host "Moved: $($file.Name) -> $(Split-Path -Leaf $destination)"
    }
    else {
        $keptCount++
        Write-Host "Kept: $($file.Name) ($([math]::Round($file.Length / 1MB, 1)) MB)"
    }
}

Write-Progress -Id 1 -Activity 'Finding singles by size' -Completed
Write-Host ("Done. Moved {0} file(s) under {1} MB to SINGLES; kept {2} larger file(s) in place." -f $movedCount, [math]::Round($MaxSingleTrackSizeBytes / 1MB, 1), $keptCount)
exit 0

<#
function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $quotedArgs = foreach ($arg in $Arguments) {
        if ($arg -match '\s|["]') {
            '"' + ($arg -replace '"', '\"') + '"'
        }
        else {
            $arg
        }
    }
    $psi.Arguments = ($quotedArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Get-FileDurationSeconds {
    param([Parameter(Mandatory)] [string]$Path)

    $result = Invoke-ProcessCapture -FilePath 'ffprobe' -Arguments @(
        '-v', 'error'
        '-show_entries', 'format=duration'
        '-of', 'default=noprint_wrappers=1:nokey=1'
        $Path
    )

    $durationText = $result.StdOut.Trim()
    if (-not $durationText) {
        throw "Could not read duration for '$Path'. $($result.StdErr.Trim())"
    }

    return [double]::Parse($durationText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-SilenceEvents {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [double]$ThresholdDb,
        [Parameter(Mandatory)] [double]$MinDurationSeconds
    )

    $args = @(
        '-hide_banner'
        '-nostats'
        '-i', $Path
        '-af', "silencedetect=noise=${ThresholdDb}dB:d=${MinDurationSeconds}"
        '-f', 'null'
        'NUL'
    )

    $result = Invoke-ProcessCapture -FilePath 'ffmpeg' -Arguments $args
    if ($result.ExitCode -ne 0 -and -not ($result.StdErr -match 'silence_(start|end)')) {
        throw "ffmpeg failed for '$Path'. $($result.StdErr.Trim())"
    }

    $output = @()
    if ($result.StdErr) {
        $output += $result.StdErr -split "(`r`n|`n|`r)"
    }
    if ($result.StdOut) {
        $output += $result.StdOut -split "(`r`n|`n|`r)"
    }

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($line in $output) {
        if ($line -match 'silence_start:\s*(?<start>\d+(?:\.\d+)?)') {
            $events.Add([pscustomobject]@{
                Type = 'start'
                Time = [double]::Parse($Matches['start'], [System.Globalization.CultureInfo]::InvariantCulture)
            })
        }
        elseif ($line -match 'silence_end:\s*(?<end>\d+(?:\.\d+)?)\s*\|\s*silence_duration:\s*(?<dur>\d+(?:\.\d+)?)') {
            $events.Add([pscustomobject]@{
                Type = 'end'
                Time = [double]::Parse($Matches['end'], [System.Globalization.CultureInfo]::InvariantCulture)
            })
        }
    }

    return $events
}

function Get-SegmentsFromSilence {
    param(
        [Parameter(Mandatory)] [double]$DurationSeconds,
        [Parameter(Mandatory)] [object]$Events
    )

    $segments = New-Object System.Collections.Generic.List[object]
    $segmentStart = 0.0

    foreach ($event in @($Events)) {
        if ($event.Type -eq 'start') {
            $silenceStart = [math]::Max(0.0, [double]$event.Time)
            if ($silenceStart -gt $segmentStart + 0.05) {
                $segments.Add([pscustomobject]@{
                    Start = $segmentStart
                    End   = $silenceStart
                })
            }
        }
        elseif ($event.Type -eq 'end') {
            $segmentStart = [math]::Max(0.0, [double]$event.Time)
        }
    }

    if ($DurationSeconds -gt $segmentStart + 0.05) {
        $segments.Add([pscustomobject]@{
            Start = $segmentStart
            End   = $DurationSeconds
        })
    }

    return @($segments)
}

function Move-FileSafely {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$DestinationFolder
    )

    $destination = Join-Path $DestinationFolder $File.Name
    $counter = 1
    while (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $DestinationFolder ('{0} ({1}){2}' -f $File.BaseName, $counter, $File.Extension)
        $counter++
    }

    Move-Item -LiteralPath $File.FullName -Destination $destination
    return $destination
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg was not found in PATH."
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffprobe was not found in PATH."
}

New-Item -ItemType Directory -Force -Path $TrackFolder | Out-Null

$analysisScript = {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [double]$ThresholdDb,
        [Parameter(Mandatory)] [double]$MinDurationSeconds
    )

    $ErrorActionPreference = 'Stop'

    function Invoke-ProcessCapture {
        param(
            [Parameter(Mandatory)] [string]$FilePath,
            [Parameter(Mandatory)] [string[]]$Arguments
        )

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $quotedArgs = foreach ($arg in $Arguments) {
            if ($arg -match '\s|["]') {
                '"' + ($arg -replace '"', '\"') + '"'
            }
            else {
                $arg
            }
        }
        $psi.Arguments = ($quotedArgs -join ' ')
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }

    function Get-FileDurationSeconds {
        param([Parameter(Mandatory)] [string]$FilePath)

        $result = Invoke-ProcessCapture -FilePath 'ffprobe' -Arguments @(
            '-v', 'error'
            '-show_entries', 'format=duration'
            '-of', 'default=noprint_wrappers=1:nokey=1'
            $FilePath
        )

        $durationText = $result.StdOut.Trim()
        if (-not $durationText) {
            throw "Could not read duration. $($result.StdErr.Trim())"
        }

        return [double]::Parse($durationText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    }

    function Get-SilenceEvents {
        param(
            [Parameter(Mandatory)] [string]$FilePath,
            [Parameter(Mandatory)] [double]$NoiseThresholdDb,
            [Parameter(Mandatory)] [double]$MinimumDurationSeconds
        )

        $result = Invoke-ProcessCapture -FilePath 'ffmpeg' -Arguments @(
            '-hide_banner'
            '-nostats'
            '-i', $FilePath
            '-af', "silencedetect=noise=${NoiseThresholdDb}dB:d=${MinimumDurationSeconds}"
            '-f', 'null'
            'NUL'
        )

        if ($result.ExitCode -ne 0 -and -not ($result.StdErr -match 'silence_(start|end)')) {
            throw "ffmpeg failed. $($result.StdErr.Trim())"
        }

        $output = @()
        if ($result.StdErr) {
            $output += $result.StdErr -split "(`r`n|`n|`r)"
        }
        if ($result.StdOut) {
            $output += $result.StdOut -split "(`r`n|`n|`r)"
        }

        $events = New-Object System.Collections.Generic.List[object]
        foreach ($line in $output) {
            if ($line -match 'silence_start:\s*(?<start>\d+(?:\.\d+)?)') {
                $events.Add([pscustomobject]@{
                    Type = 'start'
                    Time = [double]::Parse($Matches['start'], [System.Globalization.CultureInfo]::InvariantCulture)
                })
            }
            elseif ($line -match 'silence_end:\s*(?<end>\d+(?:\.\d+)?)\s*\|\s*silence_duration:\s*(?<dur>\d+(?:\.\d+)?)') {
                $events.Add([pscustomobject]@{
                    Type = 'end'
                    Time = [double]::Parse($Matches['end'], [System.Globalization.CultureInfo]::InvariantCulture)
                })
            }
        }

        return $events
    }

    function Get-SegmentCountFromSilence {
        param(
            [Parameter(Mandatory)] [double]$DurationSeconds,
            [Parameter(Mandatory)] [object]$Events
        )

        $segmentCount = 0
        $segmentStart = 0.0

        foreach ($event in @($Events)) {
            if ($event.Type -eq 'start') {
                $silenceStart = [math]::Max(0.0, [double]$event.Time)
                if ($silenceStart -gt $segmentStart + 0.05) {
                    $segmentCount++
                }
            }
            elseif ($event.Type -eq 'end') {
                $segmentStart = [math]::Max(0.0, [double]$event.Time)
            }
        }

        if ($DurationSeconds -gt $segmentStart + 0.05) {
            $segmentCount++
        }

        return $segmentCount
    }

    try {
        $duration = Get-FileDurationSeconds -FilePath $Path
        $events = Get-SilenceEvents -FilePath $Path -NoiseThresholdDb $ThresholdDb -MinimumDurationSeconds $MinDurationSeconds
        $segmentCount = Get-SegmentCountFromSilence -DurationSeconds $duration -Events $events

        [pscustomobject]@{
            Path         = $Path
            Name         = $Name
            IsSingle     = ($segmentCount -le 1)
            SegmentCount = $segmentCount
            Error        = $null
        }
    }
    catch {
        [pscustomobject]@{
            Path         = $Path
            Name         = $Name
            IsSingle     = $false
            SegmentCount = 0
            Error        = $_.Exception.Message
        }
    }
}

$sourceFiles = Get-ChildItem -LiteralPath $InputFolder -File -Filter '*.mp3' | Sort-Object Name
if (-not $sourceFiles) {
    Write-Host "No MP3 files found in '$InputFolder'."
    exit 0
}

$totalFiles = $sourceFiles.Count
$completedCount = 0
$movedCount = 0
$keptCount = 0
$script:analysisJobs = @()

function Update-ScanProgress {
    param([Parameter(Mandatory)] [string]$Status)

    $percent = if ($totalFiles -gt 0) {
        [math]::Round(($completedCount / [double]$totalFiles) * 100, 1)
    }
    else {
        100
    }

    Write-Progress -Id 1 -Activity 'Scanning MP3s' -Status $Status -PercentComplete $percent
}

function Complete-AnalysisJob {
    param([Parameter(Mandatory)] [System.Management.Automation.Job]$Job)

    $result = Receive-Job -Job $Job | Select-Object -Last 1
    Remove-Job -Job $Job -Force
    $script:analysisJobs = @($script:analysisJobs | Where-Object { $_.Id -ne $Job.Id })
    $script:completedCount++

    if (-not $result) {
        $script:keptCount++
        Write-Warning "Could not classify a file because the analysis job returned no result."
        return
    }

    if ($result.Error) {
        $script:keptCount++
        Write-Warning "Could not classify '$($result.Name)': $($result.Error)"
        return
    }

    if ($result.IsSingle) {
        $file = Get-Item -LiteralPath $result.Path -ErrorAction SilentlyContinue
        if ($file) {
            $destination = Move-FileSafely -File $file -DestinationFolder $TrackFolder
            $script:movedCount++
            Write-Host "Moved: $($result.Name) -> $(Split-Path -Leaf $destination)"
        }
        else {
            $script:keptCount++
            Write-Warning "Could not move '$($result.Name)' because it no longer exists."
        }
    }
    else {
        $script:keptCount++
        Write-Host "Kept: $($result.Name) ($($result.SegmentCount) segments)"
    }
}

foreach ($file in $sourceFiles) {
    try {
        if ($file.Length -lt $MaxSingleTrackSizeBytes) {
            $completedCount++
            Update-ScanProgress -Status ("{0}/{1} moving short file: {2}" -f $completedCount, $totalFiles, $file.Name)
            $destination = Move-FileSafely -File $file -DestinationFolder $TrackFolder
            $movedCount++
            Write-Host "Moved: $($file.Name) -> $(Split-Path -Leaf $destination)"
            continue
        }

        while ($analysisJobs.Count -ge $ThrottleLimit) {
            [void](Wait-Job -Job $analysisJobs -Any)
            foreach ($finishedJob in @($analysisJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') })) {
                Complete-AnalysisJob -Job $finishedJob
                Update-ScanProgress -Status ("{0}/{1} analyzed files; {2} active job(s)" -f $completedCount, $totalFiles, $analysisJobs.Count)
            }
        }

        $analysisJobs += Start-Job -ScriptBlock $analysisScript -ArgumentList $file.FullName, $file.Name, $SilenceThresholdDb, $MinSilenceDurationSeconds
        Update-ScanProgress -Status ("{0}/{1} queued: {2}; {3} active job(s)" -f $completedCount, $totalFiles, $file.Name, $analysisJobs.Count)
    }
    catch {
        $completedCount++
        $keptCount++
        Write-Warning "Could not classify '$($file.Name)': $($_.Exception.Message)"
    }
}

while ($analysisJobs.Count -gt 0) {
    [void](Wait-Job -Job $analysisJobs -Any)
    foreach ($finishedJob in @($analysisJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') })) {
        Complete-AnalysisJob -Job $finishedJob
        Update-ScanProgress -Status ("{0}/{1} analyzed files; {2} active job(s)" -f $completedCount, $totalFiles, $analysisJobs.Count)
    }
}

Write-Progress -Id 1 -Activity 'Scanning MP3s' -Completed
Write-Host ("Done. Moved {0} file(s) to SINGLES; kept {1} file(s) in place." -f $movedCount, $keptCount)
#>
