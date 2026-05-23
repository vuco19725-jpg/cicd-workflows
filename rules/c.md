## C/C++ 特定规则

### 内存安全（CRITICAL）
- **缓冲区溢出**：禁止使用 `strcpy`、`strcat`、`gets`、`sprintf`。用 `strncpy`、`snprintf`、`std::string` 替代。
- **Use-After-Free / 悬空指针**：释放后未置 `nullptr`。优先用 `std::unique_ptr`、`std::shared_ptr` 管理所有权。禁止 `ptr.get()` 长期存储。
- **整数溢出**：分配大小计算前未检查溢出。用 `__builtin_add_overflow` 或 `std::add_overflow`(C++23)。循环索引类型应统一，避免 `int` 和 `size_t` 混用。
- **未检查返回值**：`malloc`、`fopen`、`pthread_create` 返回值未检查。每个系统调用必须检查错误。

### RAII 资源管理（CRITICAL）
- **裸 new/delete**：禁止。文件用 `std::fstream`，锁用 `std::lock_guard` / `std::scoped_lock`。用 `std::make_unique` / `std::make_shared` 创建智能指针。
- **析构函数抛异常**：析构函数必须 `noexcept`。异常在析构中会导致 `std::terminate`。
- **移动构造未置空源指针**：`other.data_ = nullptr` 缺失导致 double-free。

### 格式化字符串（CRITICAL）
- **`printf(user_input)`**：禁止用户输入直接当格式化字符串。必须用 `printf("%s", user_input)`。
- **`snprintf` 截断未检查**：截断时返回值 ≥ buf_size，必须处理截断情况。

### 并发安全（HIGH）
- **`std::atomic` 内存序错误**：禁止随地用 `memory_order_relaxed`。acquire/release 必须配对。
- **数据竞争**：多线程读写同一变量未加锁或未用 `std::atomic`。用 TSan(`-fsanitize=thread`) 检测。
- **线程生命周期**：用 `std::jthread`(C++20) 自动 join；传递 `std::stop_token` 协作取消。

### 代码质量（MEDIUM）
- **C 风格转换**：禁止 `(int)x`。用 `static_cast`、`reinterpret_cast`（标注原因）。
- **宏滥用**：复杂宏用 `constexpr` / `inline` 函数替代。
- **魔法数字**：缓冲区大小、超时值等必须命名常量，附带单位注释。

### 编译器标志（应存在）
- `-Wall -Wextra -Werror` 必须开启
- `-fstack-protector-strong` 栈保护
- `-D_FORTIFY_SOURCE=2` 运行时缓冲区检测
- ASan/UBSan 在测试中开启

### 反面规则
- 命名风格偏好（snake_case vs camelCase）
- `#include` 顺序
- 注释语言选择
