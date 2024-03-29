#Requires -Modules TableUI
Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"
[string]$PackageDatabaseSchema = "$PSScriptRoot\schema\packages.schema.json"
[string]$CheckpointFilePath = "$PSScriptRoot\winget.{HOSTNAME}.checkpoint"
[string]$FakePackageExpression = "<.*>"
[string]$DefaultSource = 'winget'

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
        [Parameter(Mandatory, ParameterSetName = 'Filter')]
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

        # When set, ignore the 'Version' of all packages to be installed and use
        # the latest version available. However, packages with 'VersionLock' set
        # will be respected.
        [Parameter()]
        [switch]$UseLatest,

        # When set, indicates that interactive installation should be used,
        # requires user to navigate install wizards.
        [Parameter()]
        [switch]$Interactive,

        # Acts as an inverse of -Confirm. Provided for convenience.
        [Parameter()]
        [switch]$Force,

        # Launches and runs the invoked command in an administrator instance of
        # PowerShell.
        [Parameter()]
        [switch]$Administrator,

        # Bypasses schema validation for the "winget.packages.json". This is
        # for testing purposes and should not be used in normal usage.
        [Parameter()]
        [switch]$SkipValidation
    )

    function Write-ProgressHelper
    {
        param (
            [PSObject[]]$Packages,
            [int]$PackageIndex
        )

        $i = $PackageIndex + 1
        $bar = ('─' * 64) # Match Width of TableUI
        Write-Output "`r$bar"
        Write-Output "[ $i / $($Packages.Count) ] Installing '$($Packages[$PackageIndex].PackageIdentifier)'"
        Write-Output "$bar`n"
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
        $label = 'Microsoft Article'
        $url = 'https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/create-symbolic-links'
        Write-Warning ("Some programs will not install correctly if WinGet is used without administrator rights.`n" +
                    "`t This is particularly true for zip-based installs which involve the creation of symbolic`n" +
                    "`t links to export the utility the WinGet 'Links' path. Administrators may grant users`n" +
                    "`t privileges to create symbolic links via local policies.`n" +
                    "`t For more information see: " + (New-HyperLinkText -Label $label -Url $url))
        Write-Output 'Press ENTER to continue ...'
        Wait-ConsoleKeyEnter
    }

    if (-not(Test-Path variable:Confirm)) {
        $Confirm = $false
    }

    if ($Force -and -not $Confirm) {
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

    if (-not($SkipValidation) -and -not(Test-Json -Json (Get-Content $PackageDatabase | Out-String) -SchemaFile $PackageDatabaseSchema)) {
        Write-Error "Schema validation failed for: '$PackageDatabase'. Please fix and try again. The file can be validated against '$PackageDatabaseSchema'."
        return
    }

    $installPackages = @(Get-Content $PackageDatabase | ConvertFrom-Json)

    $checkpointFile = $CheckpointFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
    if ($NotInstalled) {
        if (Test-Path $checkpointFile) {
            # Check across all sources for packages, not just winget.
            $checkpointPackageIds = (Get-Content $checkpointFile | ConvertFrom-Json).Sources.Packages.PackageIdentifier

            $installPackages = @($installPackages | Where-Object {
                $checkpointPackageIds -notcontains $_.PackageIdentifier
            })
        } else {
            Write-Error "No checkpoint file found. 'Checkpoint-WinGetSoftware' should be run before using -NotInstalled."
            return
        }
    }

    if (-not($All)) {
        $installPackages  = @($installPackages | Where-Object {
            &$isMatch -p1 $Tag -p2 $_.Tags
        })
    }

    if ($ExcludeTag.Count -gt 0) {
        $installPackages  = @($installPackages | Where-Object {
            &$MatchNoneScriptBlock -p1 $ExcludeTag -p2 $_.Tags
        })
    }

    if ($installPackages.Count -eq 0) {
        Write-Output "No packages to install."
        return
    }

    $fakePackages = $installPackages | Where-Object { $_.PackageIdentifier -match $FakePackageExpression } | Sort-Object -Property PackageIdentifier
    $installPackages = $installPackages | Where-Object { $_.PackageIdentifier -notmatch $FakePackageExpression } | Sort-Object -Property PackageIdentifier

    if ($null -ne $fakePackages) {
        $installPackages = $installPackages + $fakePackages
    }

    if ($UseUI) {
        $selections = [bool[]]@()

        $showPackageDetailsScriptBlock = {
            param($currentSelections, $selectedIndex)
            $fakePackage = $installPackages[$selectedIndex].PackageIdentifier -match $FakePackageExpression
            $hasPostInstall = $installPackages[$selectedIndex].PSobject.Properties.Name -contains "PostInstall"
            if ($fakePackage) {
                $title = $installPackages[$selectedIndex].PackageIdentifier
                $details = @("The selected package is not part of winget and only executes post-install comamnds.")
            } else {
                $commandArgs = @('show', $installPackages[$selectedIndex].PackageIdentifier)
                if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
                    $commandArgs += @('--source', $DefaultSource)
                }
                $consoleEncoding = [console]::OutputEncoding
                [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
                $details = @('')
                $details += winget $commandArgs --no-vt
                [console]::OutputEncoding = $consoleEncoding
                $fistLine = $details | Select-String -Pattern 'Found\s+(.*\[.*\])'
                $found = (($null -ne $fistLine) -and ($fistLine.Matches.Count -eq 1))
                if ($found) {
                    $title = $fistLine.Matches[0].Groups[1].Value
                    $details = $details[$fistLine.LineNumber..($details.Length - 1)]
                } else {
                    $title =$installPackages[$selectedIndex].PackageIdentifier
                }
            }
            if ($hasPostInstall) {
                $details += "`nPost-Install Commands:"
                $installPackages[$selectedIndex].PostInstall.Commands | ForEach-Object { $details += "`t$_" }
            }
            Show-Paginated -TextData $details -Title $title
            Hide-TerminalCursor
        }

        $TableUIArgs = @{
            Table = $installPackages
            Title = 'Select Software to Install'
            EnterKeyDescription = "Press ENTER to show selection details."
            EnterKeyScript = $showPackageDetailsScriptBlock
            DefaultMemberToShow = "PackageIdentifier"
            SelectedItemMembersToShow = @("PackageIdentifier", "Tags", "Version", "Location", "Interactive")
            Selections = ([ref]$selections)
        }

        Enter-AltScreenBuffer
        Hide-TerminalCursor
        Show-TableUI @TableUIArgs
        Exit-AltScreenBuffer

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

        $fakePackage = ($installPackage.PackageIdentifier -match $FakePackageExpression)
        if ($fakePackage) {
            Write-Verbose "command: (post-install only)"
        } else {
            Write-Verbose "command: winget install$(Get-WinGetSoftwareInstallArgs -Package $installPackage -UseLatest:$UseLatest)"
        }

        if ($PSCmdlet.ShouldProcess($installPackage.PackageIdentifier)) {
            Install-WinGetSoftware -Package $installPackage -ErrorCount ([ref]$errorCount)
        }

        Write-Output ""

        $packageIndex++
    }

    if ($errorCount -gt 0) {
        Write-Error "Done (Errors = $errorCount)."
    } else {
        Write-Output "Done."
    }
}

function Test-ObjectProperty
{
    param (
        [object]$Object,
        [string]$PropertyName
    )
    $PropertyName -in $Object.PSobject.Properties.Name
}

function Get-WinGetSoftwareInstallArgs
{
    param(
        [object]$Package,
        [switch]$UseLatest
    )

    if ($Interactive -or ((Test-ObjectProperty -Object $Package -Property "Interactive") -and $Package.Interactive)) {
        $interactiveArg = ' --interactive'
    } else {
        $interactiveArg = ''
    }

    $packageIdArg = " --id $($Package.PackageIdentifier)"

    if (-not([string]::IsNullOrWhiteSpace($DefaultSource))) {
        $sourceArg = " --source $DefaultSource"
    } else {
        $sourceArg = ''
    }

    if ((((Test-ObjectProperty -Object $Package -Property "VersionLock") -and $Package.VersionLock) -or -not($UseLatest)) -and
        (Test-ObjectProperty -Object $Package -Property "Version") -and -not([string]::IsNullOrWhiteSpace($Package.Version))) {
        $versionArg = " --version $($Package.Version)"
    } else {
        $versionArg = ''
    }

    if ((Test-ObjectProperty -Object $Package -Property "Location") -and -not([string]::IsNullOrWhiteSpace($Package.Location))) {
        $locationArg = " --location '$($Package.Location)'"
    } else {
        $locationArg = ''
    }

    if ((Test-ObjectProperty -Object $Package -Property "AdditionalArgs") -and -not([string]::IsNullOrWhiteSpace($Package.AdditionalArgs))) {
        $additionalArgs = " $($Package.AdditionalArgs)"
    } else {
        $additionalArgs = ''
    }

    return "$interactiveArg$packageIdArg$sourceArg$versionArg$locationArg$additionalArgs"
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

    $fakePackage = $Package.PackageIdentifier -match $FakePackageExpression
    if ($fakePackage) {
        $installOk = $true
    } else {
        $installArgs = Get-WinGetSoftwareInstallArgs -Package $Package -UseLatest:$UseLatest
        Invoke-Expression "winget install $installArgs"

        $installOk = $LASTEXITCODE -eq 0
        Write-Verbose "returned: $LASTEXITCODE"
    }

    if (-not($installOk)) { $ErrorCount.Value++ }
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
        }
    }

    if (-not($runPostInstall)) { continue }

    Write-Output "Post-install: running ..."

    $terminatePostInstall = $false
    foreach ($cmd in $Package.PostInstall.Commands) {
        $runCommand = $true
        while ($runCommand) {
            $runCommand = $false
            Write-Verbose "executing: '$cmd'"
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
                    $terminatePostInstall = $true
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

        if ($terminatePostInstall) {
            break;
        }
    }

    Write-Output "Post-install: complete."
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
