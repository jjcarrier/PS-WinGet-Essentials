function Build-RequiredModuleFiles {
    $data = Import-PowerShellDataFile .\*.psd1
    [array]$requiredModules = $data.RequiredModules

    if ($requiredModules) {
        Push-Location
        if ($IsWindows) {
            $modulesPath = "$env:USERPROFILE/Documents/PowerShell/Modules"
        } else {
            $modulesPath = '~/.local/share/powershell/Modules'
        }

        if (-not(Test-Path -PathType Container $modulesPath)) {
            New-Item -ItemType Directory $modulesPath
        }

        Set-Location $modulesPath

        foreach ($module in $requiredModules) {
            $moduleName = $module.ModuleName
            New-Item $moduleName -type Directory
            Write-Output "Creating fake .psd1 file for module $modulename at $((Get-Location).Path)\$moduleName\$moduleName.psd1"
            New-ModuleManifest ".\$moduleName\$moduleName.psd1"
        }

        Pop-Location
    }
}
