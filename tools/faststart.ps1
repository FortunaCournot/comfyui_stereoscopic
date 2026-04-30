<#
.SYNOPSIS
    Recursively probe files in a directory with ffprobe and convert video files
    to MP4 (H.264/AAC) with -movflags +faststart.

USAGE
    .\scripts\faststart.ps1 <directory>

NOTES
    - Accepts a single positional argument (directory).
    - ffprobe output is suppressed.
    - ffmpeg runs with minimal verbosity and shows progress only.
#>

param(
    [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $false)]
    [string]$Directory
)

function Write-ErrorAndExit {
    param($Message, $Code = 1)
    Write-Error $Message
    exit $Code
}

try {
    $resolved = Resolve-Path -Path $Directory -ErrorAction Stop
    $root = $resolved.Path
}
catch {
    Write-ErrorAndExit "Directory not found: $Directory" 2
}

$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffprobeCmd = Get-Command ffprobe -ErrorAction SilentlyContinue
if (-not $ffmpegCmd) { Write-ErrorAndExit 'ffmpeg not found in PATH.' 3 }
if (-not $ffprobeCmd) { Write-ErrorAndExit 'ffprobe not found in PATH.' 3 }

Write-Host "Scanning: $root"

Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_

    # Probe quietly. Suppress ffprobe stderr and capture stdout only.
    $probeOutput = & $ffprobeCmd.Path -v error -select_streams v -show_entries stream=codec_type -of csv=p=0 -i $file.FullName 2>$null

    if ($probeOutput -and $probeOutput.Trim().Length -gt 0) {
        Write-Host "Converting: $($file.FullName)"

        $dir = $file.DirectoryName
        $guid = [System.Guid]::NewGuid().ToString()
        $tempOutput = Join-Path $dir ("ffmpeg_tmp_{0}.mp4" -f $guid)

        # ffmpeg: minimal verbosity, show progress with -stats
        & $ffmpegCmd.Path -hide_banner -loglevel error -stats -i $file.FullName -c:v libx264 -crf 18 -preset medium -c:a aac -b:a 128k -pix_fmt yuv420p -movflags +faststart $tempOutput
        $exit = $LASTEXITCODE

        if ($exit -eq 0 -and (Test-Path $tempOutput)) {
            # target name = original base name + ".mp4" (avoid double extension)
            $targetName = $file.BaseName + ".mp4"
            $targetFull = Join-Path $dir $targetName

            $origFull = $file.FullName

            if (Test-Path $targetFull) {
                if ($targetFull -ne $origFull) {
                    try {
                        Remove-Item -Path $targetFull -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Warning ("Unable to remove existing target {0}: {1}" -f $targetFull, $_.Exception.Message)
                        $timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
                        $targetFull = Join-Path $dir ("$($file.BaseName)_converted_$timestamp.mp4")
                    }
                }
                # if targetFull equals origFull, we'll overwrite via Move-Item -Force below
            }

            try {
                Move-Item -Path $tempOutput -Destination $targetFull -Force -ErrorAction Stop

                # Delete original input file only if it's different from the target path
                if ($origFull -ne $targetFull -and (Test-Path $origFull)) {
                    Remove-Item -Path $origFull -Force -ErrorAction Stop
                }

                Write-Host ("Replaced: {0} -> {1}" -f $origFull, $targetFull)
            }
            catch {
                Write-Warning ("Failed to finalize conversion for {0}: {1}" -f $file.FullName, $_.Exception.Message)
                if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force -ErrorAction SilentlyContinue }
            }
        }
        else {
            Write-Warning "ffmpeg failed for $($file.FullName) (exit code $exit)."
            if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force -ErrorAction SilentlyContinue }
        }
    }
    else {
        # No video stream detected — skip
    }
}
