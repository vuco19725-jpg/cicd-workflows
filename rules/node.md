## Node.js/TypeScript 特定规则

### 安全（CRITICAL）
- **原型污染**：禁止对用户输入使用 `_.merge()`、`Object.assign()` 等不安全的深度合并。用 `structuredClone()` 或冻结 `Object.prototype`。
- **eval/Function 注入**：禁止 `eval()`、`new Function()` 处理用户输入。禁止 `child_process.exec()` 拼接用户数据，用 `spawn()` + 参数数组。
- **NoSQL 注入**：MongoDB 查询中禁止直接使用用户提供的 `$where`、`$regex` 等操作符。strip `$` 前缀的 key。
- **npm 生命周期脚本**：CI 中必须用 `npm ci --ignore-scripts`。生产镜像禁止 `postinstall` 脚本。

### 鉴权（CRITICAL）
- **JWT `alg: none`**：必须 enforce allow-list 签名算法，拒绝 `alg: "none"`。
- **时序攻击**：密码/token 比较必须用 `crypto.timingSafeEqual()`，禁止 `===`。
- **bcrypt cost < 12**：密码哈希 cost factor 至少 12。

### 错误处理（HIGH）
- **异步错误未处理**：Promise 必须有 `.catch()` 或 await + try/catch。Express 路由必须显式调用 `next(err)`。
- **console.log 泄露敏感数据**：禁止 log 打印 token、密码、用户对象。生产用结构化日志 Pino/Winston。

### 依赖安全（HIGH）
- **lockfile 未提交**：`package-lock.json` 必须 commit。CI 用 `npm ci` 而不是 `npm install`。
- **未审计的依赖**：新依赖必须检查维护状态、已知漏洞、生命周期脚本。

### 反面规则
- console.log / debugger 语句（linter 处理）
- React/Vue 组件结构偏好
- CSS 类名命名风格
