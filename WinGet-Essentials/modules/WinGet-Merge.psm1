Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

[string]$CheckpointFilePath = "$PSScriptRoot\winget.{HOSTNAME}.checkpoint"
[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"
[string]$DefaultSource = 'winget'

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
        # Each package will be prompted for tagging unless -NoTags is also set.
        [switch]$MergeAll,

        # Skip prompts for tagging new package IDs.
        [switch]$NoTags,

        # Skips performing a checkpoint.
        [switch]$NoCheckpoint,

        # When set, a CLI based UI will be presented to allow for more refined
        # selection of packages to merge into 'winget.packages.json'. This may
        # be paired with -MergeAll to skip the additional final prompt to merge
        # a package.
        [switch]$UseUI
    )

    if ($NoCheckpoint) {
        # Skip performing a checkpoint.
    } else {
        Checkpoint-WinGetSoftware
        Start-Sleep -Milliseconds 500
    }

    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
    if (-not(Test-Path $checkpointFile)) {
        Write-Error "No checkpoint file found."
        return
    }

    $installedPackages = Get-Content $checkpointFile | ConvertFrom-Json
    $installedPackages = @($installedPackages.Sources | Where-Object { $_.SourceDetails.Name -eq $DefaultSource }).Packages

    if (-not(Test-Path $PackageDatabase)) {
        Write-Error "A 'winget.packages.json' is required to use this cmdlet. Please see Initialize-WinGetRestore."
        return
    }

    $packages = @(Get-Content $PackageDatabase | ConvertFrom-Json)
    if ($packages.Count -eq 0) {
        $newPackages = $installedPackages
    } else {
        $newPackages = $installedPackages | Where-Object { $packages.PackageIdentifier -notcontains $_.PackageIdentifier }
    }

    if ($NoIgnore) {
        # Skip ignore package filtering.
    } else {
        $ignorePackages = Get-WinGetSoftwareIgnores
        $newPackages = $newPackages | Where-Object { $ignorePackages -notcontains $_.PackageIdentifier }
    }

    if ($null -eq $newPackages) {
        Write-Output "Nothing to merge to: '$PackageDatabase'"
        return
    }

    $newPackages = $newPackages | Sort-Object -Unique -Property PackageIdentifier

    if ($UseUI) {
        $selections = [bool[]]@()

        $showPackageDetailsScriptBlock = {
            param($currentSelections, $selectedIndex)
            $commandArgs = @('show', $newPackages[$selectedIndex].PackageIdentifier)
            if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
                $commandArgs += @('--source', $DefaultSource)
            }
            $consoleEncoding = [console]::OutputEncoding
            [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
            $details = winget $commandArgs --no-vt
            [console]::OutputEncoding = $consoleEncoding
            $firstLine = $details | Select-String -Pattern 'Found\s+(.*\[.*\])'
            if ($firstLine.Matches.Count -eq 1) {
                $details = $details[$firstLine.LineNumber..($details.Length - 1)]
                Show-Paginated -TextData $details -Title $firstLine.Matches[0].Groups[1].Value
                Hide-TerminalCursor
            }
        }

        $TableUIArgs = @{
            Table = $newPackages
            Title = 'Select Software to Merge'
            EnterKeyDescription = "Press ENTER to show selection details.                      "
            EnterKeyScript = $showPackageDetailsScriptBlock
            DefaultMemberToShow = "PackageIdentifier"
            SelectedItemMembersToShow = @("PackageIdentifier")
            Selections = ([ref]$selections)
        }

        Enter-AltScreenBuffer
        Hide-TerminalCursor
        Show-TableUI @TableUIArgs
        Exit-AltScreenBuffer

        if ($null -eq $selections) {
            $newPackages = @();
        } else {
            $newPackages = $newPackages | Where-Object { $selections[$newPackages.indexOf($_)] }
        }
    }

    $jsonModified = $false
    $newPackages | ForEach-Object {
        $id = $_.PackageIdentifier
        $merge = $true
        if (-not($MergeAll)) {
            $question = "Merge package '$id' into 'winget.packages.json'?"
            $choices = @(
                [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Do merge")
                [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Do not merge")
            )

            $decision = $Host.UI.PromptForChoice($null, $question, $choices, 1)
            $merge = $decision -eq 0
        }

        if ($merge) {
            $newEntry = [PSCustomObject]@{
                PackageIdentifier = [string]$id
                Tags = @()
            }

            if ($NoTags) {
                # Skip prompting user for tagging each new package.
            } else {
                Write-Output "Enter tags for package '$id'. An empty entry concludes data entry."
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
            Write-Output "Added package '$id'"
        } else {
            Write-Output "Skipped package: '$id'"
        }
    }

    if ($jsonModified) {
        $packages | Sort-Object -Property PackageIdentifier | ConvertTo-Json -Depth 3 | Out-File $PackageDatabase
        if ($?) {
            Write-Output "Saved configuration: '$PackageDatabase'"
        }
    } else {
        Write-Output "Nothing to merge to: '$PackageDatabase'"
    }
}
