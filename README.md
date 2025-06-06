**Quick start**.

````markdown
# Azure File Share Purge Script (`Purge-AzFileShare.ps1`)

Deletes every file **older than _N_ days** (or in a specific sub-folder) from an Azure File Share.

* **Scales to tens of millions** of objects — walks the share with continuation tokens  
* **Recursive** by default; or start lower via `-StartPath`  
* **Parallel deletes** (configurable) for high throughput  
* **`-WhatIf` dry-run** prints paths without deleting  
* **Resume-safe** — rerun any time, already-deleted files are skipped  
* Works with **Shared Key** *or* **Azure AD / Managed Identity** authentication  

---

## Prerequisites 🛠️

| Requirement | Notes |
|-------------|-------|
| PowerShell 7+ | Windows, macOS, Linux, or Azure Cloud Shell |
| Azure CLI 2.60+ | The script shells out to `az storage file …` |
| List/Delete permission | Shared Key **or** Azure roles:<br>• _Storage File Data SMB Share Contributor_<br>• _Storage File Data Privileged Contributor_ |

---

## Quick start (local workstation)

### 1 — Get a storage-account key via CLI

```bash
# interactive login
az login
az account set --subscription "<SUBSCRIPTION-NAME-OR-GUID>"

# fetch the first key (usually 'key1')
az storage account keys list \
    --resource-group  <RESOURCE-GROUP> \
    --account-name    <STORAGE-ACCOUNT> \
    --query "[0].value" -o tsv
````

Copy the 88-character string.

### 2 — Export credentials

```bash
export AZURE_STORAGE_ACCOUNT=<STORAGE-ACCOUNT>
export AZURE_STORAGE_KEY=<PASTE-KEY-HERE>
```

*(macOS/Linux `bash/zsh` shown; in PowerShell use `$env:AZURE_STORAGE_ACCOUNT = '...'`.)*

### 3 — Dry-run the purge script

```powershell
./Purge-AzFileShare.ps1 `
    -ResourceGroupName  <RESOURCE-GROUP> `
    -StorageAccountName $Env:AZURE_STORAGE_ACCOUNT `
    -ShareName          <FILE-SHARE> `
    -Days               45 `
    -StartPath          ''        # or 'Folder/SubFolder' to scope lower
    -WhatIf
```

Remove `-WhatIf` once the preview looks correct.

---

## Parameters

| Name                      | Required | Default | Description                              |
| ------------------------- | -------- | ------- | ---------------------------------------- |
| **`-ResourceGroupName`**  | ✔        | —       | RG that owns the storage account         |
| **`-StorageAccountName`** | ✔        | —       | Storage account hosting the share        |
| **`-ShareName`**          | ✔        | —       | File-share to purge                      |
| **`-Days`**               | ✖        | `30`    | Delete files older than *N* days         |
| **`-PageSize`**           | ✖        | `5000`  | Objects per list page (service max)      |
| **`-MaxConcurrent`**      | ✖        | `32`    | Parallel delete workers                  |
| **`-StartPath`**          | ✖        | `''`    | Folder to begin recursion (blank = root) |
| **`-WhatIf`**             | ✖        | —       | Dry-run; no deletes executed             |

---
