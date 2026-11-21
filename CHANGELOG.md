# Changelog

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
