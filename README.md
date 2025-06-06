# Azure File Share Purge Script (`Purge-AzFileShare.ps1`)

Deletes every file **older than _N_ days** (or in a specific sub-folder) from an Azure File Share.

* **Scales to tens of millions** of objects — walks the share with continuation tokens.
* **Recursive** — traverses every sub-directory unless you start in a narrower `-StartPath`.
* **Parallel deletes** (configurable semaphore) for fast throughput.
* **`-WhatIf` dry-run** prints the paths that *would* be removed without touching data.
* **Resume-safe** — re-running skips files that are already gone.
* Works with **Shared Key** *or* **Azure AD/Managed Identity** authentication.

---

## Prerequisites 🛠️

| Requirement | Notes |
|-------------|-------|
| PowerShell 7+ | Windows, macOS, Linux, or Azure Cloud Shell |
| Azure CLI 2.60+ | The script shells out to `az storage file …` |
| Permission to list / delete files | Shared key **or** AAD roles:<br>• _Storage File Data SMB Share Contributor_<br>• _Storage File Data Privileged Contributor_ |

---

## Quick start (local workstation)

```powershell
# 1 – set credentials (Shared Key example)
$env:AZURE_STORAGE_ACCOUNT = 'mystorageacct'
$env:AZURE_STORAGE_KEY     = '<88-char key>'

# 2 – run a preview (-WhatIf)
./Purge-AzFileShare.ps1 `
    -ResourceGroupName  'infra-rg' `
    -StorageAccountName $env:AZURE_STORAGE_ACCOUNT `
    -ShareName          'ingest' `
    -Days               45 `
    -StartPath          ''        # or 'Folder/SubFolder' to scope lower
    -WhatIf

# 3 – remove -WhatIf when happy
