
# 🧹 Azure File Share Purge Script  
`Purge-AzFileShare.ps1`

Deletes files **older than _N_ days** (optionally within a specific sub-folder) from an Azure File Share.

---

## ✨ Highlights

|    | Feature |
| :- | :------ |
| 🚀 | **Scales** to tens of millions of objects – streams 5 000 entries/page & handles continuation tokens |
| 🌳 | **Recursive** by default; optionally start lower via `-StartPath` |
| ⚡ | **Parallel deletes** (configurable) for high throughput |
| 🔍 | **`-WhatIf`** mode prints paths **without deleting** |
| ♻️ | **Resume-safe** – rerun any time; already-deleted files are skipped |
| 🔐 | Works with **Shared Key** *or* **Azure AD / Managed Identity** authentication |


---

## 🔄 How It Works

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐
│ Authenticate │────▶│ Recursive walk   │────▶│ Delete / log  │
└──────────────┘     └──────────────────┘     └───────────────┘
```

1. **Authenticate** — reads `AZURE_STORAGE_KEY` from the environment, or
   auto-retrieves it via `az storage account keys list`.
2. **Walk** — recursively lists every directory in the share (or below
   `-StartPath`) in pages of `-PageSize` entries, following continuation
   tokens until every file has been visited.
3. **Filter** — each file's `lastModified` timestamp is compared against the
   cut-off date (`now − Days`).
4. **Delete or preview** — matched files are either printed (`-WhatIf`) or
   dispatched for deletion through a semaphore-bounded thread pool
   (`-MaxConcurrent` workers).
5. **Summarise** — after all tasks complete, a final count of matched /
   deleted files is printed.

---

## 🛠️ Prerequisites

| Requirement | Notes |
|-------------|-------|
| **PowerShell 7+** | Windows · macOS · Linux · Azure Cloud Shell |
| **Azure CLI 2.60+** | Script shells out to `az storage file …` |
| **List / Delete permission** | *Either*:<br>• Shared Key<br>• **or** Azure roles:<br>&nbsp;&nbsp;_Storage File Data SMB Share Contributor_<br>&nbsp;&nbsp;_Storage File Data Privileged Contributor_ |

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
# PowerShell users:
# $env:AZURE_STORAGE_ACCOUNT = '<STORAGE-ACCOUNT>'
# $env:AZURE_STORAGE_KEY     = '<PASTE-KEY-HERE>'
```

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

### 4 — 📋 Example dry-run output

```
Starting purge for //myaccount/myshare | Older than 45 days (cut-off 2025-04-01 00:00:00)
logs/2025-01/app.log                   [WOULD be deleted]
logs/2025-02/app.log                   [WOULD be deleted]
logs/2025-03/app.log                   [WOULD be deleted]
backups/2025-02-14/db.bak              [WOULD be deleted]
backups/2025-03-01/db.bak              [WOULD be deleted]
----------
Matched  : 5
Deleted  : 0
NOTE: -WhatIf used – no files actually removed.
```

Once you remove `-WhatIf`, the script deletes the matched files in parallel
and the `Deleted` counter will reflect the actual removals.

---

## ⚙️ Parameters

| Parameter             | Required | Default | Description                                  |
| --------------------- | -------- | ------- | -------------------------------------------- |
| `-ResourceGroupName`  | ✔        | —       | Resource group that owns the storage account |
| `-StorageAccountName` | ✔        | —       | Storage account hosting the share            |
| `-ShareName`          | ✔        | —       | File-share to purge                          |
| `-Days`               |          | `30`    | Delete files older than *N* days             |
| `-PageSize`           |          | `5000`  | Objects per list page (service max)          |
| `-MaxConcurrent`      |          | `32`    | Parallel delete workers                      |
| `-StartPath`          |          | `''`    | Folder to begin recursion (blank = root)     |
| `-WhatIf`             |          | —       | Dry-run; no deletes executed                 |

---

## ⏰ Scheduling options

| Platform             | How to wire it                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------ |
| **Azure Automation** | Import as PS 7 runbook → store key in **secure variables** → schedule 03:00 UTC daily      |
| **GitHub Actions**   | Save key in **Secrets** → CRON `0 3 * * *` → `pwsh ./Purge-AzFileShare.ps1 …`              |
| **Task Scheduler**   | `pwsh -File Purge-AzFileShare.ps1 …` with nightly trigger; load env vars in wrapper `.bat` |

---

## 🤝 Contributing

PRs welcome! Ideas:

* Retry / back-off logic
* Exclusion patterns / globbing
* Output to CSV or Log Analytics

---

## ⚖️ License

This project is licensed under the terms of the [MIT](LICENSE) license.
See the [LICENSE](LICENSE) file for details.

