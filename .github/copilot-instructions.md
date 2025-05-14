Bash is always preferred when writing scripts.  Only use python if necessary.
declare -A is not supported by my shell (Bash version < 4.0) and should not be used. For associative arrays, consider using indexed arrays or key-value pairs in a delimited string format as an alternative.
Always document usage of scripts.