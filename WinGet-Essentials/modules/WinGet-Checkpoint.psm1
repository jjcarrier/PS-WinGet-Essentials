[string]$CheckpointFilePath = "$PSScriptRoot/winget.{HOSTNAME}.checkpoint"

<#
.DESCRIPTION
    Creates/updates a manifest file (winget.{HOSTNAME}.checkpoint) that
    contains a list of all software installed on this system that is available
    on WinGet through at least one source.
#>
function Checkpoint-WingetSoftware
{
    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (Test-Path $checkpointFile) {
        Move-Item -Force -Path $checkpointFile -Destination "$checkpointFile.bak"
    }

    winget export --include-versions -o $checkpointFile
}
