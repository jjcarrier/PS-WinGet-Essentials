#Requires -Modules TableUI
$PackageDatabase = "$PSScriptRoot\winget.packages.json"

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
        [string[]]$ExcludeTag,

        # When set, all packages in "winget.packages.json" will be selected.
        [Parameter(Mandatory, ParameterSetName = 'NoFilter')]
        [switch]$All,

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

    function Test-Administrator
    {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent();
        (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }

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

    if (-not(Test-Administrator)) {
        Write-Warning "Some programs will not install correctly if winget is used without administrator rights. This is particularly true for zip-based installs."
    }

    if ($Force -and -not $Confirm){
        $ConfirmPreference = 'None'
    }

    if (-not(Test-Path $PackageDatabase)) {
        Write-Error "`"$PackageDatabase`" does not exist. Please create this file and populate it with tagged winget package identifiers."
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

    $installPackages = Get-Content $PackageDatabase | ConvertFrom-Json

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
            $selectedPackages = $installPackages | Where-Object { $selections[$installPackages.indexOf($_)] }
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
            if ($Interactive) {
                winget install --id $installPackage.PackageIdentifier --interactive
            } else {
                winget install --id $installPackage.PackageIdentifier
            }

            if ($?)
            {
                $errorCount++
            }
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
