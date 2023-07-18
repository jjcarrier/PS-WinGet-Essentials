@{
    RootModule = 'WinGet-Essentials.psm1'
    ModuleVersion = '0.9'
    GUID = '2a2b6c24-d6cc-4d59-a456-e7ccd90afd03'
    Author = 'Jon Carrier'
    CompanyName = 'Unknown'
    Copyright = '(c) Jon Carrier. All rights reserved.'
    Description = 'Essential "winget" utilities.'

    # CompatiblePSEditions = @()
    # PowerShellVersion = ''
    # RequiredModules = @()
    # ScriptsToProcess = @()
    # TypesToProcess = @()
    # FormatsToProcess = @()
    # NestedModules = @()

    FunctionsToExport = @()
    CmdletsToExport = @('Update-WinGetSoftware', 'Checkpoint-WinGetSoftware', 'Restore-WinGetSoftware')
    VariablesToExport = '*'
    AliasesToExport = @('winup', 'winget-update, winget-checkpoint, winget-restore')

    # ModuleList = @()
    # FileList = @()

    PrivateData = @{

        PSData = @{
            Tags = @('WinGet', 'Console', 'Terminal', 'UI')
            LicenseUri = 'https://github.com/jjcarrier/PS-WinGet-Essentials/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jjcarrier/PS-WinGet-Essentials'
            # IconUri = ''
            # ReleaseNotes = ''
            # Prerelease = ''
            # RequireLicenseAcceptance = $false
            # ExternalModuleDependencies = @('TextTable', 'TableUI')

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfoURI = ''
    # DefaultCommandPrefix = ''
}
