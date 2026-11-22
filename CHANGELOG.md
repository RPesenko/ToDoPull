# Changelog

## [0.5.0] - 2026-11-21

### Added
- Exported the Microsoft Graph `recurrence` property, including its pattern and range objects.
- Exported `startDateTime`, `reminderDateTime`, and `bodyLastModifiedDateTime` task properties.
- Added readable recurrence and schedule details to Markdown exports.
- Added Pester coverage for recurrence and additional schedule properties.

## [0.4.0] - 2026-11-21

### Added
- Added an optional `-Markdown` switch that writes a `.md` export alongside the JSON export.
- Added Markdown task checkboxes, list headings, due dates, categories, descriptions, and failed-list reporting.
- Added Pester coverage for Markdown rendering, Unicode, multiline descriptions, escaped punctuation, Graph pagination, recurrence, and Hashtable values.
- Added GitHub Actions validation for pull requests and pushes to `main`.

### Changed
- Normalized Hashtable task fields, including due dates and body content, before rendering JSON or Markdown.
- Updated task and log timestamps to local 12-hour time with `AM`/`PM` and available timezone abbreviations.
- Preserved explicit UTC labels for UTC timestamps.
- Aligned multiline Markdown descriptions beneath the description text.

## [0.3.0] - 2026-11-21

### Added
- Added `-IncludeCompleted` to optionally export completed tasks while keeping active-only exports as the default.
- Added export metadata for the script/Graph versions, timestamp, list and task totals, and elapsed duration.
- Added summary statistics for the largest list, average tasks per list, failed lists, and skipped completed tasks.
- Added retries for transient Graph API failures and per-list failure capture so remaining lists continue processing.
- Added detailed authentication, discovery, per-list task count, exception, duration, and output-file logging.
- Added complete usage documentation, GitHub issue templates, and version 0.3.0 release notes.

### Changed
- Standardized list and task structures and kept task/list collections as arrays, including zero and one-element cases.
- Improved PowerShell parameter, error-handling, and style consistency for PowerShell 7+.
- Updated the MIT license text.

## [0.2.0]

- Authenticated to Microsoft Graph and exported To Do lists and active tasks to JSON.
- Added Graph pagination, logging, JSON validation, and export summaries.

## [0.1.0]

- Initial starter kit.
