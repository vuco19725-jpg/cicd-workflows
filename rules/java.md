## Java/Spring Boot 特定规则

### 安全（CRITICAL）
- **Spring Security 配置错误**：禁止 `.csrf().disable()`。禁止 `.permitAll()` 在敏感端点上。禁止 `@PermitAll` 在认证/管理接口上。
- **反序列化漏洞**：禁止 `ObjectInputStream` 处理不可信输入。禁止 Jackson `enableDefaultTyping()`。restrict 反序列化类型白名单。
- **JWT 验证缺失**：禁止 `parseClaimsJwt()`（不验证签名）。必须用 `parseSignedClaims()` 并验证 iss/aud/exp。
- **XXE（XML 外部实体）**：XML 解析器必须禁用 DTD/外部实体。`DocumentBuilderFactory` 必须设置 `FEATURE_SECURE_PROCESSING`。
- **路径遍历**：文件下载/上传禁止直接拼接用户输入的文件名。用 `Paths.get(baseDir).resolve(userPath).normalize()` 并验证路径在 baseDir 内。

### 鉴权（CRITICAL）
- **缺少方法级授权**：Controller 有鉴权但 Service 层没有 `@PreAuthorize` 校验。权限检查不够深。
- **角色提升漏洞**：用户不能通过 request body 的 `role`/`roles` 字段自提权。角色变更必须走独立的管理接口。

### 数据访问（HIGH）
- **JPQL/SQL 注入**：`@Query("SELECT ... WHERE name = '" + input + "'")` 禁止字符串拼接。用命名参数 `:name`。
- **N+1 查询**：JPA `@OneToMany(fetch=LAZY)` + 循环访问导致 N+1。用 `@EntityGraph`、`JOIN FETCH`、或 `@BatchSize`。
- **事务边界错误**：Service 方法缺少 `@Transactional`，或事务范围过大包含外部调用。

### 代码质量（MEDIUM）
- **字段注入代替构造器注入**：`@Autowired private Field f` 不可测试。用 `@RequiredArgsConstructor` 构造器注入。
- **异常泄露栈信息**：Controller 返回 500 时 body 包含完整 stacktrace。用 `@ControllerAdvice` 统一处理，生产不返回 stack。

### 反面规则
- Checkstyle 格式问题
- Lombok 使用偏好
- 日志级别选择（@Slf4j 已处理）
