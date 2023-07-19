# WinGet-Essentials PowerShell Module

![PSGallery](https://img.shields.io/powershellgallery/p/WinGet-Essentials)

## Description

Provides functionality for improved software management. This module includes
the following functionality:

* A simple CLI interface for `winget update`. Allows for:
  * Ignore Package support, via a `winget.{HOSTNAME}.ignore` file.
  * Tab-completion for locally cached available upgradable packages.
  * An interactive UI for selecting which packages to install.
  * Elevation option to instruct the tool to perform the install as an Administrator.
* A tag-based deployment tool which allows for:
  * Installation of suites of self-maintained tagged package-identifiers.
  * Elevation option to instruct the tool to perform the install as an Administrator.
* A basic checkpoint command, that:
  * Takes a backup of the last checkpoint.
  * Saves a list of installed software with version info.
  * This will mostly an alias for `winget export --include-versions`.

> NOTE: A future addition to this module will provide a way for `winget-restore`
  to deploy software from a checkpoint to the host machine. This will leverage
  the user-provided tags as a way to filter what software to restore and a
  way to use the specified versions or use-latest available versions.

## Installation

Download/install the module from `PSGallery`:

```pwsh
Install-Module -Name WinGet-Essentials -Repository PSGallery
```

Add the module to your `$PROFILE`:

```pwsh
Import-Module WinGet-Essentials
```

## Cmdlets

The current set of cmdlets provided by this module are:

* Update-WingetSoftware (aliases: winget-update, winup)
* Checkpoint-WingetSoftware (aliases: winget-checkpoint)
* Restore-WingetSoftware (aliases: winget-restore)

## Update-WingetSoftware

Provides a basic UI for updating software available in a WinGet repository.

### Usage

To selectively install updates using a simple UI run:

```pwsh
Update-WingetSoftware
```

![CLI Tab Completion](img/winget-update-ui.png)


To install a specific package run (supports tab-completion for cached updatable package IDs):

```pwsh
Update-WingetSoftware <WinGetPackageID>[,<AnotherWinGetPackageID>]
```

![CLI Tab Completion](img/winget-update-cli.png)

To update the cached list of upgradable package IDs, run:

```pwsh
Update-WingetSoftware -Sync
```

### Ignore package IDs

To ignore specific packages from appearing in this interface, create a
`winget.{HOSTNAME}.ignore` file in the same directory as the `winget-update.psm1`.
This path may for instance be:

`$env:USERPROFILE\Documents\PowerShell\Modules\WinGet-Essentials\<MODULE_VERSION>\modules`

Each line should contain a single winget package ID (verbatim).

> __IMPORTANT NOTE:__ It is recommended that the user creates a SymLink for this file
  instead of having the file reside directly in this path. This is to avoid
  accidental deletion during `Uninstall-Module`. It also provides more flexibility
  for linking the same file to multiple versions of the module (assuming there
  are no compatibility issues between the versions).

## Checkpoint-WingetSoftware

Stores a snapshot of installed software, including versions. This can be used
by WinGet natively to reinstall the listed software, or (__in a future release__)
restore sets of software based on tags using `Restore-WingetSoftware`.

The checkpoint file and its backup are stored in the same path that this module
resides in. This path may for instance be:

`$env:USERPROFILE\Documents\PowerShell\Modules\WinGet-Essentials\<MODULE_VERSION>\modules`

> __IMPORTANT NOTE:__ `Uninstall-Module` will indiscriminately remove files in
  the associated module's directory. Consider moving these files to another
  location. A future version of this module will likely provide a user-configurable
  way to redirect this file to other locations.

### Usage

```pwsh
Checkpoint-WingetSoftware
```

## Restore-WingetSoftware

Restores a set of software packages based on a locally, user-managed,
`winget.packages.json` (to be placed in the same directory as this module).
The set of packages to be installed/restored is determined by tags. The tags
can be used in two ways: `AND-comparison` or `OR-comparison`. This is determined
by the `-MatchAny` switch parameter (default behavior is to `Match All` tags).
This cmdlet support tab completions for the user-defined tags found in the
`winget.packages.json` file.

### Setup of winget.packages.json

Before using this cmdlet, a `winget.packages.json` file needs to be manually
setup. This file is to be placed in the same directory as this module.
This path may for instance be:

`$env:USERPROFILE\Documents\PowerShell\Modules\WinGet-Essentials\<MODULE_VERSION>\modules`

> __IMPORTANT NOTE:__ It is recommended that the user creates a SymLink for this file
  instead of having the file reside directly in this path. This is to avoid
  accidental deletion during `Uninstall-Module`. It also provides more flexibility
  for linking the same file to multiple versions of the module (assuming there
  are no compatibility issues between the versions).

This JSON file is to contain an array of objects describing each package of
interest. It should have the following form:

```json
[
  {
    "PackageIdentifier": "<WINGET_PACKAGE_ID1>",
    "Tags": [
      "<MY_TAG1>",
      "<MY_TAG2>",
    ]
  },
  {
    "PackageIdentifier": "<WINGET_PACKAGE_ID2>",
    "Tags": [
      "<MY_TAG1>",
      "<MY_TAG3>",
    ]
  }
]
```

### Usage

Example: All packages containing the both the tags: "Dev" and "Essential" will
be presented in a UI for user refinement of packages to install.

```pwsh
Restore-WingetSoftware -Tags Dev,Essential -UseUI
```

![CLI Tab Completion](img/winget-restore-ui.png)

Example: Install all packages tagged with any of the following: "Essential",
"Desktop" but not containing "Dev".

```pwsh
Restore-WingetSoftware -Tags Essential,Desktop -MatchAny -ExcludeTags Dev
```

![CLI Tab Completion](img/winget-restore-cli.png)

## Additional Notes

One feature that might be missing from a tool containing the word `Essentials`
is a tab-completion interface for winget itself. This is currently left out of
this module, but may be included in the future as an optional function to invoke,
in any case this is a trivial feature to add and is well-documented by Microsoft here:

[Microsoft Learn: WinGet Tab Completion](https://learn.microsoft.com/en-us/windows/package-manager/winget/tab-completion)

Other code repositories provide suites of tab-completion support for various
commands such as:

[PSTabCompletions Git Repository](https://github.com/jjcarrier/PSTabCompletions)
