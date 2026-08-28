<#
.SYNOPSIS
    Deletes files older than N days from an Azure File Share.

.DESCRIPTION
    Recursively walks an Azure File Share (or a sub-folder of it) and deletes every
    file whose LastModified timestamp is older than the cut-off date.

    Three authentication modes are supported:

      Key    - Shared Key (storage account key). Supplied via -AccountKey, the
               AZURE_STORAGE_KEY environment variable, or auto-retrieved with
               'az storage account keys list' when -ResourceGroupName is given.
      Sas    - Shared Access Signature. Supplied via -SasToken or the
               AZURE_STORAGE_SAS_TOKEN environment variable.
      Login  - Microsoft Entra ID (OAuth). Works with an interactive 'az login',
               a service principal, or a managed identity (-ManagedIdentity).
               Uses '--auth-mode login --backup-intent', which requires the
               'Storage File Data Privileged Contributor' role.

    'Auto' (the default) picks the first mode that has usable credentials, in the
    order Key -> Sas -> Login.

.EXAMPLE
    ./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs -Days 45 -WhatIf
    Auto-detects credentials and previews what would be deleted.

.EXAMPLE
    ./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs -AuthMode Login -ManagedIdentity
    Signs in with the VM/container system-assigned managed identity and purges.

.EXAMPLE
    ./Purge-AzFileShare.ps1 -StorageAccountName sa1 -ShareName logs -AuthMode Sas -SasToken $env:SAS
    Uses an explicit SAS token.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)][string]$ShareName,

    # Only needed when the account key has to be auto-retrieved (AuthMode 'Key').
    [string]$ResourceGroupName,

    [ValidateSet('Auto','Key','Sas','Login')]
    [string]$AuthMode = 'Auto',

    # AuthMode 'Key'   - falls back to $env:AZURE_STORAGE_KEY
    [string]$AccountKey,

    # AuthMode 'Sas'   - falls back to $env:AZURE_STORAGE_SAS_TOKEN
    [string]$SasToken,

    # AuthMode 'Login' - sign in with a managed identity before running.
    [switch]$ManagedIdentity,
    # Client ID (or resource ID) of a user-assigned managed identity.
    [string]$ManagedIdentityClientId,
    # Entra ID tenant to sign in against (rarely needed).
    [string]$TenantId,

    [ValidateRange(0, 36500)][int]$Days          = 30,
    [ValidateRange(1, 5000)] [int]$PageSize      = 5000,
    [ValidateRange(1, 512)]  [int]$MaxConcurrent = 32,
    [ValidateRange(0, 10)]   [int]$MaxRetries    = 3,

    [string]$StartPath = '',

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$cutOff = (Get-Date).AddDays(-$Days)

# ──────────────────────────────────────────────────────────────────────────────
# 0. Authentication
# ──────────────────────────────────────────────────────────────────────────────
function Test-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI ('az') was not found on PATH. Install Azure CLI 2.60+ and try again."
    }
}

function Connect-ManagedIdentity {
    param([string]$ClientId, [string]$Tenant)

    $loginArgs = @('login', '--identity', '--only-show-errors', '--output', 'none')
    if ($ClientId) { $loginArgs += @('--client-id', $ClientId) }
    if ($Tenant)   { $loginArgs += @('--tenant',    $Tenant) }

    Write-Host ("Signing in with {0} managed identity..." -f ($ClientId ? 'user-assigned' : 'system-assigned')) -ForegroundColor Cyan
    az @loginArgs
    if ($LASTEXITCODE -ne 0) { throw "Managed identity sign-in failed (az login --identity exit code $LASTEXITCODE)." }
}

function Get-AccountKey {
    param([string]$ResourceGroup, [string]$Account)

    if (-not $ResourceGroup) {
        throw "AuthMode 'Key' requires -AccountKey, `$env:AZURE_STORAGE_KEY, or -ResourceGroupName so the key can be retrieved."
    }

    Write-Verbose "Retrieving account key for '$Account' from resource group '$ResourceGroup'."
    $key = az storage account keys list -g $ResourceGroup -n $Account --query "[0].value" -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not retrieve storage account key for '$Account'." }
    return $key.Trim()
}

function Resolve-AuthArguments {
    <#
        Selects the effective auth mode and wires the credential up for every
        subsequent 'az storage file …' call.

        Shared Key and SAS credentials are handed over through the environment
        variables the Azure CLI already understands rather than through command-line
        switches. That keeps secrets out of process command lines, and - importantly
        on Windows - avoids cmd.exe mangling the '&' characters inside a SAS token
        when it launches az.cmd. Only the OAuth switches are passed as arguments.
    #>
    param([string]$Mode)

    $key = if ($AccountKey) { $AccountKey } else { $env:AZURE_STORAGE_KEY }
    $sas = if ($SasToken)   { $SasToken }   else { $env:AZURE_STORAGE_SAS_TOKEN }

    if ($Mode -eq 'Auto') {
        $Mode = if ($ManagedIdentity)      { 'Login' }
                elseif ($key)              { 'Key' }
                elseif ($sas)              { 'Sas' }
                elseif ($ResourceGroupName){ 'Key' }
                else                       { 'Login' }
        Write-Verbose "AuthMode 'Auto' resolved to '$Mode'."
    }

    switch ($Mode) {
        'Key' {
            if (-not $key) { $key = Get-AccountKey -ResourceGroup $ResourceGroupName -Account $StorageAccountName }
            $env:AZURE_STORAGE_ACCOUNT           = $StorageAccountName
            $env:AZURE_STORAGE_KEY               = $key
            $env:AZURE_STORAGE_SAS_TOKEN         = $null
            $env:AZURE_STORAGE_AUTH_MODE         = $null
            $env:AZURE_STORAGE_CONNECTION_STRING = $null
            $authArgs = @()
        }
        'Sas' {
            if (-not $sas) {
                throw "AuthMode 'Sas' requires -SasToken or `$env:AZURE_STORAGE_SAS_TOKEN."
            }
            $env:AZURE_STORAGE_ACCOUNT           = $StorageAccountName
            # az accepts the token with or without the leading '?'; normalise it away.
            $env:AZURE_STORAGE_SAS_TOKEN         = $sas.TrimStart('?')
            $env:AZURE_STORAGE_KEY               = $null
            $env:AZURE_STORAGE_AUTH_MODE         = $null
            $env:AZURE_STORAGE_CONNECTION_STRING = $null
            $authArgs = @()
        }
        'Login' {
            if ($ManagedIdentity) { Connect-ManagedIdentity -ClientId $ManagedIdentityClientId -Tenant $TenantId }

            az account show --only-show-errors --output none 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "AuthMode 'Login' requires an active Azure CLI session. Run 'az login', or pass -ManagedIdentity."
            }

            # Shared-key/SAS environment variables take precedence inside the CLI and
            # would silently defeat OAuth, so hide them from the child processes.
            $env:AZURE_STORAGE_KEY               = $null
            $env:AZURE_STORAGE_SAS_TOKEN         = $null
            $env:AZURE_STORAGE_CONNECTION_STRING = $null
            $env:AZURE_STORAGE_ACCOUNT           = $StorageAccountName

            # --backup-intent is mandatory for OAuth against Azure Files and requires
            # the 'Storage File Data Privileged Contributor' role.
            $authArgs = @('--auth-mode', 'login', '--backup-intent')
        }
    }

    return [pscustomobject]@{ Mode = $Mode; Args = $authArgs }
}

Test-AzCli
$auth     = Resolve-AuthArguments -Mode $AuthMode
$authArgs = $auth.Args

Write-Host ("Starting purge for //{0}/{1}{2} | Older than {3} days (cut-off {4}) | Auth: {5}" -f `
            $StorageAccountName, $ShareName, ($StartPath ? "/$StartPath" : ''), `
            $Days, $cutOff, $auth.Mode) -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────────────────────
# 1. Globals
# ──────────────────────────────────────────────────────────────────────────────
$pending        = [System.Collections.Generic.List[string]]::new()
$flushThreshold = [Math]::Max($MaxConcurrent * 20, 1000)
$script:Matched = 0
$script:Deleted = 0
$script:Failed  = 0
$script:Skipped = 0

# ──────────────────────────────────────────────────────────────────────────────
# 2. Delete helpers
# ──────────────────────────────────────────────────────────────────────────────
function Invoke-DeleteBatch {
    <#
        Deletes a batch of files in parallel. Runs on PowerShell 7 runspaces with a
        throttle of -MaxConcurrent, and retries transient failures with back-off.
    #>
    param([string[]]$Paths)

    if (-not $Paths -or $Paths.Count -eq 0) { return }

    $results = $Paths | ForEach-Object -ThrottleLimit $MaxConcurrent -Parallel {
        $path       = $_
        $share      = $using:ShareName
        $account    = $using:StorageAccountName
        $commonArgs = $using:authArgs
        $maxRetries = $using:MaxRetries

        for ($attempt = 0; $attempt -le $maxRetries; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Milliseconds ([Math]::Min(8000, 250 * [Math]::Pow(2, $attempt))) }

            $stdErr = az storage file delete --account-name $account --share-name $share --path $path @commonArgs --only-show-errors 2>&1 |
                      Out-String
            if ($LASTEXITCODE -eq 0) {
                [pscustomobject]@{ Path = $path; Success = $true; Error = $null }
                return
            }
        }

        [pscustomobject]@{ Path = $path; Success = $false; Error = $stdErr.Trim() }
    }

    foreach ($r in $results) {
        if ($r.Success) {
            $script:Deleted++
        } else {
            $script:Failed++
            Write-Warning ("Failed to delete '{0}': {1}" -f $r.Path, $r.Error)
        }
    }
}

function Add-Deletion {
    param([string]$RelativePath)

    $script:Matched++

    if ($WhatIf) {
        Write-Host "$RelativePath   [WOULD be deleted]" -ForegroundColor DarkYellow
        return
    }

    $pending.Add($RelativePath)
    if ($pending.Count -ge $flushThreshold) {
        Invoke-DeleteBatch -Paths $pending.ToArray()
        $pending.Clear()
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# 3. Listing / recursive walker
# ──────────────────────────────────────────────────────────────────────────────
function Get-ShareEntry {
    <#
        Returns one page of entries plus the continuation marker. 'az storage file list'
        emits a JSON array whose trailing element carries 'nextMarker' when more data
        is available, so the two shapes are separated here.
    #>
    param([string]$SubPath, [string]$Marker)

    $listArgs = @(
        '--account-name', $StorageAccountName,
        '--share-name',   $ShareName,
        '--num-results',  $PageSize
    ) + $authArgs + @('--only-show-errors', '-o', 'json')

    if ($SubPath) { $listArgs += @('--path',   $SubPath) }
    if ($Marker)  { $listArgs += @('--marker', $Marker) }

    $raw = az storage file list @listArgs
    if ($LASTEXITCODE -ne 0) { throw "Listing '$ShareName/$SubPath' failed (az exit code $LASTEXITCODE)." }

    $parsed = if ($raw) { $raw | ConvertFrom-Json } else { @() }
    $items  = @()
    $next   = $null

    foreach ($entry in @($parsed)) {
        if ($null -eq $entry) { continue }
        $props = $entry.PSObject.Properties.Name
        if ($props -contains 'nextMarker') { $next = $entry.nextMarker }
        if ($props -contains 'name')       { $items += $entry }
    }

    return [pscustomobject]@{ Items = $items; NextMarker = $next }
}

function Test-IsDirectory {
    param($Item)

    # Newer CLI versions return type = 'dir' | 'file'; older ones return isDirectory.
    if ($Item.PSObject.Properties.Name -contains 'type' -and $Item.type) { return $Item.type -eq 'dir' }
    return [bool]$Item.isDirectory
}

function Invoke-PurgeFolder {
    param([string]$SubPath = '')

    $marker = $null
    do {
        $page   = Get-ShareEntry -SubPath $SubPath -Marker $marker
        $marker = $page.NextMarker

        foreach ($item in $page.Items) {
            $fullPath = ($SubPath ? "$SubPath/" : '') + $item.name

            if (Test-IsDirectory -Item $item) {
                Invoke-PurgeFolder -SubPath $fullPath
                continue
            }

            $lastModified = $item.properties.lastModified
            if (-not $lastModified) {
                $script:Skipped++
                Write-Verbose "No lastModified for '$fullPath'; skipping."
                continue
            }

            if ([datetime]$lastModified -lt $cutOff) { Add-Deletion -RelativePath $fullPath }
        }
    } while ($marker)
}

# ──────────────────────────────────────────────────────────────────────────────
# 4. Kick-off
# ──────────────────────────────────────────────────────────────────────────────
Invoke-PurgeFolder -SubPath $StartPath

if (-not $WhatIf -and $pending.Count -gt 0) {
    Invoke-DeleteBatch -Paths $pending.ToArray()
    $pending.Clear()
}

# ──────────────────────────────────────────────────────────────────────────────
# 5. Summary
# ──────────────────────────────────────────────────────────────────────────────
Write-Host '----------' -ForegroundColor Gray
Write-Host ("Auth mode: {0}"    -f $auth.Mode)
Write-Host ("Matched  : {0:n0}" -f $script:Matched)
Write-Host ("Deleted  : {0:n0}" -f $script:Deleted)
if ($script:Failed  -gt 0) { Write-Host ("Failed   : {0:n0}" -f $script:Failed)  -ForegroundColor Red }
if ($script:Skipped -gt 0) { Write-Host ("Skipped  : {0:n0}" -f $script:Skipped) -ForegroundColor DarkGray }
if ($WhatIf) { Write-Host "NOTE: -WhatIf used - no files actually removed." -ForegroundColor Green }

if ($script:Failed -gt 0) { exit 1 }
