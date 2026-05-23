## Python 特定规则

### 安全（CRITICAL）
- **pickle 反序列化**：禁止 `pickle.loads()` 处理不可信输入。这是 RCE 漏洞（CWE-502）。用 `json.loads()` 或 `yaml.safe_load()`。
- **命令注入**：禁止 `os.system()` 和 `subprocess.run(..., shell=True)` 拼接用户输入。用 `subprocess.run([cmd, arg1, arg2], check=True)` + 参数列表。
- **Jinja2 模板注入**：禁止 `Template(user_input).render()` 和 `render_template_string(user_input)`。用户输入不进模板引擎。
- **eval/exec/compile**：禁止对用户数据使用。这是直接的代码执行。

### 鉴权（CRITICAL）
- **Django SECRET_KEY 泄露**：必须从环境变量加载，禁止硬编码在 settings.py。
- **DEBUG=True 在生产**：禁止。会泄露 settings、环境变量和 stacktrace。
- **密码哈希弱**：禁止 MD5/SHA1。必须用 `bcrypt`、`scrypt` 或 Django 的 `make_password()`。

### 错误处理（HIGH）
- **bare except**：禁止 `except:` 或 `except Exception:` 吞所有异常。必须捕获具体类型。
- **异常信息泄露**：禁止 `str(e)` 直接返回给用户。生产错误响应不能包含 traceback 或文件路径。

### 代码质量（MEDIUM）
- **mutable 默认参数**：`def f(items=[])` 是经典陷阱，多次调用共享同一 list。用 `def f(items=None)`。
- **资源未关闭**：文件、socket、DB 连接必须用 `with` 语句。禁止手动 `.open()` + `.close()`。
- **asyncio 阻塞调用**：async 函数内禁止 `time.sleep()`、`requests.get()` 等同步阻塞调用。用 `asyncio.sleep()`、`aiohttp`。

### 依赖安全（HIGH）
- **requirements.txt 未固定版本**：禁止 `flask>=2.0`。生产必须 pin 精确版本 `flask==3.1.0`。
- **未审计的依赖**：新依赖必须检查 PyPI 发布历史、维护者声誉、已知 CVE。

### 反面规则
- Black/isort 格式问题
- docstring 完整性（除非 API 文档需要）
- f-string vs .format() 偏好
