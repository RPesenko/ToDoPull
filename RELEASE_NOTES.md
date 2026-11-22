# ToDoPull 0.5.0

ToDoPull 0.5.0 expands task metadata exports to include recurrence, start, reminder, and body modification properties.

## Highlights

- Export `recurrence.pattern` and `recurrence.range` for recurring tasks.
- Render a readable recurrence line in Markdown exports.
- Export `startDateTime`, `reminderDateTime`, and `bodyLastModifiedDateTime` task properties.
- Preserve local-time formatting and timezone abbreviations for schedule timestamps.
- Pester tests cover recurrence and additional task schedule properties.

See [README.md](README.md) for usage and export format documentation.

# ToDoPull 0.4.0

ToDoPull 0.4.0 adds optional Markdown exports and improves timestamp and task-field presentation.

## Highlights

- Use `-Markdown` to create a `.md` file alongside the JSON export.
- Combine `-IncludeCompleted -Markdown` to include completed tasks in both formats.
- Markdown exports use checkbox syntax and include list headings, due dates, categories, descriptions, and failed-list information.
- Graph Hashtable values for due dates and task bodies are normalized into readable scalar values.
- Timestamps shown outside explicit UTC contexts use local 12-hour time with `AM`/`PM` and the available timezone abbreviation.
- Multiline descriptions continue on indented lines aligned with the description text.
- Pester tests cover export behavior and Markdown edge cases, and GitHub Actions validates pull requests and pushes to `main`.
- Recurrence properties are exported from `recurrence.pattern` and `recurrence.range`, and rendered as readable Markdown text.
- Start, reminder, and body modification timestamps are included in normalized task exports.

See [README.md](README.md) for usage and export format documentation.

# ToDoPull 0.3.0

ToDoPull 0.3.0 improves task selection, export consistency, diagnostics, and resiliency. Active-only exports remain the default; pass `-IncludeCompleted` to include completed tasks. The JSON now contains detailed metadata and list-level summary statistics. Transient Graph requests are retried up to three times, and failed lists are reported without stopping other lists from exporting.

See [README.md](README.md) for installation, permissions, examples, and the export schema.
