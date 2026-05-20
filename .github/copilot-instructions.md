## Language Choice

Bash is always preferred when writing scripts. Only use Python when using libraries like pandas or numpy, or when the task involves complex data processing that cannot be efficiently handled with Bash.

## Shebang Lines

Always use appropriate shebang lines to ensure compatibility across different systems:
- For Bash scripts: `#!/usr/bin/env bash`
- For Python scripts: `#!/usr/bin/env python3`

## Shell Compatibility

`declare -A` is not supported by my shell (Bash version < 4.0) and should not be used. For associative arrays, consider using indexed arrays or key-value pairs in a delimited string format as an alternative.

## Documentation

Always document usage of scripts.

## Scale and Resilience

Scripts often iterate over hundreds of organizations, teams, or repositories. Design for resilience so a failure mid-run doesn't require starting over:
- Write results to an output file incrementally (append after each item), not all at once at the end.
- Support a resume mode: track progress (e.g., a processed list or checkpoint file) so the script can pick up where it left off.
- Add a `--dry-run` or `--limit N` option for testing against a small subset before running the full dataset.
- Log errors per item and continue processing the rest rather than exiting on the first failure.

## GitHub API

When developing with the GitHub API, prefer using the GitHub CLI (`gh`) for authentication and making API calls. This avoids the need to handle tokens directly in your scripts, enhancing security and simplicity.
