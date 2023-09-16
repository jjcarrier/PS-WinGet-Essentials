#Requires -Modules TableUI
Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"
[string]$PackageDatabaseSchema = "$PSScriptRoot\schema\packages.schema.json"
[string]$CheckpointFilePath = "$PSScriptRoot\winget.{HOSTNAME}.checkpoint"

<#
.DESCRIPTION
    Restore a collection of packages based on the provided list of tags.

.EXAMPLE
    PS> Restore-WinGetSoftware -All -UseUI

.EXAMPLE
    PS> Restore-WinGetSoftware -Tag Dev,Essential
#>
function Restore-WinGetSoftware
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Filter', ConfirmImpact = 'High')]
    param (
        # The specified tags to filter and determine which software to install.
        # A matching package is one that contains all the specified tags.
        # See $MatchAny to change the filtering behavior for this parameter.
        [Parameter(Mandatory = $true, ParameterSetName = 'Filter')]
        [string[]]$Tag,

        # When set, the specified list of $Tag will no longer require a package
        # to contain all the specified tags for it to be considered a match,
        # as long as one of the tags is associated with the package it will be
        # considered a match. The default behavior is to "Match All" tags.
        # This switch does not affect $ExcludeTag behavior.
        [Parameter(ParameterSetName = 'Filter')]
        [switch]$MatchAny,

        # An optional list of tags which will filter a package from the
        # install list if it contains ANY of tags specified in this list.
        [Parameter()]
        [string[]]$ExcludeTag = @(),

        # When set, all packages in "winget.packages.json" will be selected.
        [Parameter(Mandatory, ParameterSetName = 'NoFilter')]
        [switch]$All,

        # When set, packages listed in the "checkpoint" file (generated via
        # Checkpoint-WinGetSoftware) will be filtered from the list. Thus
        # supplying a list of packages that are not installed on the system.
        [Parameter()]
        [switch]$NotInstalled,

        # When set, a CLI based UI will be presented to allow for more refined
        # selection of packages to install.
        [Parameter()]
        [switch]$UseUI,

        # When set, indicates that interactive installation should be used,
        # requires user to navigate install wizards.
        [Parameter()]
        [switch]$Interactive,

        # Acts as a inverse of -Confirm. Provided for convenience.
        [Parameter()]
        [switch]$Force,

        # Launches and runs the invoked command in an administrator instance of PowerShell.
        [Parameter()]
        [switch]$Administrator
    )

    function Write-ProgressHelper
    {
        param (
            [PSObject[]]$Packages,
            [int]$PackageIndex
        )

        $i = $PackageIndex + 1
        Write-Output "`r▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"
        Write-Output "[ $i / $($Packages.Count) ] Installing '$($Packages[$PackageIndex].PackageIdentifier)'"
        Write-Output "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬`n"
    }

    if ($Administrator -and -not(Test-Administrator)) {
        $boundParamsString = $PSBoundParameters.Keys | ForEach-Object {
            if ($PSBoundParameters[$_] -is [switch]) {
                if ($PSBoundParameters[$_]) {
                    "-$($_)"
                }
            } else {
                "-$($_) $($PSBoundParameters[$_])"
            }
        }
        $cmdArgs = "-NoLogo -NoExit -Command Restore-WinGetSoftware $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList $cmdArgs
        return
    }

    if (-not(Test-Administrator) -and -not($Force)) {
        Write-Warning ('Some programs will not install correctly if WinGet is used without administrator rights. ' +
            'This is particularly true for zip-based installs which involve the creation of symbolic links to export the utility the WinGet "Links" path.')
        Write-Host 'Press any key to continue ...'
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }

    if ($Force -and -not $Confirm){
        $ConfirmPreference = 'None'
    }

    Initialize-WinGetRestore | Out-Null
    if (-not(Test-Path $PackageDatabase)) {
        Write-Error ("`"$PackageDatabase`" does not exist. Please create this file and populate it with tagged winget package identifiers. " +
            "Then use Initialize-WinGetRestore to setup a symlink to this file.")
        return
    }

    $MatchAnyScriptBlock = {
        param([string[]]$p1, [string[]]$p2)

        $tags = $p1
        $packageTags = $p2
        $matchedAny = $false
        $tags | ForEach-Object {
            if ($packageTags -contains $_) {
                $matchedAny = $true
                return
            }
        }

        $matchedAny
    }

    $MatchAllScriptBlock = {
        param([string[]]$p1, [string[]]$p2)

        $tags = $p1
        $packageTags = $p2
        $matchedAll = $true
        $tags | ForEach-Object {
            if ($packageTags -notcontains $_) {
                $matchedAll = $false
                return
            }
        }

        $matchedAll
    }

    $MatchNoneScriptBlock = {
        param([string[]]$p1, [string[]]$p2)

        $tags = $p1
        $packageTags = $p2
        $matchedNone = $true
        $tags | ForEach-Object {
            if ($packageTags -contains $_) {
                $matchedNone = $false
                return
            }
        }

        $matchedNone
    }

    if ($MatchAny) {
        $isMatch = $MatchAnyScriptBlock
    } else {
        $isMatch = $MatchAllScriptBlock
    }

    if (-not(Test-Json -Json ([string](Get-Content $PackageDatabase)) -SchemaFile $PackageDatabaseSchema)) {
        Write-Error "Schema validation failed for: '$PackageDatabase'. Please fix and try again. The file can be validated against '$PackageDatabaseSchema'."
        return
    }

    $installPackages = Get-Content $PackageDatabase | ConvertFrom-Json

    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
    if ($NotInstalled) {
        if (Test-Path $checkpointFile) {
            # Check across all sources for packages, not just winget.
            $checkpointPackageIds = (Get-Content $checkpointFile | ConvertFrom-Json).Sources.Packages.PackageIdentifier

            $installPackages = $installPackages | Where-Object {
                $checkpointPackageIds -notcontains $_.PackageIdentifier
            }
        } else {
            Write-Error "No checkpoint file found. 'Checkpoint-WinGetSoftware' should be run before using -NotInstalled."
            return
        }
    }

    if (-not($All)) {
        $installPackages  = $installPackages | Where-Object {
            &$isMatch -p1 $Tag -p2 $_.Tags
        }
    }

    if ($ExcludeTag.Count -gt 0) {
        $installPackages  = $installPackages | Where-Object {
            &$MatchNoneScriptBlock -p1 $ExcludeTag -p2 $_.Tags
        }
    }

    if ($installPackages.Count -eq 0) {
        Write-Output "No packages to install."
        return
    }

    $installPackages = $installPackages | Sort-Object -Property PackageIdentifier

    if ($UseUI) {
        $selections = [bool[]]@()

        $ShowPackageDetailsScriptBlock = {
            param($currentSelections, $selectedIndex)
            $command = "winget show $($installPackages[$selectedIndex].PackageIdentifier)"
            Clear-Host
            Invoke-Expression $command
            Write-Output "`n[Press ENTER to return.]"
            [Console]::CursorVisible = $false
            $cursorPos = $host.UI.RawUI.CursorPosition
            while ($host.ui.RawUI.ReadKey().VirtualKeyCode -ne [ConsoleKey]::Enter) {
                $host.UI.RawUI.CursorPosition = $cursorPos
                [Console]::CursorVisible = $false
            }
        }

        $TableUIArgs = @{
            Table = $installPackages
            Title = 'Select Software to Install'
            EnterKeyDescription = "Press ENTER to show selection details.                      "
            EnterKeyScript = $ShowPackageDetailsScriptBlock
            DefaultMemberToShow = "PackageIdentifier"
            SelectedItemMembersToShow = @("PackageIdentifier","Tags")
            Selections = ([ref]$selections)
        }

        Show-TableUI @TableUIArgs

        if ($null -eq $selections) {
            $selectedPackages = @();
        } else {
            $selectedPackages = @($installPackages | Where-Object { $selections[$installPackages.indexOf($_)] })
        }
    } else {
        $selectedPackages = $installPackages
    }

    if ($selectedPackages.Count -eq 0) {
        Write-Output "No packages selected."
        return
    }

    $packageIndex = 0
    $errorCount = 0

    foreach ($installPackage in $selectedPackages)
    {
        Write-ProgressHelper -Packages $selectedPackages -PackageIndex $packageIndex

        if ($PSCmdlet.ShouldProcess($installPackage.PackageIdentifier)) {
            Install-WinGetSoftware -Package $installPackage -ErrorCount ([ref]$errorCount)
        } else {
            Write-Output "Skipped."
        }

        $packageIndex++
    }

    if ($errorCount -gt 0) {
        throw "Done (Errors = $errorCount)."
    } else {
        Write-Output "Done."
    }
}

function Install-WinGetSoftware
{
    param(
        [object]$Package,
        [ref]$ErrorCount
    )

    $postInstallQuestion = "Run post-install command(s)?"
    $postInstallChoices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Do run post-install command")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Do not run post-install command")
    )

    $runPostInstall = ($Package.PSobject.Properties.Name -contains "PostInstall")

    if ($Interactive) {
        winget install --id $Package.PackageIdentifier --interactive
    } else {
        winget install --id $Package.PackageIdentifier
    }

    $installOk = $?

    if (-not($runPostInstall)) { continue }

    if ($installOk) {
        if ($Package.PostInstall.Run -eq "Prompt") {
            $decision = $Host.UI.PromptForChoice($null, $postInstallQuestion, $postInstallChoices, 0)
            $runPostInstall = $runPostInstall -and ($decision -eq 0)
        } else {
            $runPostInstall = $runPostInstall -and (
                ($Package.PostInstall.Run -eq "Always") -or
                ($Package.PostInstall.Run -eq "OnSuccess"))
        }
    } else {
        if (($Package.PostInstall.Run -eq "Prompt") -or
            ($Package.PostInstall.Run -eq "PromptOnError")) {
            $decision = $Host.UI.PromptForChoice($null, $postInstallQuestion, $postInstallChoices, 1)
            $runPostInstall = $runPostInstall -and ($decision -eq 0)
        } else {
            $runPostInstall = $runPostInstall -and ($Package.PostInstall.Run -eq "Always")
            $ErrorCount.Value++
        }
    }

    if (-not($runPostInstall)) { continue }

    foreach ($cmd in $Package.PostInstall.Commands) {
        $runCommand = $true
        while ($runCommand) {
            $runCommand = $false
            Write-Output "Executing: '$cmd'"
            $errorReult = $false
            try {
                $global:LASTEXITCODE = 0
                Invoke-Expression $cmd -ErrorVariable errorOutput
                $errorReult = ($LASTEXITCODE -ne 0) -or -not($?) -or -not([string]::IsNullOrEmpty($errorOutput))
            } catch {
                Write-Output "Last command encountered an error: $_"
                $errorReult = $true
            }

            if ($errorReult) {
                $ErrorCount.Value++
                if ($Package.PostInstall.OnError -eq "Skip") {
                    break
                } elseif ($Package.PostInstall.OnError -eq "Prompt") {
                    $title = "An error occurred during the last post-install command"
                    $question = "What action should be performed?"
                    $choices = @(
                        [System.Management.Automation.Host.ChoiceDescription]::new("&Continue", "Continue with the next command")
                        [System.Management.Automation.Host.ChoiceDescription]::new("&Re-Run", "Re-run the last command")
                        [System.Management.Automation.Host.ChoiceDescription]::new("&Skip", "Skip the remaining commands for the current package")
                    )

                    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 2)
                    $runCommand = $decision -eq 1
                    if ($decision -eq 2) { return }
                } else {
                    # "Continue", do nothing.
                }
            }
        }
    }
}

$RestoreTagScriptBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if (Test-Path $PackageDatabase) {
        $packages = Get-Content $PackageDatabase | ConvertFrom-Json
        if ($null -ne $packages) {
            $packages.Tags | Sort-Object -Unique | Where-Object { $_ -like "$wordToComplete*" }
        }
    }
}

Register-ArgumentCompleter -CommandName Restore-WingetSoftware -ParameterName Tag -ScriptBlock $RestoreTagScriptBlock
Register-ArgumentCompleter -CommandName Restore-WingetSoftware -ParameterName ExcludeTag -ScriptBlock $RestoreTagScriptBlock
