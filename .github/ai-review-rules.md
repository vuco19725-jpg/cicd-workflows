# AI Code Review Rules

## Security (CRITICAL)

1. **Hardcoded Secrets**: No API keys, tokens, passwords, private keys, or connection strings in source code. Use environment variables or secrets manager.
2. **SQL Injection**: Never concatenate user input into SQL/NoSQL query strings. Use parameterized queries or ORM safe methods.
3. **Command Injection**: Never pass user input directly to shell commands (`exec`, `spawn`, `os.system`, `os/exec`). Use argument arrays or strict sanitization.
4. **XSS**: In web output, always escape user-generated content. Use framework built-in escaping (React JSX, Go `html/template`, Vue `v-text`).
5. **Missing Authentication/Authorization**: New endpoints or handlers must verify user identity and permissions. No unprotected routes.
6. **Unsafe Deserialization**: Never deserialize untrusted data without validation. Avoid `pickle`, `yaml.load`, `json.Unmarshal` on raw user input without schema checks.
7. **No Timeout on External Calls**: All HTTP requests, DB queries, and RPC calls must have explicit timeouts set. Default infinite timeout causes cascading failures.

## Error Handling (HIGH)

8. **Swallowed Errors**: Catching an error without handling it (empty catch block, `_ = err`, bare `except:`) is forbidden. Must log or propagate.
9. **Error Messages Leak Info**: Error messages returned to users must not expose stack traces, internal paths, database structure, or framework versions.
10. **Missing Input Validation**: All user input at system boundaries (API params, form fields, file uploads) must be validated for type, length, range, and format.
11. **Logging Sensitive Data**: Never log passwords, tokens, PII (email, phone, ID numbers), or credit card data. Use masked/redacted logging.
12. **Idempotency for Critical Operations**: Payment processing, webhook handlers, and order creation must be idempotent (duplicate requests produce same result).

## Performance (HIGH)

13. **N+1 Queries**: Avoid querying the database inside a loop. Use batch queries, JOINs, or eager loading.
14. **Missing Indexes**: New `WHERE` / `JOIN` / `ORDER BY` columns in queries should have corresponding database indexes.

## Code Quality (MEDIUM)

15. **Dead Code**: Large commented-out blocks, unreachable code, unused imports, and unused functions should be removed.
16. **Magic Numbers**: Numeric literals in business logic (except 0, 1, -1) must be named constants with descriptive names.
17. **Overly Long Functions**: Functions exceeding 50 lines should be split into smaller, single-responsibility functions.
18. **Naming**: Variables/functions with names under 2 characters (except loop indices `i`, `j`, `k`) should be renamed descriptively.
19. **Duplicate Code**: Blocks of code copy-pasted across files should be extracted into shared utility functions.

## Database Migrations (HIGH)

20. **NOT NULL without Default**: Adding a NOT NULL column to an existing table must include a DEFAULT value or be split into multiple migration steps.
21. **Destructive Changes**: Dropping columns, tables, or indexes must have an explicit approval comment explaining the migration plan and rollback strategy.

## Testing (LOW)

22. **Untested Error Branches**: New error-handling branches that lack corresponding test coverage should be flagged.
23. **Missing Edge Case Tests**: Functions handling user input, file I/O, or network calls should have tests for empty input, null values, and timeout scenarios.

## Anti-Rules (Do NOT flag)

- Code formatting or style (handled by linter/gofmt/prettier)
- Comment completeness (unless code is misleading without it)
- Variable naming preferences (unless under 2 characters)
- "Consider using pattern X" without concrete justification
