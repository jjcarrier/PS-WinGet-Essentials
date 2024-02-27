#Requires -Modules TextTable, TableUI
Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

# Used for specifing the default choice when prompting the user.
[int]$DefaultChoiceContinue = 0

[string]$DefaultSource = 'winget'
[string]$CacheFilePath = "$PSScriptRoot/winget.{HOSTNAME}.cache"

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
    Queries "winget upgrade", applies a filter according to ignore-file rule(s)
    and resolve output truncation.
.OUTPUTS
    An array of objects containing the available upgrades.
#>
function Get-WinGetSoftwareUpgrade
{
    param (
        # Detruncate any entries in the text-based results by performing additional queries.
        [switch]$Detruncate,

        # Use the ignore file to filter the available upgrades.
        [switch]$NoIgnore,

        # Clean the cache prior to fetching upgrades.
        [switch]$CleanCache
    )

    $consoleWidth = [console]::BufferWidth
    [console]::BufferWidth = [console]::LargestWindowWidth

    $commandArgs = @('upgrade')
    if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
        $commandArgs += @('--source', $DefaultSource)
    }

    # For better caching, strip any output before the header row of the upgrade table.
    $response = winget $commandArgs
    $startIndex = ($response | Select-String "^Name " | Select-Object -First 1).LineNumber - 1
    $response = $response[$startIndex .. ($response.Length - 1)]
    [console]::BufferWidth = $consoleWidth
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
        if ($CleanCache) {
            Remove-Item $cacheFile
        } else {
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

    if (-not($cached)) {
        $lastLineRegex = "\d+ upgrades available\."
        $splitIndex = ($response | Select-String $lastLineRegex).LineNumber
        $upgrades = $response | ConvertFrom-TextTable -LastLineRegEx $lastLineRegex
        $lastLineRegex = "\d+ package\(s\)"
        if ($splitIndex -le ($response.Count-1)) {
            $upgrades += $response[$splitIndex..($response.Count-1)] | ConvertFrom-TextTable -LastLineRegEx $lastLineRegex
        }

        if (-not($NoIgnore)) {
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
            Write-Verbose "Resolving $($_.Id) ($($_.Name)) ..."
            $commandArgs = @('search', '--id', "$($_.Id.Replace('…',''))")
            if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
                $commandArgs += @('--source', $DefaultSource)
            }

            $tmp = @(winget $commandArgs | ConvertFrom-TextTable)
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
    Attempts to upgrade to the latest version of WinGet-Essentials via the
    PSGallery. The various configuration files required by the WinGet-Essentials
    cmdlets will be migrated/moved from prior installations, or an error output
    will be emitted stating that such a resouce is missing and is needed to
    function.
#>
function Update-WinGetEssentials
{
    param(
        <#
        When set, the cmdlet will automatically relaunch using an Administrator
        PowerShell instance. This cmdlet requires aministrator privileges
        to create Symbolic Links.
        #>
        [switch]$Administrator,

        # Perform all update operations even if no new version was detected.
        [switch]$Force
    )

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
        $cmdArgs = "-NoLogo -NoExit -Command Update-WinGetEssentials $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath 'pwsh' -ArgumentList $cmdArgs
        return
    }

    if (-not(Test-CreateSymlink)) {
        $label = 'Microsoft Article'
        $url = 'https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/create-symbolic-links'
        Write-Error "The current user does not have the required privileges to create symbolic links. See $(New-HyperLinkText -Label $label -Url $url)."
        return
    }

    Write-Output 'Upgrading module from PSGallery ...'
    $current = @(Get-Module WinGet-Essentials -ListAvailable)[0]
    Write-Output "- Current Version: $($current.Version)"
    Remove-Module -Name WinGet-Essentials
    Update-Module -Name WinGet-Essentials
    $newest = @(Get-Module WinGet-Essentials -ListAvailable)[0]
    Write-Output "- Updated Version: $($newest.Version)"
    Import-Module WinGet-Essentials -RequiredVersion $newest.Version

    if (-not($Force) -and ($current.Version -eq $newest.Version)) {
        Write-Output "No new version detected."
        return
    }

    Write-Output 'Migrating ignore file (if available) ...'
    Initialize-WinGetIgnore
    Write-Output 'Migrating "winget.packages.json" (if available) ...'
    Initialize-WinGetRestore

    Write-Output 'Creating a checkpoint ...'
    $jobName = Start-Job -ScriptBlock { Checkpoint-WingetSoftware | Out-Null }
    Show-JobProgress $jobName

    Write-Output 'Syncing upgrade packages ...'
    $jobName = Start-Job -ScriptBlock { Update-WinGetSoftware -Sync | Out-Null }
    Show-JobProgress $jobName
    Write-Output 'Done.'
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
        # to the next. NOTE: This overrides -WhatIf and -Confirm; however, it
        # does not disable the -Interactive switch.
        [switch]$Force
    )

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
            [ref]$ErrorCount
        )

        $result = $LASTEXITCODE -eq 0

        if (-not($result)) {
            $ErrorCount.Value++
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
            [switch]$Force,

            # The decision (index) made by the user.
            [ref]$Action,

            # Command details that will be output to warning log.
            [string]$CmdDetails
        )

        Write-Output ""
        $url = "https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md"
        $label = "More Info"
        if ([string]::IsNullOrWhiteSpace($CmdDetails)) {
            Write-Warning "An error (code: $("0x{0:X08}" -f $Code)) occurred while executing the last step."
        } else {
            Write-Warning "An error (code: $("0x{0:X08}" -f $Code)) occurred while executing:"
            Write-Warning $CmdDetails
        }
        Write-Warning "Additional details here: $(New-HyperLinkText -Url $url -Label $label)"

        if ($Force) {
            return
        }

        $abortIndex = 2
        $title = $null # not used
        $question = "What action should be performed?"
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new("&Continue", "Continue installing other software (if available).")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Retry", "Retry installation of the current software package.")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Abort", "Stop and exit installation process.")
        )

        $Action.Value = $Host.UI.PromptForChoice($title, $question, $choices, $DefaultChoiceContinue)

        if ($Action.Value -eq $abortIndex) {
            throw "Aborted (Errors = $ErrorCount)."
        }

        Write-Output ""
    }

    <#
    .DESCRIPTION
        Get the caches item for the specified package identifier.
    #>
    function Get-ItemFromCache
    {
        param(
            # Package Identifier to get the cache entry.
            [string]$Id
        )

        $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

        if (-not(Test-Path $cacheFile)) {
            return $null
        }

        $cache = Get-Content $cacheFile | ConvertFrom-Json
        $cachedItem = $cache.upgrades | Where-Object {
            $_.Id -eq $Id
        }

        return $cachedItem
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
        Returns the arguments to be used for performing an update via WinGet.
    #>
    function Get-WinGetSoftwareUpgradeArgs
    {
        param (
            # The item containing the package to update along with its metadata.
            [PSCustomObject]$Item,

            # Provide user-interactive installation for the specified package.
            [switch]$Interactive
        )

        $commandArgs = @('upgrade', '--id', $Item.Id, '--version', $Item.Available)
        if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
            $commandArgs += @('--source', $DefaultSource)
        }
        if ($Interactive) {
            $commandArgs += '--interactive'
        }

        return $commandArgs
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
        $done = $false

        while (-not($done)) {
            Write-Verbose "Updating '$($Item.Id)' ..."
            $commandArgs = Get-WinGetSoftwareUpgradeArgs -Item $Item -Interactive:$Interactive
            winget $commandArgs

            $upgradeOk = $LASTEXITCODE -eq 0

            if (-not($upgradeOk) -and ($LASTEXITCODE -eq $UPDATE_NOT_APPLICABLE)) {
                # This is a best-effort workaround for an issue currently present in
                # winget where the listing reports an update, but it is not possible
                # to 'upgrade'. Instead, use the 'install' command. This is
                # typically due to a different installer used for the current
                # installation versus what is available on the winget source. In
                # this case, try with --uninstall-previous, but support for this is
                # not guaranteed. If this fails, the user likely needs to
                # "winget uninstall" and then "winget install". This could
                # potentially be handled here, but there may be issues with ensuring
                # the install state is maintained. For now it is best to force the
                # user to upgrade this package manually.
                $commandArgs[0] = 'install'
                $commandArgs += '--uninstall-previous'
                Write-Verbose "command: winget $commandArgs"
                winget $commandArgs
            }

            # TODO: Ignore exit code 3010 (seems to indicate "restart required")?
            if (Test-LastCommandResult -ErrorCount $ErrorCount -Force:$Force) {
                $done = $true
                Write-Verbose "Updated '$($Item.Id)'"
                Write-Verbose "`tOld Version: [$($Item.Version)]"
                Write-Verbose "`tNew Version: [$($Item.Available)]"
                Write-Output ""
                $Success.Value = $true
            } else {
                $action = 0
                Request-ContinueOnError -Code $LastExitCode -ErrorCount $ErrorCount.Value -Force:$Force -Action ([ref]$action) -CmdArgs @('winget', $commandArgs)
                $done = $action -eq $DefaultChoiceContinue # The 'Abort' action is handled by Request-ContinueOnError
                $Success.Value = $false
            }
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
        $bar = ('─' * $Host.UI.RawUI.WindowSize.Width) # Match current console width
        Write-Output "`n$bar"
        Write-Output "[ $i / $($UpgradeTable.Count) ] Upgrading '$($UpgradeTable[$UpgradeIndex].Name)'"
        Write-Output "$bar`n"
    }

    [int]$errorCount = 0

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

    $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (-not([string]::IsNullOrWhiteSpace($Id))) {
        $upgradeTable = @()
        $Id | ForEach-Object {
            $upgradeItem = Get-ItemFromCache -Id $_
            if ($null -eq $upgradeItem) {
                Write-Warning "`"$_`" was not found in cache and will not be upgraded."
            } else {
                $upgradeTable += $upgradeItem
            }
        }

        $ConfirmPreference = 'None'
        $upgradeIndex = 0
        $upgradeTable | ForEach-Object {
            Write-ProgressHelper -UpgradeTable $upgradeTable -UpgradeIndex $upgradeIndex
            $upgradeIndex++
            Write-Verbose "command: winget $(Get-WinGetSoftwareUpgradeArgs -Item $_ -Interactive:$Interactive)"
            if ($Force -or $PSCmdlet.ShouldProcess($_.Id)) {
                $upgraded = $false
                Update-Software -Item $_ -Interactive:$Interactive -Success ([ref]$upgraded) -ErrorCount ([ref]$errorCount) -Force:$Force
                if ($upgraded) {
                    Remove-UpgradeItemFromCache -Item $_
                }
            }
        }
        return
    }

    Write-Output "Getting winget upgrades ..."

    $upgradeTable = @()
    if ($Sync) {
        $jobName = Start-Job -ScriptBlock {
            $commandArgs = @('source', 'update')
            if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
                $commandArgs += @('--name', $DefaultSource)
            }
            winget $commandArgs
            Get-WinGetSoftwareUpgrade -UseIgnores -Detruncate
        }

        Show-JobProgress $jobName
        $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
        $upgradeTable = (Get-Content $cacheFile | ConvertFrom-Json).upgrades

        if ($upgradeTable.Count -gt 0) {
            Write-Output "`nAvailable Upgrades:"
            $upgradeTable | Format-Table
        }
        return
    }
    else {
        $jobName = Start-Job -ScriptBlock {
            Get-WinGetSoftwareUpgrade -UseIgnores -Detruncate
        }

        Show-JobProgress $jobName
        $cacheFile = $CacheFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
        $upgradeTable = (Get-Content $cacheFile | ConvertFrom-Json).upgrades
    }

    if ($upgradeTable.Count -eq 0) {
        Write-Output "No packages to be updated ..."
        $selections =@()
        # Do nothing
    } elseif ($All) {
        # Upgrade all packages
        $selections = $upgradeTable | ForEach-Object { $true }
        $upgradeTable = $upgradeTable | Sort-Object -Property Name
    } else {
        # Ask user to select packages to install
        $upgradeTable = $upgradeTable | Sort-Object -Property Name
        $selections = $upgradeTable | ForEach-Object { $false }

        $showPackageDetailsScriptBlock = {
            param($currentSelections, $selectedIndex)
            $commandArgs = @('show', $upgradeTable[$selectedIndex].Id)
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
            Table = $upgradeTable
            Selections = ([ref]$selections)
            Title = 'Select Software to Update'
            DefaultMemberToShow = @('Name','Available','Version')
            SelectedItemMembersToShow = @('Name','Id','Version','Available')
            EnterKeyDescription = 'Press ENTER to show selection details.'
            EnterKeyScript = $showPackageDetailsScriptBlock
        }

        Enter-AltScreenBuffer
        Hide-TerminalCursor
        Show-TableUI @TableUIArgs
        Exit-AltScreenBuffer
    }

    Write-Output "Upgrades available: $($upgradeTable.Count)"
    if ($null -eq $selections) {
        $upgradeTable = @()
    } else {
        $upgradeTable = @($upgradeTable | Where-Object { $selections[$upgradeTable.indexOf($_)] })
    }

    Write-Output "Upgrades selected: $($upgradeTable.Count)"
    if ($upgradeTable.Count -ne 0) {
        $upgradeIndex = 0
        $upgradeTable | ForEach-Object { Write-Output "- $($_.Id) ($($_.Name))" }

        foreach ($upgradeItem in $upgradeTable) {
            Write-ProgressHelper -UpgradeTable $upgradeTable -UpgradeIndex $upgradeIndex

            if (($upgradeItem.Version -eq 'Unknown') -and -not($UpgradeUnknown)) {
                Write-Warning "'$($upgradeItem.Id)': Unknown version installed. Install manually or specify '-UpgradeUnknown' to bypass this check."
                continue
            }

            Write-Verbose "command: winget $(Get-WinGetSoftwareUpgradeArgs -Item $upgradeItem -Interactive:$Interactive)"
            if ($Force -or $PSCmdlet.ShouldProcess($upgradeItem.Id)) {
                $upgraded = $false
                Update-Software $upgradeItem -Interactive:$Interactive -Success ([ref]$upgraded) -ErrorCount ([ref]$errorCount) -Force:$Force
                if ($upgraded) {
                    Remove-UpgradeItemFromCache -Item $upgradeItem
                }
            }

            $upgradeIndex++
        }
    }

    if ($errorCount -gt 0) {
        Write-Error "Done (Errors = $errorCount)."
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
            $commandLine = $commandAst.Extent.Text | Select-String -Pattern "\s+\-$parameterName\s+"
            if (($null -ne $commandLine) -and ($commandLine.Matches.Count -gt 0)) {
                $commandLine = $commandAst.Extent.Text.Split(($commandLine.Matches | Select-Object -Last 1).Value) | Select-Object -Last 1
            } else {
                $commandLine = $commandAst.Extent.Text.Split(" ") | Select-Object -Skip 1
            }

            # Extract the values that have been entered so far
            if ($null -ne $commandLine) {
                $enteredUpgrades = $commandLine.Split(",") | ForEach-Object { $_.Trim('"').Trim("'") }
            } else {
                $enteredUpgrades = @()
            }

            # Filter out the values that have already been entered
            $completionUpgrades = $upgrades | Where-Object { $_.Id -notin $enteredUpgrades }

            $completionUpgrades | Where-Object { $_.Id -like "$wordToComplete*" } | ForEach-Object {
                $toolTip = "$($_.Name) [$($_.Version) --> $($_.Available)]"
                [System.Management.Automation.CompletionResult]::new($_.Id, $_.Id, 'ParameterValue', $toolTip)
            }
        }
    }
}

Register-ArgumentCompleter -CommandName Update-WinGetSoftware -ParameterName Id -ScriptBlock $UpgradesScriptBlock
