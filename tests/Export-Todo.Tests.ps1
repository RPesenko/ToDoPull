Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot '..\Export-Todo.ps1'
. $scriptPath

function New-TestTask {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status = 'notStarted'
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
        categories = @('Work')
        body = [pscustomobject]@{ content = 'Task body' }
        hasAttachments = $false
        isReminderOn = $true
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

        $result.Export.activeTaskCount | Should Be 1
        $result.Export.completedTaskCount | Should Be 0
        $result.Export.summary.skippedCompletedCount | Should Be 1
        $result.Export.lists.Count | Should Be 1
        $result.Export.lists[0].taskCount | Should Be 1
        $result.Export.lists[0].tasks[0].id | Should Be 'task-active'
        Test-Path $result.OutputFile | Should Be $true
        (Get-Content -LiteralPath $result.OutputFile -Raw | ConvertFrom-Json).lists[0].tasks.Count | Should Be 1
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

        $result.Export.activeTaskCount | Should Be 1
        $result.Export.completedTaskCount | Should Be 1
        $result.Export.summary.skippedCompletedCount | Should Be 0
        $result.Export.lists[0].taskCount | Should Be 2
    }

    It 'uses empty task arrays for empty lists' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/me/todo/lists$') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'empty-list'; displayName = 'Empty' }); '@odata.nextLink' = $null }
            }
            return [pscustomobject]@{ value = @(); '@odata.nextLink' = $null }
        }

        $result = Invoke-ToDoExport -ScriptRoot $testRoot -NoBanner

        $result.Export.lists[0].tasks -is [array] | Should Be $true
        $result.Export.lists[0].tasks.Count | Should Be 0
        $result.Export.summary.largestListTaskCount | Should Be 0
        $result.Export.summary.averageTasksPerList | Should Be 0
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

        $result.Export.listCount | Should Be 2
        $result.Export.activeTaskCount | Should Be 2
        $result.Export.summary.largestList | Should Be 'One'
        $result.Export.summary.largestListTaskCount | Should Be 2
        $result.Export.summary.averageTasksPerList | Should Be 1
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

        $result.Export.summary.failedListCount | Should Be 1
        $result.Export.summary.failedLists[0].id | Should Be 'bad-list'
        $result.Export.activeTaskCount | Should Be 1
        $result.Export.lists.Count | Should Be 1
        $result.Export.lists[0].name | Should Be 'Good'
    }
}
