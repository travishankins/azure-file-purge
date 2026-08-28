
# 🧹 Azure File Share Purge Script
`Purge-AzFileShare.ps1`

Deletes files **older than _N_ days** (optionally within a specific sub-folder) from an Azure File Share.

---

## ✨ Highlights

|    | Feature |
| :- | :------ |
| 🔐 | **Three auth modes** — Shared Key, SAS token, or Microsoft Entra ID / **Managed Identity** |
| 🚀 | **Scales** to tens of millions of objects – streams up to 5 000 entries/page & follows continuation tokens |
| 🌳 | **Recursive** by default; optionally start lower via `-StartPath` |
| ⚡ | **Parallel deletes** (configurable) for high throughput |
| ♻️ | **Retries with back-off** on transient delete failures |
| 🔍 | **`-WhatIf`** mode prints paths **without deleting** |
| 🔁 | **Resume-safe** – rerun any time; already-deleted files are skipped |
| 🛡️ | Secrets are passed via environment variables, never on the command line |

---

## 🔐 Authentication

The script supports three credential types, selected with `-AuthMode`.

| `-AuthMode` | Credential | How to supply it |
| ----------- | ---------- | ---------------- |
| `Auto` *(default)* | Whatever is available | Resolution order: `-ManagedIdentity` → account key → SAS token → `-ResourceGroupName` (key lookup) → Entra ID login |
| `Key`   | Storage account key | `-AccountKey`, `$env:AZURE_STORAGE_KEY`, or auto-retrieved with `az storage account keys list` when `-ResourceGroupName` is supplied |
| `Sas`   | Shared Access Signature | `-SasToken` or `$env:AZURE_STORAGE_SAS_TOKEN` (leading `?` optional) |
| `Login` | Microsoft Entra ID (OAuth) | An existing `az login` session (user or service principal), or `-ManagedIdentity` to sign in with the host's managed identity |

The mode that was actually used is printed in the banner and in the final summary,
so you always know which credential the run relied on.

### Managed identity

`-ManagedIdentity` runs `az login --identity` before the purge starts. Use it on any
Azure host with an assigned identity (VM, VMSS, App Service, Container Apps, Azure
Automation, or an Azure DevOps / GitHub self-hosted runner):

```powershell
# System-assigned identity
./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs -AuthMode Login -ManagedIdentity

# User-assigned identity
./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs `
  -AuthMode Login -ManagedIdentity -ManagedIdentityClientId <CLIENT-ID>
```

If your environment already signed in (for example `azure/login` in GitHub Actions with
OIDC, or a Container App with the identity already bootstrapped), just use `-AuthMode Login`
and omit `-ManagedIdentity`.

> **Required role:** OAuth access to Azure Files uses the `--backup-intent` request flag,
> which requires the **Storage File Data Privileged Contributor** role on the storage
> account. `Storage Blob …` roles and the control-plane `Contributor` role are *not*
> sufficient for file data operations.

```bash
az role assignment create \
  --assignee <PRINCIPAL-ID> \
  --role "Storage File Data Privileged Contributor" \
  --scope $(az storage account show -g <RG> -n <ACCOUNT> --query id -o tsv)
```

> **Note:** `Login` mode is the only option when the storage account has shared-key access
> disabled (`allowSharedKeyAccess = false`). In that case `Key` and `Sas` modes fail with
> `KeyBasedAuthenticationNotPermitted`.

### SAS token

Generate a token with list + delete rights on the share:

```bash
az storage share generate-sas \
  --account-name <ACCOUNT> --name <SHARE> \
  --permissions dlrw --expiry 2026-01-01T00:00Z \
  --auth-mode login --as-user -o tsv
```

```powershell
$env:AZURE_STORAGE_SAS_TOKEN = '<TOKEN>'
./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs -AuthMode Sas
```

The token is passed to the CLI through `AZURE_STORAGE_SAS_TOKEN` rather than
`--sas-token`, which keeps it out of process command lines and prevents `cmd.exe` on
Windows from mangling the `&` separators inside the token.

---

## 🔄 How It Works

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐
│ Authenticate │────▶│ Recursive walk   │────▶│ Delete / log  │
└──────────────┘     └──────────────────┘     └───────────────┘
```

1. **Authenticate** — resolves the effective auth mode (see above) and wires the
   credential up for every `az storage file …` call.
2. **Walk** — recursively lists every directory in the share (or below `-StartPath`)
   in pages of `-PageSize` entries, following continuation markers until every file
   has been visited.
3. **Filter** — each file's `lastModified` timestamp is compared against the
   cut-off date (`now − Days`). Entries without a timestamp are skipped and counted.
4. **Delete or preview** — matched files are either printed (`-WhatIf`) or deleted in
   batches through a throttled parallel pipeline (`-MaxConcurrent` workers), with up
   to `-MaxRetries` exponential-back-off retries per file.
5. **Summarise** — a final count of matched / deleted / failed / skipped files is
   printed. The script exits with code `1` if any delete failed.

---

## 🛠️ Prerequisites

| Requirement | Notes |
|-------------|-------|
| **PowerShell 7+** | Windows · macOS · Linux · Azure Cloud Shell |
| **Azure CLI 2.60+** | Script shells out to `az storage file …`. OAuth mode needs **2.70+** for `--backup-intent` |
| **List / Delete permission** | *Either*:<br>• Shared Key<br>• SAS with `dlrw` permissions<br>• **or** the Azure role **Storage File Data Privileged Contributor** |

---

## ⚡ Quick start

### Option A — 🪪 Managed identity / Entra ID (recommended)

```powershell
az login   # or -ManagedIdentity on an Azure host

./Purge-AzFileShare.ps1 `
  -StorageAccountName <STORAGE-ACCOUNT> `
  -ShareName          <FILE-SHARE> `
  -AuthMode           Login `
  -Days               45 `
  -WhatIf
```

### Option B — 🗝️ Shared key

```powershell
$env:AZURE_STORAGE_KEY = (az storage account keys list -g <RG> -n <ACCOUNT> --query "[0].value" -o tsv)

./Purge-AzFileShare.ps1 `
  -StorageAccountName <STORAGE-ACCOUNT> `
  -ShareName          <FILE-SHARE> `
  -Days               45 `
  -WhatIf
```

Or let the script fetch the key itself by passing `-ResourceGroupName <RG>`.

### Option C — 🎟️ SAS token

```powershell
$env:AZURE_STORAGE_SAS_TOKEN = '<TOKEN>'

./Purge-AzFileShare.ps1 `
  -StorageAccountName <STORAGE-ACCOUNT> `
  -ShareName          <FILE-SHARE> `
  -AuthMode           Sas `
  -Days               45 `
  -WhatIf
```

Remove `-WhatIf` once the preview looks correct.

### 📋 Example dry-run output

```
Starting purge for //myaccount/myshare | Older than 45 days (cut-off 2025-04-01 00:00:00) | Auth: Login
logs/2025-01/app.log                   [WOULD be deleted]
logs/2025-02/app.log                   [WOULD be deleted]
logs/2025-03/app.log                   [WOULD be deleted]
backups/2025-02-14/db.bak              [WOULD be deleted]
backups/2025-03-01/db.bak              [WOULD be deleted]
----------
Auth mode: Login
Matched  : 5
Deleted  : 0
NOTE: -WhatIf used - no files actually removed.
```

---

## ⚙️ Parameters

| Parameter | Required | Default | Description |
| --------- | -------- | ------- | ----------- |
| `-StorageAccountName`       | ✔ | — | Storage account hosting the share |
| `-ShareName`                | ✔ | — | File share to purge |
| `-ResourceGroupName`        |   | — | Only needed so the account key can be auto-retrieved in `Key` mode |
| `-AuthMode`                 |   | `Auto` | `Auto`, `Key`, `Sas`, or `Login` |
| `-AccountKey`               |   | — | Storage account key (`Key` mode) |
| `-SasToken`                 |   | — | SAS token (`Sas` mode) |
| `-ManagedIdentity`          |   | — | Sign in with the host's managed identity (`Login` mode) |
| `-ManagedIdentityClientId`  |   | — | Client ID of a **user-assigned** managed identity |
| `-TenantId`                 |   | — | Entra ID tenant to sign in against |
| `-Days`                     |   | `30` | Delete files older than *N* days |
| `-PageSize`                 |   | `5000` | Objects per list page (service max) |
| `-MaxConcurrent`            |   | `32` | Parallel delete workers |
| `-MaxRetries`               |   | `3` | Retries per failed delete (exponential back-off) |
| `-StartPath`                |   | `''` | Folder to begin recursion (blank = share root) |
| `-WhatIf`                   |   | — | Dry-run; no deletes executed |

**Exit codes:** `0` on success, `1` if one or more deletes failed.

---

## ⏰ Scheduling options

| Platform | How to wire it |
| -------- | -------------- |
| **Azure Automation**   | Import as a PS 7 runbook → enable the runbook's **managed identity** → grant it *Storage File Data Privileged Contributor* → run with `-AuthMode Login -ManagedIdentity` (no secrets to store) |
| **Azure VM / VMSS / Container Apps** | Assign a managed identity → `-AuthMode Login -ManagedIdentity` |
| **GitHub Actions**     | Use `azure/login` with OIDC federated credentials → `-AuthMode Login`. CRON `0 3 * * *` → `pwsh ./Purge-AzFileShare.ps1 …` |
| **Task Scheduler**     | `pwsh -File Purge-AzFileShare.ps1 …` with a nightly trigger; set `AZURE_STORAGE_KEY` / `AZURE_STORAGE_SAS_TOKEN` in a wrapper script |

---

## 🩺 Troubleshooting

| Symptom | Likely cause / fix |
| ------- | ------------------ |
| `KeyBasedAuthenticationNotPermitted` | Shared key is disabled on the account — use `-AuthMode Login` |
| `AuthorizationPermissionMismatch` in `Login` mode | Missing the **Storage File Data Privileged Contributor** role, or the assignment has not propagated yet (allow a few minutes) |
| `The request may be blocked by network rules` | The account has `publicNetworkAccess` disabled or an IP firewall — run from an allowed network / private endpoint |
| `unrecognized arguments: --backup-intent` | Azure CLI is too old — upgrade to 2.70+ |
| `AuthMode 'Login' requires an active Azure CLI session` | Run `az login`, or pass `-ManagedIdentity` |

---

## 🤝 Contributing

PRs welcome! Ideas:

* Exclusion patterns / globbing
* Output to CSV or Log Analytics
* Native REST/SDK backend to avoid the per-file `az` process cost

---

## ⚖️ License

This project is licensed under the terms of the [MIT](LICENSE) license.
See the [LICENSE](LICENSE) file for details.
