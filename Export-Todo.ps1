# Export-Todo.ps1
# Version 0.2.0

$ErrorActionPreference = "Stop"

$ScriptVersion = "0.2.0"
$StartTime = Get-Date

$OutputFolder = Join-Path $PSScriptRoot "output"
$LogFolder = Join-Path $PSScriptRoot "logs"

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null

$LogFile = Join-Path `
    $LogFolder `
    ("export-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $entry = "$timestamp - $Message"

    $entry | Tee-Object -FilePath $LogFile -Append
}

function Get-AllGraphPages {
    param([string]$Uri)

    $results = @()

    do {
        $response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $Uri

        if ($response.value) {
            $results += @($response.value)
        }

        $Uri = $response.'@odata.nextLink'

    } while ($Uri)

    return ,$results
}

Write-Log "Starting ToDo export v$ScriptVersion"

Import-Module Microsoft.Graph.Authentication

Connect-MgGraph `
    -Scopes "Tasks.Read","User.Read" `
    -NoWelcome

Write-Log "Connected to Microsoft Graph"

$Lists = Get-AllGraphPages `
    -Uri "https://graph.microsoft.com/v1.0/me/todo/lists"

Write-Log "Lists discovered: $($Lists.Count)"

$TotalActiveTasks = 0
$TotalCompletedTasks = 0

$Export = [ordered]@{
    exportTimestamp   = (Get-Date).ToUniversalTime().ToString("o")
    scriptVersion     = $ScriptVersion
    graphApiVersion   = "v1.0"
    generatedBy       = "ToDoPull"
    listCount         = $Lists.Count
    activeTaskCount   = 0
    completedSkipped  = 0
    lists             = @()
}

foreach ($List in $Lists) {

    Write-Log "Processing list: $($List.displayName)"

    $TaskUri = "https://graph.microsoft.com/v1.0/me/todo/lists/$($List.id)/tasks"

    $Tasks = Get-AllGraphPages `
        -Uri $TaskUri

    $ActiveTasks = @()

    foreach ($Task in $Tasks) {

        if ($Task.status -eq "completed") {

            $TotalCompletedTasks++

            continue
        }

        $ActiveTasks += [ordered]@{
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

        $TotalActiveTasks++
    }

    $Export.lists += [ordered]@{
        id        = $List.id
        name      = $List.displayName
        taskCount = $ActiveTasks.Count
        tasks     = @($ActiveTasks)
    }

    Write-Log "  Active tasks exported: $($ActiveTasks.Count)"
}

$Export.activeTaskCount = $TotalActiveTasks
$Export.completedSkipped = $TotalCompletedTasks

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$OutputFile = Join-Path `
    $OutputFolder `
    "todo-export-$Timestamp.json"

$Export |
    ConvertTo-Json -Depth 50 |
    Set-Content `
        -Path $OutputFile `
        -Encoding UTF8

# Validation

try {

    $null = Get-Content $OutputFile -Raw |
        ConvertFrom-Json

    Write-Log "JSON validation successful"
}
catch {

    Write-Log "JSON validation FAILED"
    throw
}

$Duration = (
    New-TimeSpan `
        -Start $StartTime `
        -End (Get-Date)
).TotalSeconds

Write-Log "Export complete"
Write-Log "Output file : $OutputFile"
Write-Log "Active tasks: $TotalActiveTasks"
Write-Log "Skipped completed tasks: $TotalCompletedTasks"
Write-Log ("Duration: {0:N2} sec" -f $Duration)

Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "ToDoPull Export Complete" -ForegroundColor Green
Write-Host "Version: $ScriptVersion"
Write-Host "Lists: $($Lists.Count)"
Write-Host "Active Tasks: $TotalActiveTasks"
Write-Host "Skipped Completed: $TotalCompletedTasks"
Write-Host "Output: $OutputFile"
Write-Host "Log: $LogFile"
Write-Host "==================================" -ForegroundColor Cyan