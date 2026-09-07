# Azure File Share Purge

Preview or delete Azure File Share files older than a configured age.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

[Quick Start](#quick-start) | [Configuration](#configuration) | [Validation](#validation) | [Guide](GUIDE.md)

## Overview

A PowerShell script with recursive traversal, paged listing, parallel deletion, retries, and a `-WhatIf` preview.
Deletion is destructive. Validate against disposable data before scheduling a production job.

## Prerequisites

- PowerShell 7 and a supported Azure CLI version for the selected authentication mode.
- Network access and list/delete permissions on the intended share.
- A recovery plan and verified backups before enabling deletion.

## Quick Start

```text
git clone https://github.com/travishankins/azure-file-purge.git
cd azure-file-purge
pwsh -File tests/Test-Purge.ps1
```

The test mocks Azure CLI and does not contact a share. Use the [project guide](GUIDE.md) to configure authentication and run an initial `-WhatIf` preview.

## Configuration

Choose the storage account, share, optional start path, age cutoff, concurrency, and retry limit.
Prefer Entra ID or managed identity when available; keep keys and SAS tokens out of source control.

## Validation

The mock test covers pagination, recursion, filtering, missing timestamps, and the no-delete preview guard.
Verify actual CLI output, authentication, delete failures, cutoff boundaries, and throughput with disposable share data.

## Operations

Install the reviewed script in the scheduler or runbook that owns the job.
Review its exit status and failed/skipped counts. Reverting the script cannot restore deleted files.

## Security and Limitations

The privileged Azure Files role can bypass file-level permissions; scope it carefully.
No benchmark establishes a supported object count. Do not remove `-WhatIf` until the preview matches an independent inventory.

## Documentation

- [Project guide](GUIDE.md): authentication, parameters, scheduling, examples, and troubleshooting.
- [Purge script](Purge-AzFileShare.ps1): implementation and command help.

## Contributing

Open an issue or pull request with a synthetic reproduction and test results. Never include keys, SAS tokens, or private file inventories.

## License

[MIT License](LICENSE).
