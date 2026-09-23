# codex-winfix

Windows Codex 工具链修复 Skill。它针对 Codex 提示“没有可用的终端、文件编辑或子智能体管理工具”，以及 code-mode host exited during handshake、CWD 转发、插件缓存复制和 app-server 重载异常。

## 一、这个仓库是什么？

这是一个轻量、可复用的 Codex Skill 和 PowerShell 修复脚本。它把 Windows 上已经验证过的排查路径整理成一条安全流程：

~~~text
读取证据 -> 区分模型/配置/路径/插件问题 -> 备份 -> 安全暂存修复
-> 正常重启 Desktop -> 终端/文件/子智能体真实回归
~~~

本项目不是 Codex 官方补丁、模型中转服务或配置分享。仓库不包含 API Key、Token、Cookie、私有日志、编译后的二进制文件或个人配置。

本次问题的关键经验是：Desktop 的 app-server 是多个项目共用的控制面。正在运行时停止 shim、CLI 或 Code Mode host，会让界面看起来仍在运行，但旧任务句柄已经失效，随后出现 thread not found，并可能中断其他开发项目。

## 二、适合谁用？

### 1、特别适合

- Windows 上使用 Codex Desktop 或 Codex CLI 的用户。
- GPT-5.5 正常、GPT-5.6 或更高模型无法调用本地工具的用户。
- 日志出现 code-mode host exited during handshake 的用户。
- 从项目目录启动失败、切换到用户目录却正常的用户。
- 进程链同时出现 C 盘和 E 盘 Codex 安装的用户。
- 日志出现 plugin_marketplace_folder_write_failed 或 bundled_plugins_marketplace_resolve_failed，且 WindowsApps 插件文件带 Encrypted 属性的用户。
- 希望保留 workspace-write 沙箱，并避免打断其他项目的用户。

### 2、不适合

- macOS 或 Linux 用户。
- 账号登录失败、API 余额不足、第三方服务宕机等纯服务端问题。
- 需要绕过权限、关闭沙箱、获取他人凭据或强制修改系统安全策略的场景。
- 已经确认是 MCP 服务自身故障，而不是 Codex Code Mode 或 CLI 启动链路故障的场景。

## 三、它会产出什么？

- 不泄露秘密的本地诊断结果。
- config.toml 时间戳备份。
- 独立版本的 native Windows CWD forwarding shim。
- 只作用于下次启动的用户级 CODEX_CLI_PATH 配置。
- 必要时可生成未加密的本地 bundled marketplace 缓存。
- 终端、文件编辑、子智能体的真实回归结果，以及 PASS、PARTIAL、BLOCKED 或 NOT_RUN 状态。

## 四、具有什么价值？

- 把“工具没了”定位到配置、模型路由、CWD、混用安装、插件缓存或 app-server 生命周期。
- 先诊断和备份，再做可回滚的暂存修改。
- 不用 danger-full-access 掩盖问题，不盲改注册表。
- 不在活跃 Desktop 会话中杀进程或覆盖锁定文件。
- 对主会话和子智能体做端到端验证，而不是只看按钮或 UI 提示。

## 五、示例效果

典型修复前：

~~~text
Codex 又提示没有可用的终端、文件编辑或子智能体管理工具
code-mode host exited during handshake
GPT-5.5 正常，GPT-5.6-sol 失败
~~~

典型验证目标：

~~~text
config.toml parse: ok
terminal command: exit code 0
file edit: create/read/update/delete ok
subagent call: completed
~~~

本次修复中，使用新 shim 和 GPT-5.6-sol 在用户的 Downloads\demo 目录真实执行终端命令成功；文件创建、读取、修改、删除成功；明确指定的 GPT-5.6 子智能体返回成功。每台机器仍必须重新验证，不能把示例当成预先承诺。

## 六、安装方法

~~~powershell
git clone https://github.com/yangjing6213-dev/codex-winfix.git
Set-Location .\codex-winfix
~~~

作为 Codex Skill 使用时，将仓库目录放入：

~~~text
%USERPROFILE%\.codex\skills\codex-winfix\
~~~

目录至少保留 SKILL.md 和 scripts\Repair-CodexWinFix.ps1。

## 七、如何使用

先运行只读诊断：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1
~~~

确认目标目录、模型、provider 和真实 CLI 路径后，再暂存修复：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -StageOnly -ProjectPath "$HOME\Downloads\demo"
~~~

如果 Desktop 仍在运行，StageOnly 只编译独立版本 shim，不修改配置和用户环境。等其他项目可以安全暂停时，完整退出 Desktop，再运行不带 StageOnly 的 Apply 命令：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -ProjectPath "$HOME\Downloads\demo"
~~~

普通 Apply 会先确认没有活跃 Codex 进程，再备份配置并设置用户级环境变量。它不会停止 Codex 进程，不会重启 Desktop，也不会覆盖当前正在使用的固定 shim。

当其他项目可以安全暂停时，用户再完整退出并重新打开 Codex Desktop。随后在目标目录依次验证：

1. 运行一个不会改动项目的终端命令。
2. 创建、读取、修改、删除一个临时测试文件。
3. 发起一次真实子智能体调用。
4. 检查测试文件已删除，并记录每一步状态。

不要通过 Stop-Process 强行释放文件锁，也不要只根据 UI 显示“正在运行”判断成功。

## 八、项目工作流程

~~~text
症状收集
  -> 版本、模型、provider、错误和进程链
  -> config.toml/config.yaml 与 doctor 检查
  -> GPT-5.5 / GPT-5.6 对照
  -> WindowsApps 加密插件缓存检查
  -> 备份配置
  -> 版本化 shim 安全暂存
  -> 正常退出并重启 Desktop
  -> 主会话终端验证
  -> 文件读写验证
  -> 子智能体验证
  -> PASS / PARTIAL / BLOCKED / NOT_RUN
~~~

## 九、项目目录结构

~~~text
codex-winfix/
├── SKILL.md
├── README.md
├── CHANGELOG.md
├── LICENSE
└── scripts/
    └── Repair-CodexWinFix.ps1
~~~

## 十、注意实现

- 默认只读诊断；-Apply 才会备份配置、暂存版本化 shim 和设置用户级变量。
- sandbox_mode 保持 workspace-write，不使用 danger-full-access。
- shim 使用稳定用户目录作为 CWD，清理子进程 PATH 中其他 Codex 安装，并显式指定 real CLI、Code Mode host 和 TERM。
- 发现活跃 Desktop、app-server、shim 或 host 时，绝不停止它们；修复只为下一次正常启动准备。
- 只有日志证明 bundled marketplace 复制失败时，才处理插件缓存；保留完整缓存和旧 staging 证据。
- 不修改系统级环境变量，不盲改 SafeDllSearchMode，不删除会话、数据库或用户项目。
- model_catalog_json 只应指向本机可信且不含秘密的模型目录。
- 第三方 provider 的可用性、认证和模型权限仍需由用户自行确认。

本项目参考了官方仓库 issue openai/codex#32759 中关于 GPT-5.6 Code Mode 握手失败和 Windows CWD shim 的排查经验：
https://github.com/openai/codex/issues/32759

## 十一、版本说明

当前版本：v0.2.0

### v0.2.0

- 总结 GPT-5.5 正常、GPT-5.6+ 工具失败的模型对照排查。
- 增加 WindowsApps 加密插件文件导致 marketplace staging 失败的诊断。
- 增加混用 C 盘/E 盘 Codex 安装和 Code Mode host 路径的处理说明。
- 将固定 shim 热替换改为版本化 shim 安全暂存。
- 增加 StageOnly 模式；普通 Apply 在进程活跃或无法枚举时 fail-closed。
- 明确禁止在活跃 app-server 内停止进程，避免 thread not found 和其他项目中断。
- 增加终端、文件编辑、子智能体三类真实回归要求。

### v0.1.0

- 首个公开版本。
- 提供 Windows Codex 配置诊断、CWD shim 修复路径和配置备份说明。
- 不包含预编译二进制和个人环境文件。

## 十二、相关项目

无。

## 十三、关于作者

### 1、Enhe（恩禾）

- 产品设计师
- 一人公司实践者
- AI Builder

用 AI 打造一个人公司。

- GitHub: [yangjing6213-dev](https://github.com/yangjing6213-dev)
- X/Twitter: [Amenenhe_ai](https://x.com/Amenenhe_ai)
- 网站: [www.enhe-tech.com.cn](https://www.enhe-tech.com.cn/)
- 微信: Hu-Amen
- 邮箱: amen.enhe@gmail.com

[恩禾 ENHE AI | AI工具、AI资讯、账号服务与技能课程](https://www.enhe-tech.com.cn/)

## 十四、继续探索

这个项目是我用 AI 搭建的个人生成系统里的一个工具。如果你也在用 AI 做内容、知识库、工作流或产品化，可以访问 [www.enhe-tech.com.cn](https://www.enhe-tech.com.cn/) 查看更多资料。

## License

[MIT](./LICENSE)
