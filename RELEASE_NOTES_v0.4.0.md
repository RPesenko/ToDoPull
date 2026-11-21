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

See [README.md](README.md) for usage and export format documentation.
