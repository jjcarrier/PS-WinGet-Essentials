Set-StrictMode -Version 2

[string]$IgnoreFilePath = "$PSScriptRoot\winget.{HOSTNAME}.ignore"
[string]$CheckpointFilePath = "$PSScriptRoot\winget.{HOSTNAME}.checkpoint"
[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"

<#
.DESCRIPTION
    Merge host-installed package IDs into "winget.packages.json".
#>
function Merge-WinGetRestore
{
    param(
        # When set, the package ignore-file is not applied.
        [switch]$NoIgnore,

        # Skip prompts for confirmation to merge missing package IDs.
        [switch]$MergeAll,

        # Skip prompts for tagging new package IDs.
        [switch]$NoTags,

        # Skips performing a checkpoint.
        [switch]$NoCheckpoint
    )

    if ($NoCheckpoint) {
        # Skip performing a checkpoint.
    } else {
        Checkpoint-WinGetSoftware
    }

    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
    if (-not(Test-Path $checkpointFile)) {
        Write-Error "No checkpoint file found."
        return
    }

    $installedPackages = Get-Content $checkpointFile | ConvertFrom-Json
    $installedPackages = @($installedPackages.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }).Packages

    if (-not(Test-Path $PackageDatabase)) {
        Write-Error "A 'winget.packages.json' is required to use this cmdlet. Please see Initialize-WinGetRestore."
        return
    }

    $packages = Get-Content $PackageDatabase | ConvertFrom-Json

    $newPackages = $installedPackages.PackageIdentifier | Where-Object { $packages.PackageIdentifier -notcontains $_ }
    $newPackages = $newPackages | Sort-Object -Unique

    if ($NoIgnore) {
        # Skip ignore package filtering.
    } else {
        # TODO: replace with Get-WinGetSoftwareIgnores

        $ignorePackages = $null
        $ignoreFile = $IgnoreFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
        if (Test-Path $ignoreFile)
        {
            $ignorePackages = Get-Content $ignoreFile
        }

        $newPackages = $newPackages | Where-Object { $ignorePackages -notcontains $_ }
    }

    $jsonModified = $false
    $newPackages | ForEach-Object {
        $merge = $true
        if (-not($MergeAll)) {
            $question = "Merge package '$_' into 'winget.packages.json'?"
            $choices = @(
                [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Do merge")
                [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Do not merge")
            )

            $decision = $Host.UI.PromptForChoice($null, $question, $choices, 1)
            $merge = $decision -eq 0
        }

        if ($merge) {
            $newEntry = [PSCustomObject]@{
                PackageIdentifier = [string]$_
                Tags = @()
            }

            if ($NoTags) {
                # Skip prompting user for tagging each new package.
            } else {
                Write-Output "Enter tags for package '$_'. An empty entry concludes data entry."
                while ($true) {
                    $tagEntry = Read-Host "Enter a tag name"

                    if ([string]::IsNullOrWhiteSpace($tagEntry)) {
                        break
                    }

                    $newEntry.Tags += $tagEntry
                }
            }

            $packages += $newEntry
            $jsonModified = $true
            Write-Output "Added package '$_'"
        } else {
            Write-Output "Skipped package: '$_'"
        }
    }

    if ($jsonModified) {
        $packages | ConvertTo-Json | Out-File $PackageDatabase
        if ($?) {
            Write-Output "Saved configuration: '$PackageDatabase'"
        }
    } else {
        Write-Output "Nothing to merge to: '$PackageDatabase'"
    }
}
