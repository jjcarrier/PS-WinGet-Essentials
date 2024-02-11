Set-StrictMode -Version 3

[string]$IgnoreFilePath = "$PSScriptRoot\winget.{HOSTNAME}.ignore"

<#
.DESCRIPTION
    Test whether the current instance of PowerShell is an administrator.
#>
function Test-Administrator
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
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

<#
.DESCRIPTION
    Enter the "Alternate Screen Buffer".
#>
function Enter-AltScreenBuffer
{
    $Host.UI.Write([char]27 + "[?1049h")
}

<#
.DESCRIPTION
    Exit the "Alternate Screen Buffer".
#>
function Exit-AltScreenBuffer
{
    $Host.UI.Write([char]27 + "[?1049l")
}

<#
.DESCRIPTION
    Show the terminal cursor.
#>
function Show-TerminalCursor
{
    $Host.UI.Write([char]27 + "[?25h")
}

<#
.DESCRIPTION
    Hide the terminal cursor.
#>
function Hide-TerminalCursor
{
    $Host.UI.Write([char]27 + "[?25l")
}

<#
.DESCRIPTION
    Start the display of busy indicator on supported terminals.
#>
function Start-TerminalBusy
{
    #https://learn.microsoft.com/en-us/windows/terminal/tutorials/progress-bar-sequences
    $Host.UI.Write([char]27 + "]9;4;3;0" + [char]7)
}

<#
.DESCRIPTION
    Stop the display of busy indicator on supported terminals.
#>
function Stop-TerminalBusy
{
    $Host.UI.Write([char]27 + "]9;4;0;0" + [char]7)
}

<#
.DESCRIPTION
    Draws job progress indicators.
#>
function Show-JobProgress
{
    param(
        [System.Management.Automation.Job]$Job
    )

    $progressIndicator = @('|', '/', '-', '\')
    $progressIter = 0

    Start-TerminalBusy
    Hide-TerminalCursor
    while ($Job.JobStateInfo.State -eq "Running") {
        $progressIter = ($progressIter + 1) % $progressIndicator.Count
            Write-Host "$($progressIndicator[$progressIter])`b" -NoNewline
        Start-Sleep -Milliseconds 125
    }
    Stop-TerminalBusy
}

<#
.DESCRIPTION
    Creates a hyperlink text entry.
#>
function New-HyperLinkText
{
    param(
        [string]$Url,
        [string]$Label
    )

    "`e]8;;$Url`e\$Label`e]8;;`e\"
}

<#
.DESCRIPTION
    Waits for user to press the ENTER key.
#>
function Wait-ConsoleKeyEnter
{
    while ($Host.ui.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode -ne [ConsoleKey]::Enter) {}
}

<#
.DESCRIPTION
    Check permissions for creating symbolic links.
#>
function Test-CreateSymlink
{
    $success = $true
    $symLinkArgs = @{
        ItemType = "SymbolicLink"
        Path = "$(Split-Path -Parent $PSScriptRoot)"
        Name = "check.tmp"
        Value = ""
        Force = $true
    }

    try {
        $tempFile = New-TemporaryFile
        $symLinkArgs.Value = $tempFile.FullName
        $symlinkFile = New-Item @symLinkArgs
        Remove-Item -Path $symlinkFile
    } catch {
        $success = $true
    } finally {
        Remove-Item -Path $tempFile
    }

    return $success
}
