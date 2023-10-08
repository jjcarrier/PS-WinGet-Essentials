@{
    RootModule = 'WinGet-Essentials.psm1'
    ModuleVersion = '1.7.0'
    GUID = '2a2b6c24-d6cc-4d59-a456-e7ccd90afd03'
    Author = 'Jon Carrier'
    CompanyName = 'Unknown'
    Copyright = '(c) Jon Carrier. All rights reserved.'
    Description = 'Essential "winget" utilities.'

    # CompatiblePSEditions = @()
    # PowerShellVersion = ''
    # ScriptsToProcess = @()
    # TypesToProcess = @()
    # FormatsToProcess = @()
    # NestedModules = @()

    RequiredModules = @(
        @{ModuleName = 'TextTable'; ModuleVersion = '1.0.2'; Guid = '16a5ab4c-4d8c-42d6-8f72-227aea552a84'},
        @{ModuleName = 'TableUI'; ModuleVersion = '1.1.0';  Guid = 'b5eb9ef8-a2ef-40d4-a8d5-46d91ab7060e'}
    )
    FunctionsToExport = @('Update-WinGetEssentials', 'Update-WinGetSoftware', 'Checkpoint-WinGetSoftware', 'Restore-WinGetSoftware', 'Initialize-WinGetIgnore', 'Initialize-WinGetRestore', 'Merge-WinGetRestore')
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @('winup', 'winget-update', 'winget-checkpoint', 'winget-restore')

    # ModuleList = @()
    FileList = @(
        'WinGet-Essentials.psd1',
        'WinGet-Essentials.psm1',
        'modules\WinGet-Checkpoint.psm1',
        'modules\WinGet-Initialize.psm1'
        'modules\WinGet-Merge.psm1'
        'modules\WinGet-Restore.psm1',
        'modules\WinGet-Update.psm1'
        'modules\WinGet-Utils.psm1'
    )

    PrivateData = @{

        PSData = @{
            Tags = @('Windows', 'WinGet', 'Console', 'Terminal', 'UI')
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
