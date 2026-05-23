## Go 特定规则

### 并发安全（CRITICAL）
- **goroutine 泄漏**：每个 goroutine 必须有明确的退出条件。使用 context 传播取消信号，确保所有 goroutine 在函数返回前退出。
- **未加锁的共享变量**：多个 goroutine 读写同一变量必须用 sync.Mutex/RWMutex 保护。优先用 Mutex 而非 Channel 处理共享状态。
- **channel 未关闭**：生产者退出时必须 close channel，消费者用 `for range`。永远不要在接收端 close channel。
- **WaitGroup 误用**：`wg.Add(1)` 必须在 goroutine 外部调用。禁止拷贝 WaitGroup。

### 错误处理（CRITICAL）
- **吞错误**：禁止 `_ = err` 和空的 `if err != nil {}`。错误必须 log + return 或 wrap + propagate。
- **panic 未 recover**：goroutine 内必须 defer recover，否则单 goroutine panic 崩整个进程。
- **返回 `(nil, nil)`**：禁止返回模糊的 `(result, err)` 组合。有 err 时 result 必须是零值。

### 代码质量（HIGH）
- **defer 在循环内**：`for { defer f.Close() }` 导致文件句柄堆积和内存泄漏。循环体应封装为函数。
- **context 未检查取消**：传入了 ctx 但函数内从未 select ctx.Done()。所有阻塞操作必须响应取消。
- **interface{} 滥用**：能用泛型/具体类型的不用 interface{}/any。

### GORM 特定（HIGH）
- **零值更新陷阱**：`db.Updates(struct{...})` 不会更新零值字段(0,"",false)。用 `Select` 指定字段或传入 map。
- **N+1 查询**：循环内调用 DB。用 `Preload`/`Joins` 预加载关联数据。
- **缺少超时**：`db.WithContext(ctx)` 必须传入带 timeout 的 context。

### 反面规则
- gofmt 格式问题
- import 分组顺序（goimports 处理）
- 变量命名风格偏好
