Set-StrictMode -Version 3
Import-Module "$PSScriptRoot\WinGet-Utils.psm1"

[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"
[string]$IgnoreFilePath = "$PSScriptRoot\winget.{HOSTNAME}.ignore"

<#
.DESCRIPTION
    This is the back end handler for initializing various user-facing files
    that typically are expected to resize external to the module install
    location but symlinked.
#>
function Initialize-WinGetResource
{
    param(
        # The path to an existing file. This file will be symbolically linked.
        [string]$SourceFile,

        # Points to one of the internally referernced resource files which
        # the $SourceFile will be SmyLink'd or copied to.
        [string]$DestinationFile
    )

    $DestinationFilename = $(Split-Path -Leaf $DestinationFile)

    if (-not([string]::IsNullOrWhiteSpace($SourceFile))) {
        if ((Test-Path $DestinationFile) -and -not(Test-ReparsePoint $DestinationFile)) {
            Write-Output "Backing up existing '$DestinationFilename'."
            Move-Item $DestinationFile -Destination "$DestinationFile.bak" -Force
        }

        $SymLinkArgs = @{
            ItemType = "SymbolicLink"
            Path = "$(Split-Path -Parent $DestinationFile)"
            Name = $DestinationFilename
            Value = "$($SourceFile | Resolve-Path)"
            Force = $true
        }

        Write-Output "Creating new symlink for '$DestinationFilename'."
        New-Item @SymLinkArgs
    } elseif (Test-Path $DestinationFile) {
        Write-Output "The '$DestinationFilename' file is already initialized."
        return
    } else {
        $currentVersion = [version]"0.0"
        if (-not[version]::TryParse((Split-Path -Leaf (Get-Item $PSScriptRoot/..)), [ref]$currentVersion)) {
            # Not installed as a module, do not try to migrate
            Write-Output "Not installed as a module. Migration of '$DestinationFilename' cannot be performed."
            return
        }

        $selectedVersion = [version]"0.0"
        $selectedPackageFile = $null
        $moduleVersionPaths = Get-ChildItem -Directory $PSScriptRoot/../..
        $moduleVersionPaths | Where-Object { [version]($_.Name) -ne $currentVersion } | ForEach-Object {
            $packageFile = (Join-Path $_ "modules/$DestinationFilename")
            if (Test-Path $packageFile) {
                $version = [version](Split-Path -Leaf $_)
                if ($version -gt $selectedVersion) {
                    $selectedVersion = $version
                    $selectedPackageFile = $packageFile
                }
            }
        }

        if ($null -ne $selectedPackageFile) {
            $source = Get-Item $selectedPackageFile
            if ($source.Target) {
                if (-not(Test-Administrator)) {
                    Write-Warning "A symlink to '$DestinationFilename' cannot be created as a non-admin."
                    return
                }

                Write-Output "Creating new symlink to '$DestinationFilename'."
                $SymLinkArgs = @{
                    ItemType = "SymbolicLink"
                    Path = "$(Split-Path -Parent $DestinationFile)"
                    Name = $DestinationFilename
                    Value = $source.Target
                }

                New-Item @SymLinkArgs
            } else {
                Write-Output "Copying existing '$DestinationFilename'."
                Copy-Item -Path $source.FullName -Destination $DestinationFile
            }
        } else {
            Write-Output "No '$DestinationFilename' detected."
            Write-Output "Create one and provide it as the argument to -SourceFile."
        }
    }
}

<#
.DESCRIPTION
    Initialize the local "winget.software.json" needed by Restore-WinGetSoftware.
    If -SourceFile is specified, the file will be symbolically linked to the
    appropriate location. When this parameter is not specified, the cmdlet will
    auto-detect other installed module versions and attempt to find the latest
    existing "winget.packages.json". In such cases, it will make a symlink
    only if one was used previously; otherwise it will copy the previous file.

.EXAMPLE
    PS> Initialize-WinGetRestore -SourceFile "./winget.software.json"

.EXAMPLE
    PS> Initialize-WinGetRestore
#>
function Initialize-WinGetRestore
{
    param(
        <#
        The path to an existing "winget.software.json" file. This file
        will be symbolically linked.
        #>
        [string]$SourceFile,

        <#
        When set, the cmdlet will automatically relaunch using an Administrator
        PowerShell instance. This cmdlet needs such permissions to create
        Symbolic Links.
        #>
        [switch]$Administrator
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
        $cmdArgs = "-NoLogo -NoExit -Command Initialize-WinGetRestore $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList $cmdArgs
        return
    }

    Initialize-WinGetResource -SourceFile $SourceFile -DestinationFile $PackageDatabase
}


<#
.DESCRIPTION
    Initialize the local "winget.{HOSTNAME}.ignore" used by various cmdlets.
    If -SourceFile is specified, the file will be symbolically linked to the
    appropriate location. When this parameter is not specified, the cmdlet will
    auto-detect other installed module versions and attempt to find the latest
    existing "winget.{HOSTNAME}.ignore". In such cases, it will make a symlink
    only if one was used previously; otherwise it will copy the previous file.

.EXAMPLE
    PS> Initialize-WinGetIgnore -SourceFile "./winget.example-hostname.ignore"

.EXAMPLE
    PS> Initialize-WinGetIgnore
#>
function Initialize-WinGetIgnore
{
    param(
        <#
        The path to an existing winget-ignore file. This file will be
        symbolically linked.
        #>
        [string]$SourceFile,

        <#
        When set, the cmdlet will automatically relaunch using an Administrator
        PowerShell instance. This cmdlet needs such permissions to create
        Symbolic Links.
        #>
        [switch]$Administrator
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
        $cmdArgs = "-NoLogo -NoExit -Command Initialize-WinGetIgnore $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList $cmdArgs
        return
    }

    $ignoreFile = $IgnoreFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())
    Initialize-WinGetResource -SourceFile $SourceFile -DestinationFile $ignoreFile
}
