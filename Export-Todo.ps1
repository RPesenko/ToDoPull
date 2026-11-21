[CmdletBinding()]
param(
    # Include completed tasks in the JSON export. By default only active tasks are exported.
    [switch]$IncludeCompleted
)

$ErrorActionPreference = 'Stop'

$ScriptVersion = '0.3.0'
$GraphApiVersion = 'v1.0'
$StartTime = Get-Date
$ExportTimestamp = $StartTime.ToUniversalTime().ToString('o')
$OutputFolder = Join-Path $PSScriptRoot 'output'
$LogFolder = Join-Path $PSScriptRoot 'logs'

New-Item -ItemType Directory -Path $OutputFolder, $LogFolder -Force | Out-Null

$LogFile = Join-Path $LogFolder ("export-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $entry = '{0} - {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $entry -Encoding utf8
    Write-Host $entry
}

function Get-GraphErrorDetails {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $details = [System.Collections.Generic.List[string]]::new()
    $details.Add($ErrorRecord.Exception.ToString())

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $details.Add("Graph error details: $($ErrorRecord.ErrorDetails.Message)")
    }

    return ($details -join [Environment]::NewLine)
}

function Test-TransientGraphError {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null
    try {
        if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
            $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode
        }
    }
    catch {
        # Some Graph SDK response types do not expose StatusCode as a castable value.
    }

    # Retry throttling, timeouts, server errors, and transport failures without an HTTP status.
    return ($null -eq $statusCode -or $statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500)
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [ValidateRange(1, 3)]
        [int]$MaximumAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            return Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        }
        catch {
            $errorDetails = Get-GraphErrorDetails -ErrorRecord $_
            Write-Log ("Graph request failed (attempt {0}/{1}) for {2}: {3}" -f $attempt, $MaximumAttempts, $Uri, $errorDetails)

            if ($attempt -ge $MaximumAttempts -or -not (Test-TransientGraphError -ErrorRecord $_)) {
                throw
            }

            $delaySeconds = [Math]::Pow(2, $attempt)
            Write-Log ("Transient Graph failure; retrying in {0} seconds." -f $delaySeconds)
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Get-AllGraphPages {
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri

    while ($nextUri) {
        $response = Invoke-GraphRequestWithRetry -Uri $nextUri
        if ($null -ne $response.value) {
            foreach ($item in $response.value) {
                $results.Add($item)
            }
        }
        $nextUri = $response.'@odata.nextLink'
    }

    return ,$results.ToArray()
}

function ConvertTo-ExportTask {
    param(
        [Parameter(Mandatory)]
        $Task
    )

    return [ordered]@{
        id                   = $Task.id
        title                = $Task.title
        status               = $Task.status
        importance           = $Task.importance
        createdDateTime      = $Task.createdDateTime
        lastModifiedDateTime = $Task.lastModifiedDateTime
        dueDateTime          = $Task.dueDateTime
        completedDateTime    = $Task.completedDateTime
        categories           = @($Task.categories)
        body                 = $Task.body.content
        hasAttachments       = $Task.hasAttachments
        isReminderOn         = $Task.isReminderOn
    }
}

Write-Log "Starting ToDo export v$ScriptVersion (IncludeCompleted: $([bool]$IncludeCompleted))"

try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Connect-MgGraph -Scopes 'Tasks.Read', 'User.Read' -NoWelcome -ErrorAction Stop
    Write-Log 'Authentication successful; connected to Microsoft Graph.'

    $listsUri = "https://graph.microsoft.com/$GraphApiVersion/me/todo/lists"
    $lists = Get-AllGraphPages -Uri $listsUri
    Write-Log "List discovery complete: $($lists.Count) list(s) found."
}
catch {
    Write-Log ("Unable to authenticate or discover To Do lists: {0}" -f (Get-GraphErrorDetails -ErrorRecord $_))
    throw
}

$exportLists = [System.Collections.Generic.List[object]]::new()
$failedLists = [System.Collections.Generic.List[object]]::new()
$totalActiveTasks = 0
$totalCompletedTasks = 0
$totalSkippedCompletedTasks = 0

foreach ($list in $lists) {
    $listName = [string]$list.displayName
    Write-Log "Processing list: $listName"

    try {
        $escapedListId = [Uri]::EscapeDataString([string]$list.id)
        $taskUri = "https://graph.microsoft.com/$GraphApiVersion/me/todo/lists/$escapedListId/tasks"
        $tasks = Get-AllGraphPages -Uri $taskUri
        $exportedTasks = [System.Collections.Generic.List[object]]::new()
        $activeInList = 0
        $completedInList = 0

        foreach ($task in $tasks) {
            if ($task.status -eq 'completed') {
                if ($IncludeCompleted) {
                    $exportedTasks.Add((ConvertTo-ExportTask -Task $task))
                    $completedInList++
                }
                else {
                    $totalSkippedCompletedTasks++
                }
                continue
            }

            $exportedTasks.Add((ConvertTo-ExportTask -Task $task))
            $activeInList++
        }

        $exportLists.Add([ordered]@{
            id        = $list.id
            name      = $listName
            taskCount = $exportedTasks.Count
            tasks     = @($exportedTasks.ToArray())
        })

        $totalActiveTasks += $activeInList
        $totalCompletedTasks += $completedInList
        Write-Log ("  Task counts: {0} active, {1} completed exported, {2} total exported." -f $activeInList, $completedInList, $exportedTasks.Count)
    }
    catch {
        $errorDetails = Get-GraphErrorDetails -ErrorRecord $_
        Write-Log ("  Failed to process list '{0}' ({1}): {2}" -f $listName, $list.id, $errorDetails)
        $failedLists.Add([ordered]@{
            id    = $list.id
            name  = $listName
            error = $errorDetails
        })
    }
}

$durationSeconds = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
$largestList = $null
$largestListTaskCount = 0
$taskTotals = 0

foreach ($exportedList in $exportLists) {
    $taskTotals += $exportedList.taskCount
    if ($exportedList.taskCount -gt $largestListTaskCount) {
        $largestList = $exportedList.name
        $largestListTaskCount = $exportedList.taskCount
    }
}

$averageTasksPerList = if ($exportLists.Count -gt 0) {
    [Math]::Round(($taskTotals / $exportLists.Count), 2)
}
else {
    0
}

$export = [ordered]@{
    scriptVersion          = $ScriptVersion
    exportTimestamp        = $ExportTimestamp
    graphApiVersion        = $GraphApiVersion
    listCount              = $lists.Count
    activeTaskCount        = $totalActiveTasks
    completedTaskCount     = $totalCompletedTasks
    exportDurationSeconds  = $durationSeconds
    summary                = [ordered]@{
        largestList             = $largestList
        largestListTaskCount    = $largestListTaskCount
        averageTasksPerList     = $averageTasksPerList
        failedListCount         = $failedLists.Count
        failedLists             = @($failedLists.ToArray())
        skippedCompletedCount   = $totalSkippedCompletedTasks
    }
    lists                  = @($exportLists.ToArray())
}

$fileTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputFile = Join-Path $OutputFolder "todo-export-$fileTimestamp.json"

try {
    $export | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $outputFile -Encoding utf8
    $null = Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Log 'JSON validation successful.'
}
catch {
    Write-Log ("Export writing or JSON validation failed: {0}" -f (Get-GraphErrorDetails -ErrorRecord $_))
    throw
}

Write-Log ("Elapsed duration: {0:N2} seconds." -f $durationSeconds)
Write-Log "Output filename: $outputFile"
Write-Log ("Export complete: {0} active, {1} completed, {2} failed list(s)." -f $totalActiveTasks, $totalCompletedTasks, $failedLists.Count)

Write-Host ''
Write-Host '==================================' -ForegroundColor Cyan
Write-Host 'ToDoPull Export Complete' -ForegroundColor Green
Write-Host "Version: $ScriptVersion"
Write-Host "Lists discovered: $($lists.Count)"
Write-Host "Active tasks: $totalActiveTasks"
Write-Host "Completed tasks exported: $totalCompletedTasks"
Write-Host "Completed tasks skipped: $totalSkippedCompletedTasks"
Write-Host "Failed lists: $($failedLists.Count)"
Write-Host ("Duration: {0:N2} seconds" -f $durationSeconds)
Write-Host "Output: $outputFile"
Write-Host "Log: $LogFile"
Write-Host '==================================' -ForegroundColor Cyan
