# AI Code Review Rules

## Security (CRITICAL)

1. **SQL Injection**: Never concatenate user input into SQL strings. Use parameterized queries.
2. **Hardcoded Secrets**: No API keys, tokens, passwords, or private keys in source code. Use environment variables or secrets manager.
3. **Command Injection**: Never pass user input directly to shell commands (`exec`, `spawn`, `os.system`). Use argument arrays or sanitize.
4. **XSS**: In web output, always escape user-generated content. Use framework built-in escaping (React JSX, Go html/template).

## Error Handling (HIGH)

5. **Swallowed Errors**: Catching an error without handling it (empty catch block, `_ = err`) is forbidden. Log or propagate.
6. **Error Messages**: Error messages returned to users must not leak stack traces, internal paths, or database structure.

## Performance (MEDIUM)

7. **N+1 Queries**: Avoid querying the database inside a loop. Use batch queries or JOINs.
8. **Missing Indexes**: New `WHERE` / `JOIN` columns in queries should have corresponding database indexes.

## Code Quality (MEDIUM)

9. **Duplicate Code**: Flag blocks of code that are copy-pasted across files. Suggest extraction.
10. **Naming**: Variables/functions with names under 2 characters (except loop indices `i`, `j`, `k`) should be renamed descriptively.

## Database Migrations (HIGH)

11. **NOT NULL without Default**: Adding a NOT NULL column to an existing table must include a DEFAULT value or be split into multiple migration steps.
12. **Destructive Changes**: Dropping columns or tables must have an explicit approval comment in the code.

## Testing (LOW)

13. **Untested Edge Cases**: New error-handling branches that lack corresponding test coverage should be flagged.
