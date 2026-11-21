# ToDoPull

ToDoPull is a PowerShell 7+ script that exports Microsoft To Do lists and tasks to a validated JSON file using Microsoft Graph. By default, the export includes active tasks; completed tasks are optional.

## Requirements

- PowerShell 7 or later.
- An internet connection and a personal Microsoft account with Microsoft To Do data.
- Microsoft Graph delegated permissions: `Tasks.Read` and `User.Read`. The script starts an interactive Microsoft Graph sign-in and requests consent as needed.

## Installation

Install the Microsoft Graph Authentication module for your current user:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

Clone or download this repository, then run the script from its directory. The first run may prompt you to sign in and consent to the requested Graph scopes.

## Usage

Export active tasks (the default):

```powershell
.\Export-Todo.ps1
```

Include completed tasks:

```powershell
.\Export-Todo.ps1 -IncludeCompleted
```

Also create a readable Markdown export alongside the JSON file:

```powershell
.\Export-Todo.ps1 -Markdown
```

Completed tasks can be included in both formats:

```powershell
.\Export-Todo.ps1 -IncludeCompleted -Markdown
```

Exports are written to `output/` and run logs to `logs/`, both created beside the script. JSON remains the default output. Markdown output uses checkbox task syntax and is written as a `.md` file with the same timestamp as the JSON export. Graph list/task requests follow pagination. Transient request failures are retried up to three times, and a list that still fails is recorded while processing continues for other lists.

## Export format

The top-level metadata includes script and Graph API versions, export time, list and task counts, elapsed duration, and a summary. Each list has a consistent structure and `tasks` is always an array, including for empty or single-task lists.

```json
{
  "scriptVersion": "0.4.0",
  "exportTimestamp": "2026-01-15T12:30:00.0000000Z",
  "graphApiVersion": "v1.0",
  "listCount": 1,
  "activeTaskCount": 1,
  "completedTaskCount": 0,
  "exportDurationSeconds": 1.25,
  "summary": {
    "largestList": "Personal",
    "largestListTaskCount": 1,
    "averageTasksPerList": 1.0,
    "failedListCount": 0,
    "failedLists": [],
    "skippedCompletedCount": 0
  },
  "lists": [
    {
      "id": "list-id",
      "name": "Personal",
      "taskCount": 1,
      "tasks": [
        {
          "id": "task-id",
          "title": "Example task",
          "status": "notStarted",
          "importance": "normal",
          "createdDateTime": "2026-01-15T10:00:00Z",
          "lastModifiedDateTime": "2026-01-15T10:00:00Z",
          "dueDateTime": null,
          "completedDateTime": null,
          "categories": [],
          "body": null,
          "hasAttachments": false,
          "isReminderOn": false
        }
      ]
    }
  ]
}
```

`activeTaskCount` and `completedTaskCount` count tasks actually included in the exported lists. If completed tasks are omitted, `summary.skippedCompletedCount` records the number skipped. `listCount` is the number of discovered lists; `summary.failedLists` identifies any lists whose tasks could not be fetched.

## Example console output

```text
2026-01-15 12:30:00 - Starting ToDo export v0.4.0 (IncludeCompleted: False)
2026-01-15 12:30:01 - Authentication successful; connected to Microsoft Graph.
2026-01-15 12:30:02 - List discovery complete: 1 list(s) found.
2026-01-15 12:30:02 - Processing list: Personal
2026-01-15 12:30:03 -   Task counts: 1 active, 0 completed exported, 1 total exported.
2026-01-15 12:30:03 - JSON validation successful.
2026-01-15 12:30:03 - Elapsed duration: 2.45 seconds.
2026-01-15 12:30:03 - Output filename: .../output/todo-export-20260115-123003.json
2026-01-15 12:30:03 - Export complete: 1 active, 0 completed, 0 failed list(s).
```

## Tests

Run the offline Pester test suite from the repository root:

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0
Invoke-Pester -Path ./tests
```

The tests mock Microsoft Graph and do not require Microsoft account credentials.

## License

This project is distributed under the MIT License; see [LICENSE](LICENSE).
