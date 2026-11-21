# ToDoPull 0.3.0

ToDoPull 0.3.0 improves task selection, export consistency, diagnostics, and resiliency. Active-only exports remain the default; pass `-IncludeCompleted` to include completed tasks. The JSON now contains detailed metadata and list-level summary statistics. Transient Graph requests are retried up to three times, and failed lists are reported without stopping other lists from exporting.

See [README.md](README.md) for installation, permissions, examples, and the export schema.
