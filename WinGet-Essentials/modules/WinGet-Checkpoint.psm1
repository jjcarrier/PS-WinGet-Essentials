Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

[string]$CheckpointFilePath = "$PSScriptRoot/winget.{HOSTNAME}.checkpoint"

<#
.DESCRIPTION
    Creates/updates a manifest file (winget.{HOSTNAME}.checkpoint) that
    contains a list of all software installed on this system that is available
    on WinGet through at least one source.

.EXAMPLE
    PS> Checkpoint-WingetSoftware
#>
function Checkpoint-WingetSoftware
{
    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (Test-Path $checkpointFile) {
        Move-Item -Force -Path $checkpointFile -Destination "$checkpointFile.bak"
    }

    Write-Output 'Creating checkpoint ...'
    $jobName = Start-Job -ArgumentList $checkpointFile -ScriptBlock {
        param([string]$outFile)

        $consoleOutEncoding = [console]::OutputEncoding
        $consoleInEncoding = [console]::InputEncoding
        [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        [console]::InputEncoding = [System.Text.UTF8Encoding]::new()
        winget export --include-versions -o $outFile
        [console]::OutputEncoding = $consoleOutEncoding
        [console]::InputEncoding = $consoleInEncoding
    }

    $notAvail = 'Installed package is not available from any source: '
    $versionNotAvail = 'Installed version of package is not available from any source: '
    $outInfo = [PSCustomObject]@{
        NotAvailable = @()
        VersionNotAvail = @()
    }

    $consoleOutEncoding = [console]::OutputEncoding
    $consoleInEncoding = [console]::InputEncoding
    [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [console]::InputEncoding = [System.Text.UTF8Encoding]::new()
    Show-JobProgress $jobName
    Receive-Job $jobName | Where-Object { $_.StartsWith('I') } | ForEach-Object {
        if ($_.StartsWith($notAvail)) {
            $outInfo.NotAvailable += $_.Replace($notAvail, '')
        } elseif ($_.StartsWith($versionNotAvail)) {
            $outInfo.VersionNotAvail += $_.Replace($versionNotAvail, '')
        }
    }
    [console]::OutputEncoding = $consoleOutEncoding
    [console]::InputEncoding = $consoleInEncoding

    Write-Output $versionNotAvail
    $outInfo.VersionNotAvail | Sort-Object -Unique | ForEach-Object { "`t- $_" }
    Write-Output $notAvail
    $outInfo.NotAvailable | Sort-Object -Unique | ForEach-Object { "`t- $_" }
}
