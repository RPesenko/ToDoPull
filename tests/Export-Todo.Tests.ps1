Set-StrictMode -Version Latest

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\Export-Todo.ps1'
    . $scriptPath

    function New-TestTask {
        param(
            [string]$Id,
            [string]$Title,
            [string]$Status = 'notStarted',
            [AllowNull()][string]$Body = 'Task body',
            [string[]]$Categories = @('Work')
        )

        [pscustomobject]@{
            id = $Id
            title = $Title
            status = $Status
            importance = 'normal'
            createdDateTime = '2026-11-21T12:00:00Z'
            lastModifiedDateTime = '2026-11-21T12:30:00Z'
            dueDateTime = $null
            completedDateTime = if ($Status -eq 'completed') { '2026-11-21T12:30:00Z' } else { $null }
            categories = $Categories
            body = if ($null -eq $Body) { $null } else { [pscustomobject]@{ content = [string]$Body } }
            hasAttachments = $false
            isReminderOn = $true
        }
    }
}

Describe 'ToDoPull export behavior' {
    $testRoot = $null

    BeforeEach {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ToDoPull.Tests-' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        Mock Import-Module { }
        Mock Connect-MgGraph { }
    }

    AfterEach {
        if ($testRoot -and (Test-Path $testRoot)) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }

    It 'exports active tasks and skips completed tasks by default' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Personal' }); '@odata.nextLink' = $null }
            }
            if ($Uri -match '/lists/list-1/tasks$') {
                return [pscustomobject]@{
                    value = @(
                        (New-TestTask -Id 'task-active' -Title 'Active'),
                        (New-TestTask -Id 'task-done' -Title 'Done' -Status 'completed')
                    )
                    '@odata.nextLink' = $null
                }
            }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.Export.activeTaskCount | Should -Be 1
        $result.Export.completedTaskCount | Should -Be 0
        $result.Export.summary.skippedCompletedCount | Should -Be 1
        $result.Export.lists.Count | Should -Be 1
        $result.Export.lists[0].taskCount | Should -Be 1
        $result.Export.lists[0].tasks[0].id | Should -Be 'task-active'
        Test-Path $result.OutputFile | Should -Be $true
        (Get-Content -LiteralPath $result.OutputFile -Raw | ConvertFrom-Json).lists[0].tasks.Count | Should -Be 1
    }

    It 'includes completed tasks when requested' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Personal' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{
                value = @(
                    (New-TestTask -Id 'task-active' -Title 'Active'),
                    (New-TestTask -Id 'task-done' -Title 'Done' -Status 'completed')
                )
                '@odata.nextLink' = $null
            }
        }

        $result = Invoke-ToDoExport -IncludeCompleted -ScriptRoot $testRoot -NoBanner

        $result.Export.activeTaskCount | Should -Be 1
        $result.Export.completedTaskCount | Should -Be 1
        $result.Export.summary.skippedCompletedCount | Should -Be 0
        $result.Export.lists[0].taskCount | Should -Be 2
    }

    It 'uses empty task arrays for empty lists' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'empty-list'; displayName = 'Empty' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{ value = @(); '@odata.nextLink' = $null }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.Export.lists[0].tasks -is [array] | Should -Be $true
        $result.Export.lists[0].tasks.Count | Should -Be 0
        $result.Export.summary.largestListTaskCount | Should -Be 0
        $result.Export.summary.averageTasksPerList | Should -Be 0
    }

    It 'follows Graph pagination and aggregates summary values' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'list-1'; displayName = 'One' })
                    '@odata.nextLink' = 'https://graph.test/lists-page-2'
                }
            }
            if ($Uri -eq 'https://graph.test/lists-page-2') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'list-2'; displayName = 'Two' })
                    '@odata.nextLink' = $null
                }
            }
            if ($Uri -match '/lists/list-1/tasks$') {
                return [pscustomobject]@{ value = @((New-TestTask -Id 'a' -Title 'A')); '@odata.nextLink' = 'https://graph.test/tasks-page-2' }
            }
            if ($Uri -eq 'https://graph.test/tasks-page-2') {
                return [pscustomobject]@{ value = @((New-TestTask -Id 'b' -Title 'B')); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{ value = @(); '@odata.nextLink' = $null }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.Export.listCount | Should -Be 2
        $result.Export.activeTaskCount | Should -Be 2
        $result.Export.summary.largestList | Should -Be 'One'
        $result.Export.summary.largestListTaskCount | Should -Be 2
        $result.Export.summary.averageTasksPerList | Should -Be 1
    }

    It 'records an individual list failure and continues exporting other lists' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ id = 'bad-list'; displayName = 'Bad' },
                        [pscustomobject]@{ id = 'good-list'; displayName = 'Good' }
                    )
                    '@odata.nextLink' = $null
                }
            }
            if ($Uri -match '/lists/bad-list/tasks$') {
                throw [System.InvalidOperationException]::new('List request failed')
            }
            return [pscustomobject]@{ value = @((New-TestTask -Id 'good-task' -Title 'Good')); '@odata.nextLink' = $null }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.Export.summary.failedListCount | Should -Be 1
        $result.Export.summary.failedLists[0].id | Should -Be 'bad-list'
        $result.Export.activeTaskCount | Should -Be 1
        $result.Export.lists.Count | Should -Be 1
        $result.Export.lists[0].name | Should -Be 'Good'
    }

    It 'does not create Markdown output unless the switch is specified' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Personal' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{ value = @((New-TestTask -Id 'task-1' -Title 'Normal')); '@odata.nextLink' = $null }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.MarkdownFile | Should -BeNullOrEmpty
        Get-ChildItem -LiteralPath (Join-Path $testRoot 'output') -Filter '*.md' | Should -BeNullOrEmpty
    }

    It 'renders checkbox tasks and escapes Unicode, multiline, and punctuation content' {
        $title = '*Review [日本語]* & _draft_'
        $body = "First line`nSecond # line`nThird | line"

        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = '日本語リスト' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{
                value = @(
                    (New-TestTask -Id 'task-active' -Title $title -Body "First line`nSecond # line`nThird | line" -Categories @('Work', '日本語')),
                    (New-TestTask -Id 'task-done' -Title 'Done' -Status 'completed' -Body $null -Categories @())
                )
                '@odata.nextLink' = $null
            }
        }

        $result = Invoke-ToDoExport -IncludeCompleted -Markdown -ScriptRoot $testRoot -NoBanner

        $result.MarkdownFile | Should -Not -BeNullOrEmpty
        Test-Path $result.MarkdownFile | Should -Be $true
        $result.Export.lists[0].tasks[0].body | Should -Be $body

        $markdown = Get-Content -LiteralPath $result.MarkdownFile -Raw
        $markdown | Should -Match '## 日本語リスト'
        $markdown | Should -Match '\- \[ \]'
        $markdown | Should -Match '\- \[x\]'
        $markdown | Should -Match '日本語'
        $markdown | Should -Match 'First line'
        $markdown | Should -Match 'Second'
        $markdown | Should -Match 'Third'
        $markdown | Should -Match ([regex]::Escape('\*Review'))
        $markdown | Should -Match ([regex]::Escape('\['))
        $markdown | Should -Match ([regex]::Escape('\_draft\_'))
        $markdown | Should -Match ([regex]::Escape('\# line'))
        $markdown | Should -Match ([regex]::Escape('\| line'))
    }

    It 'renders Hashtable due-date and body values as scalar Markdown values' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Household workings' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    id = 'task-1'
                    title = 'Renew subscription'
                    status = 'notStarted'
                    importance = 'normal'
                    createdDateTime = '2026-11-21T12:00:00Z'
                    lastModifiedDateTime = '2026-11-21T12:30:00Z'
                    dueDateTime = @{ dateTime = '2026-11-22T06:00:00Z'; timeZone = 'UTC' }
                    completedDateTime = $null
                    categories = @()
                    body = @{ content = 'Renew before the deadline' }
                    hasAttachments = $false
                    isReminderOn = $false
                })
                '@odata.nextLink' = $null
            }
        }

        $result = Invoke-ToDoExport -Markdown -ScriptRoot $testRoot -NoBanner

        $result.Export.lists[0].tasks[0].dueDateTime | Should -Match '2026-11-22'
        $result.Export.lists[0].tasks[0].dueDateTime | Should -Match 'AM|PM'
        $result.Export.lists[0].tasks[0].body | Should -Be 'Renew before the deadline'

        $markdown = Get-Content -LiteralPath $result.MarkdownFile -Raw
        $markdown | Should -Match 'Due:'
        $markdown | Should -Match 'AM|PM'
        $markdown | Should -Match 'Description: Renew before the deadline'
        $markdown | Should -Not -Match 'System\.Collections\.Hashtable'
    }

    It 'formats explicit UTC timestamps and appends AM or PM to local task times' {
        $utcText = ConvertTo-DisplayTime -Value '2026-11-21T12:00:00Z' -SourceTimeZone 'UTC'
        $utcText | Should -Match 'UTC'
        $utcText | Should -Match 'AM|PM'

        $localText = ConvertTo-DisplayTime -Value '2026-11-21T12:00:00-05:00' -SourceTimeZone 'EST'
        $localText | Should -Match 'AM|PM'
        $localText | Should -Not -Match 'System\.Collections\.Hashtable'
    }

    It 'indents multiline description continuation lines beneath description text' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Tasks' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    id = 'task-1'
                    title = 'Task name'
                    status = 'notStarted'
                    importance = 'normal'
                    createdDateTime = '2026-11-21T12:00:00Z'
                    lastModifiedDateTime = '2026-11-21T12:30:00Z'
                    dueDateTime = $null
                    completedDateTime = $null
                    categories = @()
                    body = @{ content = "First body line`nSecond body line" }
                    hasAttachments = $false
                    isReminderOn = $false
                })
                '@odata.nextLink' = $null
            }
        }

        $result = Invoke-ToDoExport -Markdown -ScriptRoot $testRoot -NoBanner
        $markdown = Get-Content -LiteralPath $result.MarkdownFile -Raw

        $markdown | Should -Match "Description: First body line`r?`n                 Second body line"
        $markdown | Should -Not -Match "`nSecond body line"
    }

    It 'exports recurrence and additional task schedule properties' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'list-1'; displayName = 'Recurring tasks' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    id = 'task-1'
                    title = 'Monthly review'
                    status = 'notStarted'
                    importance = 'normal'
                    createdDateTime = '2026-11-21T12:00:00Z'
                    lastModifiedDateTime = '2026-11-21T12:30:00Z'
                    bodyLastModifiedDateTime = '2026-11-21T12:31:00Z'
                    startDateTime = @{ dateTime = '2026-11-22T09:00:00Z'; timeZone = 'UTC' }
                    dueDateTime = @{ dateTime = '2026-11-22T17:00:00Z'; timeZone = 'UTC' }
                    reminderDateTime = @{ dateTime = '2026-11-22T08:30:00Z'; timeZone = 'UTC' }
                    completedDateTime = $null
                    recurrence = @{
                        pattern = @{ type = 'absoluteMonthly'; interval = 1; dayOfMonth = 22 }
                        range = @{ type = 'noEnd'; startDate = '2026-11-22'; recurrenceTimeZone = 'UTC' }
                    }
                    categories = @('Work')
                    body = @{ content = 'Review account and renew if needed' }
                    hasAttachments = $false
                    isReminderOn = $true
                })
                '@odata.nextLink' = $null
            }
        }

        $result = Invoke-ToDoExport -Markdown -ScriptRoot $testRoot -NoBanner
        $task = $result.Export.lists[0].tasks[0]

        $task.recurrence.pattern.type | Should -Be 'absoluteMonthly'
        $task.recurrence.range.type | Should -Be 'noEnd'
        $task.startDateTime | Should -Match 'AM|PM'
        $task.reminderDateTime | Should -Match 'AM|PM'
        $task.bodyLastModifiedDateTime | Should -Match 'AM|PM'

        $markdown = Get-Content -LiteralPath $result.MarkdownFile -Raw
        $markdown | Should -Match 'Recurrence:'
        $markdown | Should -Match 'absoluteMonthly|Every 1 month'
        $markdown | Should -Match 'Starting 2026-11-22'
    }
}
