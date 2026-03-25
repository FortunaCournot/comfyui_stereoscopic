Param(
    [switch]$Commit
)

# Create a junction .github\prompts -> copilot\prompts if missing (Windows)
try {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    # script is in <repo>/copilot/scripts, repo root is two levels up
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
    $githubPrompts = Join-Path $repoRoot '.github\prompts'
    # point junction to local generated prompts by default
    $localPrompts = Join-Path $repoRoot '.copilot_local\prompts'

    $copilotPrompts = Join-Path $repoRoot 'copilot\prompts'

    # Prefer local generated prompts as target if available
    if (Test-Path $localPrompts) {
        $target = $localPrompts
    } elseif (Test-Path $copilotPrompts) {
        $target = $copilotPrompts
    } else {
        Write-Output "No target prompt folder found (neither $localPrompts nor $copilotPrompts). Nothing to link";
        exit 1
    }

    if (Test-Path $githubPrompts) {
        # If already a junction/symlink, report and exit
        $item = Get-Item -LiteralPath $githubPrompts -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Output "Junction already exists: $githubPrompts -> (reparse point)"
            exit 0
        }
        # If it's a non-empty directory, do not remove
        $entries = Get-ChildItem -LiteralPath $githubPrompts -Force -ErrorAction SilentlyContinue
        if ($entries.Count -gt 0) {
            Write-Output "Existing non-empty directory at $githubPrompts; will not remove. Aborting."
            exit 1
        }
        # Remove empty folder
        Remove-Item -LiteralPath $githubPrompts -Force -Recurse -ErrorAction Stop
        Write-Output "Removed empty folder $githubPrompts"
    }

    # Create junction using cmd mklink for compatibility
    $cmd = "cmd /c mklink /J `"$githubPrompts`" `"$target`""
    Write-Output "Creating junction: $cmd"
    $proc = Start-Process -FilePath cmd -ArgumentList "/c mklink /J `"$githubPrompts`" `"$target`"" -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Output "mklink failed with exit code $($proc.ExitCode)"
        exit $proc.ExitCode
    }

    Write-Output "Junction created: $githubPrompts -> $target"

    if ($Commit) {
        Push-Location $repoRoot
        try {
            git add .gitignore
            git rm -r --cached .github\prompts -f 2>$null | Out-Null
            git commit -m "Ignore local junction .github/prompts" -q
            Write-Output "Updated .gitignore and committed changes"
        } catch {
            Write-Output "Failed to update git index/commit: $_"
        } finally {
            Pop-Location
        }
    }
    exit 0
} catch {
    Write-Output "Error creating junction: $_"
    exit 2
}
