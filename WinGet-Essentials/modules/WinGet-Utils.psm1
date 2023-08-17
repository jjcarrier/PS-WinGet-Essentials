Set-StrictMode -Version 3

[string]$IgnoreFilePath = "$PSScriptRoot\winget.{HOSTNAME}.ignore"

<#
.DESCRIPTION
    Test whether the current instance of PowerShell is an administrator.
#>
function Test-Administrator
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    return (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

<#
.DESCRIPTION
    Test whether the specified file path points to a reparse point (i.e. symlink
    or hardlink).
#>
function Test-ReparsePoint
{
    param(
        [string]$FilePath
    )

    $file = Get-Item $FilePath -Force -ea SilentlyContinue
    return [bool]($file.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

<#
.DESCRIPTION
    Gets a list of winget upgrade IDs to ignore. If the file does not exist,
    attempt to locate the file in a prior module install. If one exists, a
    SymLink will be created if the source itself was a SymLink; otherwise, it
    will be copied to the current module version's folder. In cases, where a
    SymLink is being created, the user must be an administrator, if not, the
    operation will be skipped and a warning will be emitted.
#>
function Get-WinGetSoftwareIgnores
{
    Initialize-WinGetIgnore | Out-Null
    $ignoreFile = $IgnoreFilePath.Replace('{HOSTNAME}', $(hostname).ToLower())

    if (-not(Test-Path $ignoreFile)) {
        return $null
    }

    return Get-Content $ignoreFile
}
