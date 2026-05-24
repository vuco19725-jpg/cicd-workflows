# AI Code Review Rules

## 严重级别定义

| 级别 | 含义 | 操作 |
|------|------|------|
| **CRITICAL** | 可直接导致系统被攻破、数据丢失 | REQUEST_CHANGES，必须修 |
| **HIGH** | 生产环境下必出问题 | REQUEST_CHANGES |
| **MEDIUM** | 显著影响可靠性/可维护性 | COMMENT，建议修 |
| **LOW** | 次要问题，不影响功能 | COMMENT，可选修 |

---

## Security (CRITICAL)

1. **Hardcoded Secrets**: No API keys, tokens, passwords, private keys, or connection strings in source code. Use environment variables or secrets manager.
2. **SQL/NoSQL Injection**: Never concatenate user input into query strings. Use parameterized queries or ORM safe methods.
3. **Command Injection**: Never pass user input directly to shell commands (`exec`, `spawn`, `os.system`, `os/exec`). Use argument arrays or strict sanitization.
4. **XSS**: In web output, always escape user-generated content. Use framework built-in escaping (React JSX, Go `html/template`, Vue `v-text`).
5. **Missing Authentication/Authorization**: New endpoints or handlers must verify user identity and permissions. No unprotected routes. Check for missing `@PreAuthorize`, `requireAuth`, `authMiddleware`.
6. **Unsafe Deserialization**: Never deserialize untrusted data without validation. Avoid `pickle`, `yaml.load`, `json.Unmarshal` on raw user input without schema checks.
7. **No Timeout on External Calls**: All HTTP requests, DB queries, and RPC calls must have explicit timeouts set. Default infinite timeout causes cascading failures.
8. **CSRF Protection**: Mutating endpoints (POST/PUT/DELETE) must have CSRF protection. Check for missing CSRF tokens or `SameSite` cookie attributes.

## Error Handling (HIGH)

9. **Swallowed Errors**: Catching an error without handling it (empty catch block, `_ = err`, bare `except:`) is forbidden. Must log or propagate.
10. **Error Messages Leak Info**: Error messages returned to users must not expose stack traces, internal paths, database structure, or framework versions.
11. **Missing Input Validation**: All user input at system boundaries (API params, form fields, file uploads) must be validated for type, length, range, and format.
12. **Logging Sensitive Data**: Never log passwords, tokens, PII (email, phone, ID numbers), credit card data, or full request bodies. Use masked/redacted logging.
13. **Idempotency for Critical Operations**: Payment processing, webhook handlers, and order creation must be idempotent (duplicate requests produce same result).

## Reliability (HIGH)

14. **Race Conditions**: Shared state accessed without proper synchronization (mutex, lock, atomic). Check for goroutine safety, transaction isolation levels.
15. **API Rate Limiting**: Public endpoints lacking rate limiting protection. Any public API should have rate limiting configured.
16. **Missing Circuit Breaker**: External service calls lacking failure handling. If downstream is down, service should degrade gracefully, not cascade.

## Performance (MEDIUM)

17. **N+1 Queries**: Avoid querying the database inside a loop. Use batch queries, JOINs, or eager loading.
18. **Missing Indexes**: New `WHERE` / `JOIN` / `ORDER BY` columns in queries should have corresponding database indexes.
19. **Unnecessary Allocations**: Creating large objects in loops, missing object pooling. Check for `sync.Pool` usage where appropriate.

## Code Quality (MEDIUM)

20. **Dead Code**: Large commented-out blocks, unreachable code, unused imports, and unused functions should be removed.
21. **Magic Numbers**: Numeric literals in business logic (except 0, 1, -1) must be named constants with descriptive names.
22. **Overly Long Functions**: Functions exceeding 50 lines should be split into smaller, single-responsibility functions.
23. **Naming**: Variables/functions with names under 2 characters (except loop indices `i`, `j`, `k`) should be renamed descriptively.
24. **Duplicate Code**: Blocks of code copy-pasted across files should be extracted into shared utility functions.

## Database Migrations (HIGH)

25. **NOT NULL without Default**: Adding a NOT NULL column to an existing table must include a DEFAULT value or be split into multiple migration steps.
26. **Destructive Changes**: Dropping columns, tables, or indexes must have an explicit approval comment explaining the migration plan and rollback strategy.
27. **Non-Idempotent Migrations**: Migrations lacking `IF EXISTS`/`IF NOT EXISTS` guards. Every migration should be re-runnable without failure.

## Configuration (HIGH)

28. **Unresolved Placeholders**: Configuration files containing `REPLACE_ME`, `TODO_SECRET`, `CHANGEME`, `<INSERT>` or similar placeholder values.
29. **Hardcoded Environment Values**: Environment-specific URLs, ports, or credentials hardcoded instead of sourced from config/env.

## Testing (LOW)

30. **Untested Error Branches**: New error-handling branches that lack corresponding test coverage should be flagged.
31. **Missing Edge Case Tests**: Functions handling user input, file I/O, or network calls should have tests for empty input, null values, and timeout scenarios.

## Anti-Rules (Do NOT flag)

- Code formatting or style (handled by linter/gofmt/prettier)
- Comment completeness (unless code is misleading without it)
- Variable naming preferences (unless under 2 characters)
- "Consider using pattern X" without concrete justification
- Import order or grouping (handled by goimports)
- Test file naming convention
