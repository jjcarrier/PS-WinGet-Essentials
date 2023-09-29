# Basic tests for validating command options

# Check if winget is available, if not, skip test(s) that require it to be called.
try {
    $wingetCommand = Get-Command -CommandType Application winget
    $SkipNoWinGet = ($null -eq $wingetCommand)
}
catch {
    $SkipNoWinGet = $true
}

BeforeAll {
    Copy-Item -Path "$PSScriptRoot\test.packages.json" -Destination "$PSScriptRoot\..\WinGet-Essentials\modules\winget.packages.json"
    Copy-Item -Path "$PSScriptRoot\test.checkpoint" -Destination "$PSScriptRoot\..\WinGet-Essentials\modules\winget.$((hostname).ToLower()).checkpoint"

    Import-Module "$PSScriptRoot\..\WinGet-Essentials\modules\WinGet-Initialize.psm1"
    Import-Module "$PSScriptRoot\..\WinGet-Essentials\modules\WinGet-Restore.psm1"
}

AfterAll {
    Remove-Item "$PSScriptRoot\..\WinGet-Essentials\modules\winget.packages.json"
    Remove-Item "$PSScriptRoot\..\WinGet-Essentials\modules\winget.$((hostname).ToLower()).checkpoint"
}

Describe 'Restore-WinGetSoftware' {
    It "reports no packages when an unused tag is specified" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_unused" -WhatIf -Verbose -Force 4>&1
        $verboseLog -contains "No packages to install." | Should -Be $true
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 0
    }
}

Describe 'Restore-WinGetSoftware' {
    It "filters out packages not containing the specified tag" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_once" -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
    }
}

Describe 'Restore-WinGetSoftware' {
    It "filters out packages containing the excluded tag" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_twice" -ExcludeTag "tag_once" -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
    }
}

Describe 'Restore-WinGetSoftware' {
    It "filters out packages using AND-comparison" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_once","tag_twice" -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
    }
}

Describe 'Restore-WinGetSoftware' {
    It "filters out packages using OR-comparison when -MatchAny is set" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_once","tag_once_again" -MatchAny -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 2
    }
}

Describe 'Restore-WinGetSoftware' {
    It "provides all packages when -All is set" {
        $packages = Get-Content "$PSScriptRoot\test.packages.json" | ConvertFrom-Json
        $verboseLog = Restore-WinGetSoftware -All -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be $packages.Count
    }
}

Describe 'Restore-WinGetSoftware' {
    It "excludes packages that are already installed when -NotInstalled is set" {
        $verboseLog = Restore-WinGetSoftware -Tag "tag_twice" -NotInstalled -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
    }
}

Describe 'Restore-WinGetSoftware' {
    It "specifies the --version option when package contains 'Version' key" {
        $verboseLog = Restore-WinGetSoftware -Tag "package_with_version" -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
        $verboseLog -match '--version 1.0.0' | Should -Not -Be $null
    }
}

Describe 'Restore-WinGetSoftware' {
    It "omits the --version option when -UseLatest is set" {
        $verboseLog = Restore-WinGetSoftware -Tag "package_with_version" -UseLatest -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
        $verboseLog -match '--version 1.0.0' | Should -Be $null
    }
}

Describe 'Restore-WinGetSoftware' {
    It "specifies the --version option when package contains 'VersionLock' and -UseLatest is set" {
        $verboseLog = Restore-WinGetSoftware -Tag "package_with_version_lock" -UseLatest -WhatIf -Verbose -Force 4>&1
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -is [System.Management.Automation.InformationalRecord] })
        $verboseLog.Count | Should -Be 1
        $verboseLog -match '--version 1.0.0' | Should -Not -Be $null
    }
}

Describe 'Restore-WinGetSoftware' {
    It -Skip:$SkipNoWinGet "always runs PostInstall commands when PostInstall.Run is set to 'Always'" {
        $verboseLog = Restore-WinGetSoftware -Tag "always_run_post_install" -Verbose -Force -ErrorVariable errorLog -ErrorAction SilentlyContinue 4>&1
        $errorLog | Should -Be "Done (Errors = 1)."
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -like "Executing:*" })
        $verboseLog.Count | Should -Be 2
    }
}

Describe 'Restore-WinGetSoftware' {
    It "continues to run PostInstall commands after a command error when PostInstall.OnError is set to 'Continue'" {
        $verboseLog = Restore-WinGetSoftware -Tag "continue_post_install_commands_on_error" -Verbose -Force -ErrorVariable errorLog -ErrorAction SilentlyContinue 4>&1
        $errorLog.Count | Should -Be 2
        $errorLog[0] | Should -Be "Second Command"
        $errorLog[1] | Should -Be "Done (Errors = 1)."
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -like "Executing:*" })
        $verboseLog.Count | Should -Be 3
    }
}

Describe 'Restore-WinGetSoftware' {
    It "continues to run PostInstall commands after a command error when PostInstall.OnError is set to 'Skip'" {
        $verboseLog = Restore-WinGetSoftware -Tag "skip_post_install_commands_on_error" -Verbose -Force -ErrorVariable errorLog -ErrorAction SilentlyContinue 4>&1
        $errorLog.Count | Should -Be 2
        $errorLog[0] | Should -Be "Second Command"
        $errorLog[1] | Should -Be "Done (Errors = 1)."
        $verboseLog = [string[]]@($verboseLog | Where-Object { $_ -like "Executing:*" })
        $verboseLog.Count | Should -Be 2
    }
}
