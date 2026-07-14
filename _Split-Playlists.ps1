param(
    [string]$InputFolder = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [string]$FilePath,
    [string]$SplitFolder = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'SPLIT' } else { Join-Path (Get-Location).Path 'SPLIT' }),
    [string]$PlaylistFolder = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'PLAYLISTS' } else { Join-Path (Get-Location).Path 'PLAYLISTS' }),
    [long]$MaxSingleTrackSizeBytes = 10MB,
    [double]$SilenceThresholdDb = -32,
    [double]$MinSilenceDurationSeconds = 1.0,
    [double]$PaddingSeconds = 0.25
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
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdoutTask.Result
        StdErr   = $stderrTask.Result
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

    return $events.ToArray()
}

function Get-SegmentsFromSilence {
    param(
        [Parameter(Mandatory)] [double]$DurationSeconds,
        [object]$Events = @()
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

    return $segments.ToArray()
}

function Export-Segment {
    param(
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [double]$StartSeconds,
        [Parameter(Mandatory)] [double]$EndSeconds
    )

    $start = [math]::Max(0.0, $StartSeconds)
    $end = [math]::Max($start + 0.1, $EndSeconds)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $startArg = $start.ToString('0.###', $culture)
    $durationArg = ($end - $start).ToString('0.###', $culture)

    $args = @(
        '-y'
        '-hide_banner'
        '-loglevel', 'error'
        '-ss', $startArg
        '-t', $durationArg
        '-i', $InputPath
        '-c:a', 'libmp3lame'
        '-q:a', '2'
        $OutputPath
    )

    $result = Invoke-ProcessCapture -FilePath 'ffmpeg' -Arguments $args
    if ($result.ExitCode -ne 0) {
        throw "ffmpeg export failed for '$OutputPath'. $($result.StdErr.Trim())"
    }
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

New-Item -ItemType Directory -Force -Path $SplitFolder | Out-Null
New-Item -ItemType Directory -Force -Path $PlaylistFolder | Out-Null

$sourceFiles = if ($FilePath) {
    @(Get-Item -LiteralPath $FilePath)
}
else {
    Get-ChildItem -LiteralPath $InputFolder -File -Filter '*.mp3' | Sort-Object Length, Name
}

if (-not $sourceFiles) {
    Write-Host "No MP3 files found in '$InputFolder'."
    exit 0
}

$totalFiles = $sourceFiles.Count
$index = 0

foreach ($file in $sourceFiles) {
    $index++
    $percent = [math]::Round(($index / [double]$totalFiles) * 100, 1)
    Write-Progress -Id 1 -Activity 'Splitting playlists' -Status ("{0}/{1} {2}" -f $index, $totalFiles, $file.Name) -PercentComplete $percent
    Write-Host "Processing: $($file.Name)"

    if ($file.Length -lt $MaxSingleTrackSizeBytes) {
        Write-Host "  Short file, leaving as a single track."
        continue
    }

    try {
        $duration = Get-FileDurationSeconds -Path $file.FullName
        $events = Get-SilenceEvents -Path $file.FullName -ThresholdDb $SilenceThresholdDb -MinDurationSeconds $MinSilenceDurationSeconds
        $segments = Get-SegmentsFromSilence -DurationSeconds $duration -Events $events
    }
    catch {
        Write-Warning "Could not analyze '$($file.Name)': $($_.Exception.Message)"
        continue
    }

    if ($segments.Count -le 1) {
        Write-Host "  No split points found."
        continue
    }

    $safeBase = ($file.BaseName -replace '[\\/:*?"<>|]', '_').Trim()
    $trackIndex = 1
    foreach ($segment in $segments) {
        $trackName = '{0} {1:D2}.mp3' -f $safeBase, $trackIndex
        $trackPath = Join-Path $SplitFolder $trackName

        $start = [math]::Max(0.0, $segment.Start - $PaddingSeconds)
        $end = [math]::Min($duration, $segment.End + $PaddingSeconds)

        if ($end -le $start + 0.1) {
            continue
        }

        Export-Segment -InputPath $file.FullName -OutputPath $trackPath -StartSeconds $start -EndSeconds $end
        $trackIndex++
    }

    $destination = Move-FileSafely -File $file -DestinationFolder $PlaylistFolder
    Write-Host "  Split into $($trackIndex - 1) track(s) -> $SplitFolder"
}

Write-Progress -Id 1 -Activity 'Splitting playlists' -Completed
