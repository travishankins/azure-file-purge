<#
  … (header left unchanged for brevity)
#>

param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)][string]$ShareName,
    [int]   $Days          = 30,
    [int]   $PageSize      = 5000,
    [int]   $MaxConcurrent = 32,
    [string]$StartPath     = '',     # NEW: folder to begin recursion
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$cutOff = (Get-Date).AddDays(-$Days)

# ──────────────────────────────────────────────────────────────────────────────
# 0. Authentication
# ──────────────────────────────────────────────────────────────────────────────
if (-not $env:AZURE_STORAGE_KEY) {
    $key = az storage account keys list `
              -g $ResourceGroupName `
              -n $StorageAccountName `
              --query "[0].value" -o tsv
    if (-not $key) { throw "Could not retrieve storage account key." }
    $env:AZURE_STORAGE_KEY = $key
}
$env:AZURE_STORAGE_ACCOUNT = $StorageAccountName

Write-Host ("Starting purge for //{0}/{1}{2} | Older than {3} days (cut-off {4})" -f `
            $StorageAccountName,$ShareName,`
            ($StartPath ? "/$StartPath" : ''),$Days,$cutOff) -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────────────────────
# 1. Globals
# ──────────────────────────────────────────────────────────────────────────────
$sem            = [System.Threading.SemaphoreSlim]::new($MaxConcurrent,$MaxConcurrent)
$deleteTasks    = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
$script:Matched = 0
$script:Deleted = 0

# ──────────────────────────────────────────────────────────────────────────────
# 2. Delete helper
# ──────────────────────────────────────────────────────────────────────────────
function Invoke-Delete {
    param([string]$RelativePath)

    $script:Matched++
    if ($WhatIf) {
        Write-Host "$RelativePath   [WOULD be deleted]" -ForegroundColor DarkYellow
        return
    }

    $sem.Wait() | Out-Null
    $deleteTasks.Add(
        [System.Threading.Tasks.Task]::Run({
            param($p,$share,$acct,$key,$semRef)
            try {
                az storage file delete `
                    --share-name  $share `
                    --path        $p `
                    --account-name $acct `
                    --account-key  $key `
                    --only-show-errors | Out-Null
            } finally {
                $semRef.Release() | Out-Null
            }
        }, @($RelativePath,$ShareName,$env:AZURE_STORAGE_ACCOUNT,$env:AZURE_STORAGE_KEY,$sem))
    )
}

# ──────────────────────────────────────────────────────────────────────────────
# 3. Recursive walker
# ──────────────────────────────────────────────────────────────────────────────
function Purge-Folder {
    param([string]$SubPath = '', [string]$Marker = '')

    do {
        $json = az storage file list `
                    --share-name  $ShareName `
                    --path        $SubPath `
                    --num-results $PageSize `
                    --marker      $Marker `
                    --only-show-errors `
                    --query "{items:[],Next:nextMarker}" `
                    -o json
        $page   = $json | ConvertFrom-Json
        $Marker = $page.Next

        foreach ($item in $page.Items) {
            $fullPath = ($SubPath ? "$SubPath/" : '') + $item.name
            if ($item.isDirectory) {
                Purge-Folder -SubPath $fullPath
            } elseif ([datetime]$item.properties.lastModified -lt $cutOff) {
                Invoke-Delete -RelativePath $fullPath
            }
        }
    } while ($Marker)
}

# ──────────────────────────────────────────────────────────────────────────────
# 4. Kick-off
# ──────────────────────────────────────────────────────────────────────────────
Purge-Folder -SubPath $StartPath   # ← now respects -StartPath

if (-not $WhatIf) {
    [System.Threading.Tasks.Task]::WaitAll($deleteTasks.ToArray())
    $script:Deleted = $deleteTasks.Count
}

# ──────────────────────────────────────────────────────────────────────────────
# 5. Summary
# ──────────────────────────────────────────────────────────────────────────────
Write-Host '----------' -ForegroundColor Gray
Write-Host ("Matched  : {0:n0}" -f $script:Matched)
Write-Host ("Deleted  : {0:n0}" -f $script:Deleted)
if ($WhatIf) { Write-Host "NOTE: -WhatIf used – no files actually removed." -ForegroundColor Green }
