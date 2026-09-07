$ErrorActionPreference = 'Stop'
$environmentNames = @('AZURE_STORAGE_ACCOUNT', 'AZURE_STORAGE_KEY', 'AZURE_STORAGE_SAS_TOKEN', 'AZURE_STORAGE_AUTH_MODE', 'AZURE_STORAGE_CONNECTION_STRING')
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$testState = @{
    ListCalls   = [System.Collections.Generic.List[object]]::new()
    DeleteCalls = 0
}

function az {
    $global:LASTEXITCODE = 0
    if ($args[0] -ne 'storage' -or $args[1] -ne 'file') {
        throw 'Unexpected CLI command'
    }
    if ($args[2] -eq 'delete') {
        $testState.DeleteCalls++
        throw 'Dry run attempted a delete'
    }
    if ($args[2] -ne 'list') { throw 'Unexpected storage operation' }
    $testState.ListCalls.Add(@($args))
    $oldTimestamp = (Get-Date).AddDays(-60).ToString('o')
    $freshTimestamp = (Get-Date).ToString('o')
    if ($args -contains '--path') {
        @(@{name = 'nested-old.txt'; type = 'file'; properties = @{lastModified = $oldTimestamp } }) | ConvertTo-Json -AsArray -Depth 5
    }
    elseif ($args -contains '--marker') {
        @(
            @{name = 'fresh.txt'; type = 'file'; properties = @{lastModified = $freshTimestamp } },
            @{name = 'unknown-time.txt'; type = 'file'; properties = @{} }
        ) | ConvertTo-Json -AsArray -Depth 5
    }
    else {
        @(
            @{name = 'old.txt'; type = 'file'; properties = @{lastModified = $oldTimestamp } },
            @{name = 'nested'; type = 'dir' },
            @{nextMarker = 'second-page' }
        ) | ConvertTo-Json -AsArray -Depth 5
    }
}

try {
    $output = & (Join-Path $PSScriptRoot '../Purge-AzFileShare.ps1') -StorageAccountName 'testaccount' -ShareName 'testshare' -AuthMode Key -AccountKey 'test-only' -Days 30 -PageSize 2 -WhatIf 6>&1 | Out-String
    if ($testState.DeleteCalls -ne 0) { throw 'Expected no deletes' }
    if ($testState.ListCalls.Count -ne 3) { throw 'Expected root, nested, and continuation list calls' }
    if ($output -notmatch 'Matched\s+:\s+2') { throw 'Expected exactly two old files' }
    if ($output -notmatch 'Skipped\s+:\s+1') { throw 'Expected missing timestamp to be skipped' }
    if ($testState.ListCalls[2] -notcontains 'second-page') { throw 'Continuation token was not forwarded' }
    Write-Output 'PASS: pagination, recursion, cutoff filtering, missing timestamps, and dry-run deletion guard'
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
