function Build-RequiredModuleFiles {
    $data = Import-PowerShellDataFile .\*.psd1
    [array]$requiredModules = $data.RequiredModules

    if ($requiredModules) {
        Push-Location
        if ($IsWindows) {
            Set-Location "$env:USERPROFILE/Documents/PowerShell/Modules"
        } else {
            Set-Location '~/.local/share/powershell/Modules'
        }

        foreach ($module in $requiredModules) {
            $moduleName = $module.ModuleName
            New-Item $moduleName -type Directory
            Write-Output "Creating fake .psd1 file for module $modulename at $((Get-Location).Path)\$moduleName\$moduleName.psd1"
            New-ModuleManifest ".\$moduleName\$moduleName.psd1"
        }

        Pop-Location
    }
}
