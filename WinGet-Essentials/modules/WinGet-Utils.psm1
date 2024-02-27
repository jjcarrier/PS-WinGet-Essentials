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

<#
.DESCRIPTION
    Displays and services a simple pager UI.
#>
function Show-Paginated
{
    param (
        [string]$Title,
        [string[]]$TextData
    )

    <#
    .DESCRIPTION
        Writes the frame buffer to output.
    #>
    function Show-Frame
    {
        param(
            [string[]]$FrameBuffer,
            [int]$FrameWidth
        )
        $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = 0 }
        $FrameBuffer | ForEach-Object {
            if ($_.Length -lt $FrameWidth) {
                ($_ + (' ' * $FrameWidth - $_.Length))
            } else {
                $_
            }
        } | ForEach-Object {
            Write-Host -NoNewline $_
        }
    }

    <#
    .DESCRIPTION
        Prepares a line for output to the console. The line is constrained
        to the specified width and will be truncated if it exceeds that length.
    #>
    function Format-LineForConsole
    {
        param(
            [string]$Line,
            [int]$FrameWidth
        )
        if ($Line.Length -gt $FrameWidth) {
            # Truncate to fit width
            $Line = "$($Line.Substring(0, $FrameWidth - 1))…"
        } else {
            # Pad the tail to fit $FrameWidth
            $Line = $Line + (' ' * ($FrameWidth - $Line.Length))
        }

        return $Line
    }

    <#
    .DESCRIPTION
        Prepares an array of strings for pagination by pre-rendering the word
        wrapped output according to the specified width.
    #>
    function Format-ContentForConsole
    {
        param (
            [string[]]$Content,
            [int]$FrameWidth
        )

        $halfFrameWidth = [Math]::Floor($FrameWidth / 2)
        $newContent = @()

        foreach ($line in $Content) {
            $line = $line.TrimEnd()
            if ($line.Length -gt $FrameWidth) {
                while ($line.Length -gt $FrameWidth) {
                    $splitIndex = $line.LastIndexOf(' ', $FrameWidth)

                    if (($splitIndex -eq -1) -or ($splitIndex -lt $halfFrameWidth)) {
                        $splitIndex = $FrameWidth
                    }

                    $newContent += $line.Substring(0, $splitIndex)
                    $line = $line.Substring($splitIndex).TrimStart()
                }
            }

            $newContent += $line
        }

        return $newContent
    }

    $currentIndex = 0
    $reservedLines = 2 # Two lines removed for title and footer rows.
    $lastWidth = 0
    $header = ''
    $content = ''
    $footer = ''
    $controls = 'Use ⇧/⇩ arrows to scroll, PAGE UP/PAGE DOWN to jump, Q to quit.'

    while ($true) {
        $pageSize = $Host.UI.RawUI.WindowSize.Height - $reservedLines
        $width = $Host.UI.RawUI.WindowSize.Width

        if ($width -ne $lastWidth) {
            $header = Format-LineForConsole -Line $Title -FrameWidth $width
            $content = Format-ContentForConsole -Content $TextData -FrameWidth $width
            $footer = Format-LineForConsole -Line $controls -FrameWidth $width
        }

        # Add the title line to the frame buffer.
        [string[]]$frameBuffer = @('')
        $frameBuffer += "$($PSStyle.Foreground.Black)$($PSStyle.Background.BrightWhite)$header$($PSStyle.Reset)`n"

        # Add the in-view content lines to the frame buffer.
        # NOTE: Text must be formatted to account for word wrapping consuming additional lines.
        $endIndex = [Math]::Min($currentIndex + $pageSize, $content.Length) - 1
        $content[$currentIndex..$endIndex] | ForEach-Object { $frameBuffer += "$(Format-LineForConsole -Line $_ -FrameWidth $width)`n" }

        # Add pad lines to the frame buffer.
        $padLines = $pageSize - ($endIndex - $currentIndex) - 1
        $padLine = "$(' ' * $width)`n"
        for ($i = 0; $i -lt $padLines; $i++) { $frameBuffer += $padLine }

        # Add footer line to the frame buffer.
        $frameBuffer += "$($PSStyle.Foreground.Black)$($PSStyle.Background.BrightWhite)$footer$($PSStyle.Reset)"

        Show-Frame -FrameBuffer $frameBuffer -Width $width
        Hide-TerminalCursor

        if (-not([Console]::KeyAvailable)) {
            Start-Sleep -Milliseconds 10
            continue
        }

        $key = [Console]::ReadKey($true)
        $currentKey = [char]$key.Key
        switch ($currentKey)
        {
            # Navigate up
            { $_ -eq [ConsoleKey]::UpArrow } {
                if ($currentIndex -gt 0) { $currentIndex-- }
            }

            # Navigate down
            { $_ -eq [ConsoleKey]::DownArrow } {
                if ($currentIndex -lt $content.Length - $reservedLines) { $currentIndex++ }
            }

            # Navigate up by one page
            { $_ -eq [ConsoleKey]::PageUp } {
                if ($currentIndex -gt $pageSize) {
                    $currentIndex -= $pageSize
                } else {
                    $currentIndex = 0
                }
            }

            # Navigate down by one page
            { $_ -eq [ConsoleKey]::PageDown } {
                if ($currentIndex + $pageSize -lt $content.Length) {
                    $currentIndex += $pageSize
                } else {
                    $currentIndex = $content.Length - $reservedLines
                }
            }

            { $currentKey -eq 'Q' } {
                return
            }
        }
    }
}
