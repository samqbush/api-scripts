Bash is always preferred when writing scripts.  Only use python if necessary, for example when pandas or numpy is required, or when the task is too complex for a simple Bash script.
When writing scripts, always use `#!/usr/bin/env bash` as the shebang line to ensure compatibility across different systems.
declare -A is not supported by my shell (Bash version < 4.0) and should not be used. For associative arrays, consider using indexed arrays or key-value pairs in a delimited string format as an alternative.
Always document usage of scripts.
When developing with the GitHub API, prefer using the GitHub CLI (`gh`) for authentication and making API calls. This avoids the need to handle tokens directly in your scripts, enhancing security and simplicity.