[CmdletBinding()]
param(
    # Include completed tasks in the JSON export. By default only active tasks are exported.
    [switch]$IncludeCompleted,
    # Also render the exported data as a Markdown document.
    [switch]$Markdown
)

$ScriptVersion = '0.5.0'
$GraphApiVersion = 'v1.0'

function Invoke-ToDoExport {
    param(
        [switch]$IncludeCompleted,
        [switch]$Markdown,
        [string]$ScriptRoot = $PSScriptRoot,
        [switch]$NoBanner
    )

    $ErrorActionPreference = 'Stop'
    $StartTime = Get-Date
    $ExportTimestamp = $StartTime.ToUniversalTime().ToString('o')
    $OutputFolder = Join-Path $ScriptRoot 'output'
    $LogFolder = Join-Path $ScriptRoot 'logs'

    New-Item -ItemType Directory -Path $OutputFolder, $LogFolder -Force | Out-Null

    $script:LogFile = Join-Path $LogFolder ("export-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    function Write-Log {
        param(
            [Parameter(Mandatory)]
            [string]$Message
        )

        $zoneCode = Get-LocalTimeZoneCode
        $zoneSuffix = if ($zoneCode) { ' ' + $zoneCode } else { '' }
        $entry = '{0}{1} - {2}' -f (Get-Date -Format 'yyyy-MM-dd h:mm:ss tt'), $zoneSuffix, $Message
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

        $normalizedBody = $null
        if ($null -ne $Task.body) {
            if ($Task.body -is [string]) {
                $normalizedBody = [string]$Task.body
            }
            else {
                $contentProperty = $Task.body.PSObject.Properties['content']
                if ($null -ne $contentProperty) {
                    $normalizedBody = [string]$contentProperty.Value
                }
                elseif ($Task.body -is [hashtable] -and $Task.body.ContainsKey('content')) {
                    $normalizedBody = [string]$Task.body['content']
                }
                else {
                    $normalizedBody = [string]$Task.body
                }
            }
        }

        $normalizedDueDateTime = $null
        $dueTimeZone = $null
        if ($null -ne $Task.dueDateTime) {
            if ($Task.dueDateTime -is [string]) {
                $normalizedDueDateTime = [string]$Task.dueDateTime
            }
            elseif ($Task.dueDateTime.PSObject.Properties['dateTime']) {
                $normalizedDueDateTime = [string]$Task.dueDateTime.PSObject.Properties['dateTime'].Value
                if ($Task.dueDateTime.PSObject.Properties['timeZone']) {
                    $dueTimeZone = [string]$Task.dueDateTime.PSObject.Properties['timeZone'].Value
                }
            }
            elseif ($Task.dueDateTime -is [hashtable] -and $Task.dueDateTime.ContainsKey('dateTime')) {
                $normalizedDueDateTime = [string]$Task.dueDateTime['dateTime']
                if ($Task.dueDateTime.ContainsKey('timeZone')) {
                    $dueTimeZone = [string]$Task.dueDateTime['timeZone']
                }
            }
        }

        $normalizedStartDateTime = $null
        $startTimeZone = $null
        if ($null -ne $Task.startDateTime) {
            if ($Task.startDateTime -is [string]) {
                $normalizedStartDateTime = [string]$Task.startDateTime
            }
            elseif ($Task.startDateTime.PSObject.Properties['dateTime']) {
                $normalizedStartDateTime = [string]$Task.startDateTime.PSObject.Properties['dateTime'].Value
                if ($Task.startDateTime.PSObject.Properties['timeZone']) {
                    $startTimeZone = [string]$Task.startDateTime.PSObject.Properties['timeZone'].Value
                }
            }
            elseif ($Task.startDateTime -is [hashtable] -and $Task.startDateTime.ContainsKey('dateTime')) {
                $normalizedStartDateTime = [string]$Task.startDateTime['dateTime']
                if ($Task.startDateTime.ContainsKey('timeZone')) {
                    $startTimeZone = [string]$Task.startDateTime['timeZone']
                }
            }
        }

        $normalizedReminderDateTime = $null
        $reminderTimeZone = $null
        if ($null -ne $Task.reminderDateTime) {
            if ($Task.reminderDateTime -is [string]) {
                $normalizedReminderDateTime = [string]$Task.reminderDateTime
            }
            elseif ($Task.reminderDateTime.PSObject.Properties['dateTime']) {
                $normalizedReminderDateTime = [string]$Task.reminderDateTime.PSObject.Properties['dateTime'].Value
                if ($Task.reminderDateTime.PSObject.Properties['timeZone']) {
                    $reminderTimeZone = [string]$Task.reminderDateTime.PSObject.Properties['timeZone'].Value
                }
            }
            elseif ($Task.reminderDateTime -is [hashtable] -and $Task.reminderDateTime.ContainsKey('dateTime')) {
                $normalizedReminderDateTime = [string]$Task.reminderDateTime['dateTime']
                if ($Task.reminderDateTime.ContainsKey('timeZone')) {
                    $reminderTimeZone = [string]$Task.reminderDateTime['timeZone']
                }
            }
        }

        $normalizedRecurrence = $null
        if ($null -ne $Task.recurrence) {
            $pattern = $null
            $range = $null

            if ($Task.recurrence.PSObject.Properties['pattern']) {
                $pattern = $Task.recurrence.PSObject.Properties['pattern'].Value
            }
            elseif ($Task.recurrence -is [hashtable] -and $Task.recurrence.ContainsKey('pattern')) {
                $pattern = $Task.recurrence['pattern']
            }

            if ($Task.recurrence.PSObject.Properties['range']) {
                $range = $Task.recurrence.PSObject.Properties['range'].Value
            }
            elseif ($Task.recurrence -is [hashtable] -and $Task.recurrence.ContainsKey('range')) {
                $range = $Task.recurrence['range']
            }

            $normalizedRecurrence = [ordered]@{
                pattern = if ($null -ne $pattern) { $pattern } else { $null }
                range   = if ($null -ne $range) { $range } else { $null }
            }
        }

        return [ordered]@{
            id                   = $Task.id
            title                = $Task.title
            status               = $Task.status
            importance           = $Task.importance
            createdDateTime      = ConvertTo-DisplayTime -Value $Task.createdDateTime -SourceTimeZone 'UTC'
            lastModifiedDateTime = ConvertTo-DisplayTime -Value $Task.lastModifiedDateTime -SourceTimeZone 'UTC'
            dueDateTime          = ConvertTo-DisplayTime -Value $normalizedDueDateTime -SourceTimeZone $dueTimeZone
            completedDateTime    = ConvertTo-DisplayTime -Value $Task.completedDateTime -SourceTimeZone 'UTC'
            startDateTime        = ConvertTo-DisplayTime -Value $normalizedStartDateTime -SourceTimeZone $startTimeZone
            reminderDateTime     = ConvertTo-DisplayTime -Value $normalizedReminderDateTime -SourceTimeZone $reminderTimeZone
            bodyLastModifiedDateTime = ConvertTo-DisplayTime -Value $Task.bodyLastModifiedDateTime -SourceTimeZone 'UTC'
            recurrence           = $normalizedRecurrence
            categories           = @($Task.categories)
            body                 = $normalizedBody
            hasAttachments       = $Task.hasAttachments
            isReminderOn         = $Task.isReminderOn
        }
    }

    function ConvertTo-MarkdownText {
        param(
            [AllowNull()][string]$Text,
            [string]$ContinuationIndent = ''
        )

        if ($null -eq $Text) {
            return ''
        }

        $escaped = $Text.Replace('\', '\\')
        foreach ($character in @('`', '*', '_', '{', '}', '[', ']', '(', ')', '<', '>', '#', '+', '-', '.', '!', '|')) {
            $escaped = $escaped.Replace($character, '\' + $character)
        }

        $escaped = $escaped.Replace("`r`n", "`n").Replace("`r", "`n")
        if ($ContinuationIndent) {
            $escaped = $escaped.Replace("`n", [Environment]::NewLine + $ContinuationIndent)
        }

        return $escaped
    }

    function ConvertTo-MarkdownDocument {
        param([Parameter(Mandatory)]$ExportData)

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# Microsoft To Do Export')
        $lines.Add('')
        $lines.Add("- Exported: $(ConvertTo-DisplayTime -Value $ExportData.exportTimestamp -SourceTimeZone 'UTC')")
        $lines.Add("- Active tasks: $($ExportData.activeTaskCount)")
        $lines.Add("- Completed tasks: $($ExportData.completedTaskCount)")
        $lines.Add("- Failed lists: $($ExportData.summary.failedListCount)")
        $lines.Add('')

        foreach ($list in $ExportData.lists) {
            $lines.Add("## $(ConvertTo-MarkdownText -Text ([string]$list.name))")
            $lines.Add('')

            if ($list.tasks.Count -eq 0) {
                $lines.Add('_No tasks._')
                $lines.Add('')
                continue
            }

            foreach ($task in $list.tasks) {
                $checkbox = if ($task.status -eq 'completed') { '[x]' } else { '[ ]' }
                $lines.Add("- $checkbox $(ConvertTo-MarkdownText -Text ([string]$task.title))")

                if ($task.dueDateTime) {
                    $dueText = ConvertTo-MarkdownText -Text ([string]$task.dueDateTime)
                    $lines.Add("  - Due: $dueText")
                }
                if ($task.categories.Count -gt 0) {
                    $categoryText = ($task.categories | ForEach-Object { ConvertTo-MarkdownText -Text ([string]$_) }) -join ', '
                    $lines.Add("  - Categories: $categoryText")
                }
                if ($task.body) {
                    $bodyText = ConvertTo-MarkdownText -Text ([string]$task.body) -ContinuationIndent '                 '
                    $lines.Add("  - Description: $bodyText")
                }
                if ($task.startDateTime) {
                    $lines.Add("  - Start: $(ConvertTo-MarkdownText -Text ([string]$task.startDateTime))")
                }
                if ($task.recurrence) {
                    $recurrenceText = ConvertTo-RecurrenceText -Recurrence $task.recurrence
                    if ($recurrenceText) {
                        $lines.Add("  - Recurrence: $(ConvertTo-MarkdownText -Text $recurrenceText)")
                    }
                }
                if ($task.reminderDateTime) {
                    $lines.Add("  - Reminder: $(ConvertTo-MarkdownText -Text ([string]$task.reminderDateTime))")
                }
            }

            $lines.Add('')
        }

        if ($ExportData.summary.failedLists.Count -gt 0) {
            $lines.Add('## Failed Lists')
            $lines.Add('')
            foreach ($failedList in $ExportData.summary.failedLists) {
                $lines.Add("- $(ConvertTo-MarkdownText -Text ([string]$failedList.name))")
            }
        }

        return $lines -join [Environment]::NewLine
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

        $markdownFile = $null
        if ($Markdown) {
            $markdownFile = Join-Path $OutputFolder "todo-export-$fileTimestamp.md"
            $markdownDocument = ConvertTo-MarkdownDocument -ExportData $export
            Set-Content -LiteralPath $markdownFile -Value $markdownDocument -Encoding utf8
            Write-Log 'Markdown rendering successful.'
        }
    }
    catch {
        Write-Log ("Export writing or JSON/Markdown validation failed: {0}" -f (Get-GraphErrorDetails -ErrorRecord $_))
        throw
    }

    Write-Log ("Elapsed duration: {0:N2} seconds." -f $durationSeconds)
    Write-Log "Output filename: $outputFile"
    Write-Log ("Export complete: {0} active, {1} completed, {2} failed list(s)." -f $totalActiveTasks, $totalCompletedTasks, $failedLists.Count)

    if (-not $NoBanner) {
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
        if ($MarkdownFile) {
            Write-Host "Markdown: $MarkdownFile"
        }
        Write-Host "Log: $LogFile"
        Write-Host '==================================' -ForegroundColor Cyan
    }

    return [pscustomobject]@{
        Export = $export
        OutputFile = $outputFile
        MarkdownFile = $markdownFile
    }
}

function Get-LocalTimeZoneCode {
        param([AllowNull()][DateTime]$Date)

        $zone = [TimeZoneInfo]::Local
        if ($zone.Id -eq 'UTC' -or $zone.Id -eq 'Etc/UTC') {
            return 'UTC'
        }

        $referenceDate = if ($null -ne $Date) { [DateTime]::SpecifyKind($Date, [DateTimeKind]::Unspecified) } else { [DateTime]::Now }
        $daylight = $zone.IsDaylightSavingTime($referenceDate)
        $id = $zone.Id.ToLowerInvariant()
        $name = $zone.DisplayName.ToLowerInvariant()

        $codes = if ($daylight) {
            @{ 'eastern' = 'EDT'; 'central' = 'CDT'; 'mountain' = 'MDT'; 'pacific' = 'PDT'; 'alaskan' = 'AKDT'; 'hawaiian' = 'HST' }
        }
        else {
            @{ 'eastern' = 'EST'; 'central' = 'CST'; 'mountain' = 'MST'; 'pacific' = 'PST'; 'alaskan' = 'AKST'; 'hawaiian' = 'HST' }
        }

        foreach ($key in $codes.Keys) {
            if ($id.Contains($key) -or $name.Contains($key)) {
                return $codes[$key]
            }
        }

        return $null
    }

    function ConvertTo-DisplayTime {
        param(
            [AllowNull()][object]$Value,
            [string]$SourceTimeZone
        )

        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
            return $null
        }

        $text = [string]$Value

        try {
            $offsetDate = [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)
            $hasExplicitOffset = $text.TrimEnd().EndsWith('Z', [StringComparison]::OrdinalIgnoreCase) -or $text -match '[+-]\d{2}:?\d{2}$'
            if ($hasExplicitOffset) {
                if ($offsetDate.Offset -eq [TimeSpan]::Zero) {
                    return $offsetDate.UtcDateTime.ToString('yyyy-MM-dd h:mm:ss tt', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
                }

                $localDate = [TimeZoneInfo]::ConvertTime($offsetDate, [TimeZoneInfo]::Local).DateTime
                $zoneCode = Get-LocalTimeZoneCode -Date $localDate
                $suffix = if ($zoneCode) { ' ' + $zoneCode } else { '' }
                return $localDate.ToString('yyyy-MM-dd h:mm:ss tt', [Globalization.CultureInfo]::InvariantCulture) + $suffix
            }
        }
        catch {
            # Fall through to DateTime parsing for Graph date strings without offsets.
        }

        try {
            $date = [DateTime]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            return $text
        }

        $utcSource = [string]::IsNullOrWhiteSpace($SourceTimeZone) -or $SourceTimeZone -match 'UTC|Zulu|GMT'
        if ($utcSource) {
            $utcDate = [DateTime]::SpecifyKind($date, [DateTimeKind]::Utc)
            $date = [TimeZoneInfo]::ConvertTimeFromUtc($utcDate, [TimeZoneInfo]::Local)
        }

        $zoneCode = Get-LocalTimeZoneCode -Date $date
        $suffix = if ($zoneCode) { ' ' + $zoneCode } else { '' }
        return $date.ToString('yyyy-MM-dd h:mm:ss tt', [Globalization.CultureInfo]::InvariantCulture) + $suffix
    }

function ConvertTo-RecurrenceText {
        param([AllowNull()]$Recurrence)

        if ($null -eq $Recurrence) {
            return $null
        }

        $pattern = $Recurrence.pattern
        $range = $Recurrence.range
        $parts = [System.Collections.Generic.List[string]]::new()

        if ($null -ne $pattern) {
            $type = [string]$pattern.type
            $interval = [string]$pattern.interval
            $patternText = switch ($type) {
                'daily' { "Every $interval day(s)" }
                'weekly' { "Every $interval week(s) on $((@($pattern.daysOfWeek) -join ', '))" }
                'absoluteMonthly' { "Every $interval month(s) on day $($pattern.dayOfMonth)" }
                'relativeMonthly' { "Every $interval month(s), $($pattern.index) $((@($pattern.daysOfWeek) -join ', '))" }
                'absoluteYearly' { "Every $interval year(s) on month $($pattern.month), day $($pattern.dayOfMonth)" }
                'relativeYearly' { "Every $interval year(s), $($pattern.index) $((@($pattern.daysOfWeek) -join ', ')) in month $($pattern.month)" }
                default { "Type: $type" }
            }
            $parts.Add($patternText)
        }

        if ($null -ne $range) {
            $rangeText = switch ([string]$range.type) {
                'endDate' { "until $($range.endDate)" }
                'numbered' { "for $($range.numberOfOccurrences) occurrence(s)" }
                'noEnd' { 'with no end date' }
                default { [string]$range.type }
            }
            $parts.Add("Starting $($range.startDate) $rangeText")
        }

        return ($parts -join '; ')
    }

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ToDoExport -IncludeCompleted:$IncludeCompleted -Markdown:$Markdown -ScriptRoot $PSScriptRoot
}
