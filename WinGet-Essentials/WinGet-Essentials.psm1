Import-Module "$PSScriptRoot/modules/WinGet-Update.psm1"
Import-Module "$PSScriptRoot/modules/WinGet-Restore.psm1"
Import-Module "$PSScriptRoot/modules/WinGet-Checkpoint.psm1"

Set-Alias winup                 Update-WingetSoftware
Set-Alias winget-update         Update-WingetSoftware
Set-Alias winget-restore        Restore-WingetSoftware
Set-Alias winget-checkpoint     Checkpoint-WingetSoftware
