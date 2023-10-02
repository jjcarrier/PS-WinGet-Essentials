#Requires -Modules TextTable, TableUI
Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

# Used for specifing the default choice when prompting the user.
[int]$DefaultChoiceYes = 0
[int]$DefaultChoiceNo = 1

[string]$SourceFilter = "--source winget"
[string]$CacheFilePath = "$PSScriptRoot/winget.{HOSTNAME}.cache"

# List of all apps that are available in a known source
# winget list | ConvertFrom-TextTable | Where-Object { -not([string]::IsNullOrWhiteSpace($_.Source)) } | Format-Table

<#
.DESCRIPTION
    Computes a hash for an array of strings.
#>
function Get-ListHash
{
    param (
        # The array of strings to hash.
        [string[]]$ListData
    )

    $stringAsStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.StreamWriter]::new($stringAsStream)
    $ListData | ForEach-Object { $writer.write($_) }
    $writer.Flush()
    $stringAsStream.Position = 0
    return (Get-FileHash -InputStream $stringAsStream).Hash
}

<#
.DESCRIPTION
    Queries "winget upgrade".
.OUTPUTS
    An array of objects containing the available upgrades.
#>
function Get-WinGetSoftwareUpgrades
{
    param (
        [switch]$Detruncate,
        [switch]$UseIgnores,
        [switch]$CleanCache
    )

    $consoleWidth = [console]::WindowWidth
    [console]::WindowWidth = 512
    $command = "winget upgrade $SourceFilter"

    # NOTE: for better caching, this logic should sanitize the response. In some
    # cases winget will emit the progress bar which will prevent caching from
    # working when it should.
    $response = Invoke-Expression $command
    [console]::WindowWidth = $consoleWidth
    if ($NoIgnore) {
        $ignoredIds = @()
    } else {
        $ignoredIds = Get-WinGetSoftwareIgnores
    }
    $cacheHash = Get-ListHash -ListData ($response + $ignoredIds)
    $cached = $false

    $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (Test-Path $cacheFile)
    {
        if ($CleanCache)
        {
            Remove-Item $cacheFile
        }
        else
        {
            Write-Verbose "Getting upgrade cache ..."
            $cache = Get-Content $cacheFile | ConvertFrom-Json

            # Compare the hash against the cached hash to determine if the cached upgrade
            # data can be used or if the list needs to be reprocessed.
            if ($cacheHash -eq $cache.hash)
            {
                Write-Verbose "Loaded upgrade cache ..."
                Write-Verbose "Cached Items: $($cache.upgrades.Count)"
                $upgrades = $cache.upgrades
                $cached = $true
            }
        }
    }

    if (-not($cached))
    {
        $lastLineRegex = "\d+ upgrades available\."
        $splitIndex = ($response | Select-String $lastLineRegex).LineNumber
        $upgrades = $response | ConvertFrom-TextTable -LastLineRegEx $lastLineRegex
        $lastLineRegex = "\d+ package\(s\)"
        $upgrades += $response[$splitIndex..($response.Count-1)] | ConvertFrom-TextTable -LastLineRegEx $lastLineRegex

        if ($UseIgnores) {
            $upgrades = $upgrades | Where-Object {
                if ($_.Id.EndsWith('…')) {
                    # Determine if it is necessary to resolve a truncated ID,
                    # to determine if it should be ignored.
                    $pattern = $_.Id.Replace('…','*').Replace('.','\.')
                    $patternMatches = @($ignoredIds | Select-String $pattern).Count
                    if ($patternMatches -ne 0) {
                        $_ | Resolve-WinGetSoftwareUpgrade
                    }
                }

                -not($ignoredIds -contains $_.Id)
            }
        }
    }

    if ($Detruncate) {
        $upgrades | Resolve-WinGetSoftwareUpgrade
    }

    $cache = [PSCustomObject]@{
        hash = $cacheHash
        upgrades = $upgrades
    }
    $cache | ConvertTo-Json | Set-Content $cacheFile

    $upgrades
}

<#
.DESCRIPTION
    Resolves truncated upgrade entries. This will modify the existing
    PSCustomObject(s).
#>
function Resolve-WinGetSoftwareUpgrade
{
    process
    {
        if ($_.Name -like "*…" -or $_.Id -like "*…") {
            $tmp = @(winget search --Id "$($_.Id.Replace('…',''))" | ConvertFrom-TextTable)
            if ($tmp.Count -ne 1) {
                Write-Warning "Multiple entries for $($_.Id) returned. First entry selected."
            }
            $_.Id = $tmp[0].Id
            $_.Name = $tmp[0].Name
        }
    }
}

<#
.DESCRIPTION
    Provides an interactive WinGet UI for selectively installing updates.

.EXAMPLE
    PS> Update-WingetSoftware

.EXAMPLE
    PS> Update-WingetSoftware <WinGetPackageID>[,<AnotherWinGetPackageID>]

.EXAMPLE
    PS> Update-WingetSoftware -Sync
#>
function Update-WinGetSoftware
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', PositionalBinding)]
    param (
        # The ID or list of IDs for software package(s) to update.
        [string[]]$Id,

        # No upgrade is performed, simply requests latest upgrade info.
        [switch]$Sync,

        # Interactively install software using install wizard.
        [switch]$Interactive,

        # Upgrade all software reported as having newer versions available which have
        # known installed versions reported.
        [switch]$All,

        # Include installing software which has no known version installed.
        [switch]$UpgradeUnknown,

        # Clean the cache
        [switch]$CleanCache,

        # Indicates to run the command in an Administror PowerShell instance.
        [switch]$Administrator,

        # Bypasses the ignore file.
        [switch]$NoIgnore,

        # Bypasses prompts. If a prior upgrade fails, the process will continue
        # to the next. NOTE: This overrides -WhatIf however it does not disable
        # the -Interactive switch.
        [switch]$Force
    )

    <#
    .DESCRIPTION
        Increases indentation level for Write-OutputIndented.
    #>
    function Add-Indentation
    {
        param(
            # The current indentation level which will be incremented.
            [ref]$IndentLevel
        )

        $IndentLevel.Value++
    }

    <#
    .DESCRIPTION
        Decreases indentation level for Write-OutputIndented.
    #>
    function Remove-Indentation
    {
        param(
            # The current indentation level which will be decremented.
            [ref]$IndentLevel
        )

        if ($IndentLevel -gt 0)
        {
            $IndentLevel.Value--
        }
    }

    <#
    .DESCRIPTION
        Write a message to console with indentation.
    #>
    function Write-OutputIndented
    {
        param (
            # The level of indentation to apply.
            [int]$IndentLevel,

            # The message to display.
            [string]$Message
        )

        Write-Output "$(([string]"`t") * $IndentLevel)$Message"
    }

    <#
    .DESCRIPTION
        Check the result of the last shell command. On error, increment an error counter
        and then prompt the user if execution of the script should continue.
    .OUTPUTS
        True if last command was successful; otherwise false.
    #>
    function Test-LastCommandResult
    {
        param(
            # The current error count, on error, this value will be incremented.
            [ref]$ErrorCount,

            # The force state as specified by the user. When set, it will bypass,
            # prompts and continue on with execution.
            [switch]$Force
        )

        $result = $? -eq $true

        if (-not($result))
        {
            $ErrorCount.Value++
            Request-ContinueOnError -Code $result -ErrorCount $ErrorCount.Value -Force:$Force
        }

        return $result
    }

    <#
    .DESCRIPTION
        Reports to the user that an error occurred and prompts the user if the script
        should continue. If the user answers 'No' the script will exit immediately.
    #>
    function Request-ContinueOnError
    {
        param(
            # The error code.
            [int]$Code,

            # The current error count.
            [int]$ErrorCount,

            # The force state as specified by the user. When set, it will bypass,
            # prompts and continue on with execution.
            [switch]$Force
        )

        Write-Output ""
        Write-Warning "An error (code: $Code) occurred while executing the last step."

        if (-not($Force) -and -not(Request-YesOrNo "Do you want to continue?" $DefaultChoiceYes))
        {
            throw "Aborted (Errors = $ErrorCount)."
        }

        Write-Output ""
    }

    <#
    .DESCRIPTION
        Create and show a 'Yes' or 'No' prompt to the user and return the user's response.
    .OUTPUTS
        [bool] The user's decision.
    #>
    function Request-YesOrNo
    {
        param (
            # The Yes-No question to ask the user.
            [string]$Question,

            # The index of the default choice (-1=None, 0=Yes, 1=No).
            [int]$DefaultChoiceIndex
        )

        $choices  = '&Yes', '&No'
        $decision = Request-Choice $Question $choices $DefaultChoiceIndex
        return ($decision -eq $DefaultChoiceYes)
    }

    <#
    .DESCRIPTION
        Create and show a prompt with multiple choices and return the user's response.
    .OUTPUTS
        [int] The user's decision.
    #>
    function Request-Choice
    {
        param (
            # The question to ask the user.
            [string]$Question,

            # The available choices.
            [string[]]$Choices,

            # The index of the default choice (-1=None, Other values relate to provided choices).
            [int]$DefaultChoiceIndex
        )

        $title = $null # not used
        $decision = $Host.UI.PromptForChoice($title, $Question, $Choices, $DefaultChoiceIndex)
        return $decision
    }

    <#
    .DESCRIPTION
        Removes and item from the upgrade cache.
    #>
    function Remove-UpgradeItemFromCache
    {
        param (
            # The upgrade item to remove from cache.
            [PSCustomObject]$Item
        )

        $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

        if (-not(Test-Path $cacheFile)) {
            return
        }

        $cache = Get-Content $cacheFile | ConvertFrom-Json
        $upgrades = $cache.upgrades | Where-Object {
            $_.Id -ne $Item.Id
        }

        # Note: currently the hash depends only on the ignore file and winget's
        # raw response data for the upgrade list, so there is no need to
        # recompute the hash for this operation. However, because there are
        # several complications with detecting whether an update completed
        # successfully, it makes sense to simply invalidate the hash to
        # force a refresh after the user updated packages.
        $cache = [PSCustomObject]@{
            hash = "0"
            upgrades = $upgrades
        }
        $cache | ConvertTo-Json | Set-Content $cacheFile
    }

    <#
    .DESCRIPTION
        Updates the specified package.
    #>
    function Update-Software
    {
        param (
            # The item containing the package to update along with its metadata.
            [PSCustomObject]$Item,

            # Provide user-interactive installation for the specified package.
            [switch]$Interactive,

            # Set true when software installed successfully (note, some packages
            # will not report success for various reasons even when the
            # software did not encounter an error during the update. One example
            # of this is when a package requires a reboot to complete.
            [ref]$Success,

            # The error count, tracks the number of errors encountered through
            # the update process.
            [ref]$ErrorCount,

            # The force state as specified by the user. When set, it will bypass,
            # prompts and continue on with execution.
            [switch]$Force
        )

        # From https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h
        $UPDATE_NOT_APPLICABLE = 0x8A15002B

        Write-Output "Updating '$($Item.Id)'..."

        if ($Interactive) {
            $InteractiveArg = " --interactive"
        } else {
            $InteractiveArg = ""
        }

        winget upgrade --id $Item.Id$InteractiveArg

        if (-not($?) -and ($LastExitCode -eq $UPDATE_NOT_APPLICABLE)) {
            # This is a workaround for an issue currently present in winget where
            # the listing reports an update, but it is not possible to 'upgrade'.
            # Instead, use the 'install' command. This issue might be caused by
            # different install wizard on the local system versus what is
            # present on the winget source.
            winget install --id $Item.Id$InteractiveArg
        }

        # TODO: Ignore exit code 3010 (seems to indicate "restart required")?
        if (Test-LastCommandResult -ErrorCount $ErrorCount -Force:$Force) {
            Write-Output "`nUpdated '$($Item.Id)'"
            Write-Verbose "`tOld Version: [$($Item.Version)]"
            Write-Verbose "`tNew Version: [$($Item.Available)]"
            Write-Output ""
            $Success.Value = $true
        } else {
            $Success.Value = $false
        }
    }

    <#
    .DESCRIPTION
        Renders output to convey progress.
    #>
    function Write-ProgressHelper
    {
        param (
            [PSObject]$UpgradeTable,
            [int]$UpgradeIndex
        )

        $i = $UpgradeIndex + 1
        Write-Output "`r▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"
        Write-Output "[ $i / $($UpgradeTable.Count) ] Upgrading '$($UpgradeTable[$UpgradeIndex].Name)'"
        Write-Output "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬`n"
    }

    [int]$ErrorCount = 0
    [int]$IndentLevel = 0

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
        $cmdArgs = "-NoLogo -NoExit -Command Update-WingetSoftware $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList $cmdArgs
        return
    }

    Clear-Host
    [Console]::CursorVisible = $false
    $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (-not([string]::IsNullOrWhiteSpace($Id)))
    {
        $Id | ForEach-Object {
            winget upgrade $_
            if ($?) {
                $cache = Get-Content $cacheFile | ConvertFrom-Json
                $cache.upgrades = $cache.upgrades | Where-Object { $_.Id -ne $Id }
                $cache.hash = 0
                $cache | ConvertTo-Json | Set-Content $cacheFile
            }
        }
        return
    }

    Write-Output "Getting winget upgrades ..."
    if ($Sync)
    {
        winget source update
        $upgradeTable = Get-WinGetSoftwareUpgrades -UseIgnores -Detruncate
        if ($upgradeTable.Count -gt 0)
        {
            Write-Output "`nAvailable Upgrades:"
            $upgradeTable | Format-Table
        }
        return
    }
    else {
        $upgradeTable = Get-WinGetSoftwareUpgrades -UseIgnores -Detruncate
    }

    if ($upgradeTable.Count -eq 0)
    {
        Write-Output "No packages to be updated ..."
        $selections =@()
        # Do nothing
    }
    elseif ($All)
    {
        # Upgrade all packages
        $selections = $upgradeTable | ForEach-Object { $true }
        $upgradeTable = $upgradeTable | Sort-Object -Property Name

        Write-Output "Upgrading:"
        Add-Indentation -IndentLevel ([ref]$IndentLevel)
        $upgradeTable | ForEach-Object { Write-OutputIndented -IndentLevel $IndentLevel -Message "- $($_.Name)" }
        Remove-Indentation -IndentLevel ([ref]$IndentLevel)
    }
    else
    {
        # Ask user to select packages to install
        $upgradeTable = $upgradeTable | Sort-Object -Property Name
        $selections = $upgradeTable | ForEach-Object { $false }

        $ShowPackageDetailsScriptBlock = {
            param($currentSelections, $selectedIndex)
            $command = "winget show $($upgradeTable[$selectedIndex].Id)"
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
            Table = $upgradeTable
            Selections = ([ref]$selections)
            Title = 'Select Software to Update'
            DefaultMemberToShow = 'Name'
            SelectedItemMembersToShow = @('Name','Id','Version','Available')
            EnterKeyDescription = 'Press ENTER to show selection details.                      '
            EnterKeyScript = $ShowPackageDetailsScriptBlock
        }

        Show-TableUI @TableUIArgs
    }

    if (($upgradeTable.Count -gt 0) -and ($null -ne $selections))
    {
        $upgradeIndex = 0
        $upgradeTable = $upgradeTable | Where-Object { $selections[$upgradeTable.indexOf($_)] }

        foreach ($upgradeItem in $upgradeTable)
        {
            Write-ProgressHelper -UpgradeTable $upgradeTable -UpgradeIndex $upgradeIndex

            if (($upgradeItem.Version -eq 'Unknown') -and -not($UpgradeUnknown)) {
                Write-Warning "'$($upgradeItem.Id)': Unknown version installed. Install manually or specify '-UpgradeUnknown' to bypass this check."
                continue
            }

            if ($Force -or $PSCmdlet.ShouldProcess($upgradeItem.Id)) {
                $upgraded = $false
                Update-Software $upgradeItem -Interactive:$Interactive -Success ([ref]$upgraded) -ErrorCount ([ref]$ErrorCount) -Force:$Force
                if ($upgraded) {
                    Remove-UpgradeItemFromCache -Item $upgradeItem
                }
            }

            $upgradeIndex++
        }
    }

    if ($ErrorCount -gt 0) {
        Write-Error "Done (Errors = $ErrorCount)."
    } else {
        Write-Output 'Done.'
    }
}

$UpgradesScriptBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (Test-Path $cacheFile) {
        $upgrades = (Get-Content $cacheFile | ConvertFrom-Json).upgrades
        if ($null -ne $upgrades) {
            $upgrades | Where-Object { $_.Id -like "$wordToComplete*" } | ForEach-Object {
                $toolTip = "$($_.Name) [$($_.Version) --> $($_.Available)]"
                [System.Management.Automation.CompletionResult]::new($_.Id, $_.Id, 'ParameterValue', $toolTip)
            }
        }
    }
}

Register-ArgumentCompleter -CommandName Update-WinGetSoftware -ParameterName Id -ScriptBlock $UpgradesScriptBlock
