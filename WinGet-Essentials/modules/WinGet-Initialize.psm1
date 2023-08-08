[string]$PackageDatabase = "$PSScriptRoot\winget.packages.json"

<#
.DESCRIPTION
    Initialize the local "winget.software.json" need by Restore-WinGetSoftware.
    If -SourceFile is specified, the file will be symbolically linked to the
    appropriate location. When this parameter is not specified the cmdlet will
    auto-detect other installed module versions and attempt to find the latest
    existing `winget.packages.json`. In such cases, it will make a symlink if
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

    function Test-Administrator
    {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent();
        (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
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
        $cmdArgs = "-NoLogo -NoExit -Command Initialize-WinGetRestore $($boundParamsString -join ' ')"
        Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList $cmdArgs
        return
    }

    if (-not([string]::IsNullOrWhiteSpace($SourceFile))) {
        if (Test-Path $PackageDatabase) {
            Write-Output "Backing up existing winget.packages.json"
            Move-Item $PackageDatabase -Destination "$PackageDatabase.bak" -Force -Confirm
        }

        $SymLinkArgs = @{
            ItemType = "SymbolicLink"
            Path = "$(Split-Path -Parent $PackageDatabase)"
            Name = "$(Split-Path -Leaf $PackageDatabase)"
            Value = "$($SourceFile | Resolve-Path)"
        }

        Write-Output "Creating new symlink for winget.packages.json"
        New-Item @SymLinkArgs
    } elseif (Test-Path $PackageDatabase) {
        Write-Output "Already initialized."
        return
    } else {
        $currentVersion = [version]"0.0"
        if (-not[version]::TryParse((Split-Path -Leaf (Get-Item $PSScriptRoot/..)), [ref]$currentVersion)) {
            # Not installed as a module, do not try to migrate
            Write-Output "Not installed as a module. Nothing to do."
            return
        }

        $selectedVersion = [version]"0.0"
        $selectedPackageFile = ''
        $moduleVersionPaths = Get-ChildItem -Directory $PSScriptRoot/../..
        $moduleVersionPaths | Where-Object { [version]($_.Name) -ne $currentVersion } | ForEach-Object {
            $packageFile = (Join-Path $_ "modules/winget.packages.json")
            if (Test-Path $packageFile) {
                $version = [version](Split-Path -Leaf $_)
                if ($version -gt $selectedVersion) {
                    $selectedVersion = $version
                    $selectedPackageFile = $packageFile
                }
            }
        }

        if (-not([string]::IsNullOrWhiteSpace($selectedPackageFile))) {
            $source = Get-Item $selectedPackageFile
            if ($source.Target) {
                Write-Output "Creating new symlink to winget.packages.json"
                $SourceFile = $source.Target
            } else {
                Write-Output "Copying existing winget.packages.json"
                $SourceFile = $source.Name
            }


            $SymLinkArgs = @{
                ItemType = "SymbolicLink"
                Path = "$(Split-Path -Parent $PackageDatabase)"
                Name = "$(Split-Path -Leaf $PackageDatabase)"
                Value = $SourceFile
            }

            New-Item @SymLinkArgs
        } else {
            Write-Output "No winget.packages.json detected."
            Write-Output "Create one and provide it as the argument to -SourceFile."
        }
    }
}
