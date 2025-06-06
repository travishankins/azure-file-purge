<<<<<<< HEAD
**Quick start**.

=======
>>>>>>> 0c29d17 (Final readme.md update)
````markdown
# 🧹 Azure File Share Purge Script<br>`Purge-AzFileShare.ps1`

Deletes files **older than *N* days** (optionally within a specific sub-folder) from an Azure File Share.

<div align="center">

[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-blue?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Azure CLI 2.60+](https://img.shields.io/badge/Azure%20CLI-2.60%2B-blue?logo=microsoftazure&logoColor=white)](https://learn.microsoft.com/cli/azure/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)
[![Issues](https://img.shields.io/github/issues-raw/<YOUR-GH-USERNAME>/azure-file-purge)](../../issues)

</div>

---

## ✨ Highlights

|  | Feature |
|--|---------|
| 🚀 **Scales** to tens of millions of objects – streams 5 000 entries per call & handles continuation tokens |
| 🌳 **Recursive** by default, or target a sub-folder via `-StartPath` |
| ⚡ **Parallel deletes** (configurable) for high throughput |
| 🔍 **`-WhatIf`** mode prints paths **without deleting** |
| ♻️ **Resume-safe** – rerun any time; already-deleted files are skipped |
| 🔐 Works with **Shared Key** *or* **Azure AD / Managed Identity** authentication |

---

## 🛠️ Prerequisites

| Requirement | Notes |
|-------------|-------|
| **PowerShell 7+** | Windows, macOS, Linux, or Azure Cloud Shell |
| **Azure CLI 2.60+** | Script shells out to `az storage file …` |
| **List/Delete permission** | • Shared Key<br>• **or** Azure roles:<br>&nbsp;&nbsp;_Storage File Data SMB Share Contributor_<br>&nbsp;&nbsp;_Storage File Data Privileged Contributor_ |

---

## ⚡ Quick start (local workstation)

### 1 — 🗝️ Grab a storage-account key

```bash
az login
az account set --subscription "<SUBSCRIPTION-GUID>"

az storage account keys list \
  --resource-group  <RESOURCE-GROUP> \
  --account-name    <STORAGE-ACCOUNT> \
  --query "[0].value" -o tsv
````

Copy the 88-character string.

### 2 — 🔑 Export credentials

```bash
export AZURE_STORAGE_ACCOUNT=<STORAGE-ACCOUNT>
export AZURE_STORAGE_KEY=<PASTE-KEY-HERE>
```

*(PowerShell users: `$env:AZURE_STORAGE_ACCOUNT='...'`)*

### 3 — 🧪 Dry-run the script

```powershell
./Purge-AzFileShare.ps1 `
  -ResourceGroupName  <RESOURCE-GROUP> `
  -StorageAccountName $Env:AZURE_STORAGE_ACCOUNT `
  -ShareName          <FILE-SHARE> `
  -Days               45 `
  -StartPath          ''      # or 'Folder/SubFolder' to scope lower
  -WhatIf             # preview only
```

Remove `-WhatIf` once the preview looks correct.

---

## ⚙️ Parameters

| Parameter                 | Req’d | Default | Description                              |
| ------------------------- | ----- | ------- | ---------------------------------------- |
| **`-ResourceGroupName`**  | ✔     | —       | RG that owns the storage account         |
| **`-StorageAccountName`** | ✔     | —       | Storage account hosting the share        |
| **`-ShareName`**          | ✔     | —       | File-share to purge                      |
| **`-Days`**               |       | `30`    | Delete files older than *N* days         |
| **`-PageSize`**           |       | `5000`  | Objects per list page (service max)      |
| **`-MaxConcurrent`**      |       | `32`    | Parallel delete workers                  |
| **`-StartPath`**          |       | `''`    | Folder to begin recursion (blank = root) |
| **`-WhatIf`**             |       | —       | Dry-run; no deletes executed             |

---

## ⏰ Scheduling options

| Platform             | How to wire it                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------ |
| **Azure Automation** | Import as PS 7 runbook → store key in **secure variables** → schedule 03:00 UTC daily      |
| **GitHub Actions**   | Save key in **Secrets** → CRON `0 3 * * *` → `pwsh ./Purge-AzFileShare.ps1 …`              |
| **Task Scheduler**   | `pwsh -File Purge-AzFileShare.ps1 …` with nightly trigger; load env vars in wrapper `.bat` |

---


## 🤝 Contributing

PRs welcome!  Ideas:

* Retry/back-off logic
* Exclusion patterns / globbing
* Output to CSV or Log Analytics

