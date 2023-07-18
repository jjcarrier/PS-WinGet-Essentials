
function Merge-WingetSoftware
{
    param (
        [string]$New,
        [string]$Old
    )

    $newList = Get-Content $New | ConvertFrom-Json
    $oldList = Get-Content $Old | ConvertFrom-Json

    if ($oldList.'$schema' -ne $newList.'$schema')
    {
        # If the schemas do not match, it is not safe to merge. The user has to manually resolve this.
        Write-OutputIndented "Merge could not be performed. Please manually merge '$New' and '$Old'"
        return
    }

    foreach ($source in $oldList.Sources)
    {
        $sourceIndex = ([Collections.Generic.List[Object]]$oldList.Sources).FindIndex( {$args[0].SourceDetails.Name -eq $source.SourceDetails.Name})
        #TODO if sourceIndex is < 0 add the source in its entirety

        $newList.Sources[$sourceIndex].Packages = $newList.Sources[$sourceIndex].Packages | Sort-Object -Property PackageIdentifier

        $sortedSourcePackages = ($source.Packages | Sort-Object)
        $uniqueSourcePackageIds = $sortedSourcePackages.PackageIdentifier | Get-Unique
        foreach ($packageId in $uniqueSourcePackageIds)
        {
            $package = ($sortedSourcePackages | Where-Object { $_.PackageIdentifier -eq $packageId })[0]
            #$packageIndex = (0..($newList.Sources[$sourceIndex].Packages.Count-1)) | Where-Object {$newList.Sources[$sourceIndex].Packages[$_].PackageIdentifier -eq $packageId}
            $packageIndex = ([Collections.Generic.List[Object]]$newList.Sources[$sourceIndex].Packages).FindIndex({
                $args[0].PackageIdentifier -eq $package.PackageIdentifier })

            $packageExists = $null -ne $packageIndex
            $addEntry = -not $packageExists

            if ($packageExists)
            {
                $oldVersion = $package.Version
                $newVersion = $newList.Sources[$sourceIndex].Packages[$packageIndex].Version

                if ($newVersion -lt $oldVersion)
                {
                    # Determine if package appears to support multiple installs
                    $duplicates = $newList.Sources[$sourceIndex].Packages | Where-Object {
                        ($_.PackageIdentifier -eq $package.PackageIdentifier) }

                    $addEntry = @($duplicates).Count -gt 1

                    if (-not $addEntry)
                    {
                        $newList.Sources[$sourceIndex].Packages[$packageIndex].Version = $package.Version
                        Write-OutputIndented "Found newer version in cache ($($package.PackageIdentifier))"
                    }
                }
            }

            if ($addEntry)
            {
                $item = [PSCustomObject]@{
                    PackageIdentifier = $package.PackageIdentifier
                    Version = $package.Version
                }
                $newList.Sources[$sourceIndex].Packages += $item
                Write-OutputIndented "Merging ($($package.PackageIdentifier))"
            }
        }

        $newList.Sources[$sourceIndex].Packages = $newList.Sources[$sourceIndex].Packages | Sort-Object -Property PackageIdentifier
    }

    $newList | ConvertTo-Json -Depth 10 | Out-File $Old
    Write-OutputIndented "Merged."

    Pause
}
