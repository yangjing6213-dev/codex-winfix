# codex-winfix

Windows Codex 工具链修复 Skill，针对 Codex 提示“没有可用的终端、文件编辑或子智能体管理工具”，以及 `code-mode host exited during handshake`、CWD 转发和配置加载异常。

## 一、这个仓库是什么？

这是一个轻量、可复用的 Codex Skill 和 PowerShell 修复脚本。它把经过验证的 Windows 排查路径整理为：配置检查、CLI 启动路径修复、CWD shim 构建、Desktop 重启和真实工具验证。

它不是 Codex 官方补丁，也不是代理服务或模型配置分享。仓库不包含 API Key、Token、Cookie、私有日志、个人配置或编译后的二进制文件。

## 二、适合谁用？

### 1、特别适合

- Windows 上使用 Codex Desktop 或 Codex CLI 的用户。
- Codex 界面能打开，但终端、文件编辑或子智能体工具不可用的用户。
- 日志出现 `code-mode host exited during handshake` 的用户。
- 从特定项目目录启动时失败、切换到用户目录却正常的用户。
- 希望保留 `workspace-write` 沙箱并进行可回滚修复的用户。

### 2、不适合

- macOS 或 Linux 用户。
- 账号登录失败、API 余额不足、第三方服务宕机等纯服务端问题。
- 需要绕过权限、关闭沙箱、获取他人凭据或强制修改系统安全策略的场景。
- 已经确认是 MCP 服务自身故障，而不是 Codex Code Mode/CLI 启动链路故障的场景。

## 三、它会产出什么？

- 一份不泄露秘密的本地诊断结果。
- `config.toml` 的时间戳备份。
- 可选的 native Windows CWD forwarding shim 源码和可执行文件。
- 用户级 `CODEX_CLI_PATH`、`CODEX_REAL_CLI_PATH` 指向。
- 重启 Desktop 后的终端、文件编辑和子智能体验证结果。

## 四、具有什么价值？

- 把“看起来像工具没了”的症状定位到配置、启动路径、CWD 或 Code Mode 握手层。
- 默认先诊断，修改前备份，避免盲改配置。
- 保持 `workspace-write`，不以 `danger-full-access` 掩盖问题。
- 对配置、CLI、Desktop 和子智能体进行端到端验证，而不是只看 UI 状态。
- 适合个人复用，也适合整理为团队故障处理手册。

## 五、示例效果

典型修复前：

```text
Codex 又提示没有可用的终端、文件编辑或子智能体管理工具
code-mode host exited during handshake
```

典型修复后应分别验证：

```text
config.toml parse: ok
app-server: initialized successfully
terminal command: exit code 0
file edit: create/read/update/delete ok
subagent call: completed
```

这些是验证目标，不是对所有机器的预先承诺。若任一步失败，应保留为 `BLOCKED` 或 `PARTIAL`，继续定位真实原因。

## 六、安装方法

### 方式 A：直接使用仓库脚本

```powershell
git clone https://github.com/yangjing6213-dev/codex-winfix.git
Set-Location .\codex-winfix
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1
```

### 方式 B：作为 Codex Skill 安装

将本仓库目录复制到 Codex 的 skills 目录，例如：

```text
%USERPROFILE%\.codex\skills\codex-winfix\
```

Skill 目录至少需要保留 `SKILL.md` 和 `scripts\Repair-CodexWinFix.ps1`。

## 七、如何使用

1. 先运行诊断，不修改文件：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1
   ```

2. 确认目标目录存在，并检查诊断输出没有指向错误的 CLI、模型或认证问题。

3. 应用修复并指定测试目录：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -ProjectPath "$HOME\Downloads\demo"
   ```

4. 完全退出并重新启动 Codex Desktop，让 app-server 重新加载配置。

5. 在目标目录中依次验证终端、文件编辑和子智能体。不要只根据“工具按钮出现”判断修复完成。

如已有 shim 源码，脚本默认拒绝覆盖；确认需要重建时再加 `-Force`。

## 八、项目工作流程

```text
症状收集
  -> 读取版本与错误
  -> 检查 config.toml/config.yaml
  -> 检查模型目录与 provider
  -> 检查真实 codex.exe 与 CWD 启动路径
  -> 备份配置
  -> 构建并设置 shim（必要时）
  -> 重启 Codex Desktop
  -> 主会话终端验证
  -> 文件读写验证
  -> 子智能体验证
  -> 记录 PASS / PARTIAL / BLOCKED
```

## 九、项目目录结构

```text
codex-winfix/
├── SKILL.md
├── README.md
├── LICENSE
└── scripts/
    └── Repair-CodexWinFix.ps1
```

## 十、注意实现

- 默认模式是只读诊断；`-Apply` 才会备份配置、修复根级模型/provider/catalog/sandbox/agent 字段、构建 shim 和设置用户级环境变量。
- 只使用用户级环境变量，不修改系统级变量。
- 不输出或保存 API Key、Token、Cookie、密码、完整私人日志或第三方 API 地址。
- 不要求修改注册表，不建议关闭 `SafeDllSearchMode`。
- 不使用 `danger-full-access` 代替真正修复。
- `model_catalog_json` 只应指向本机可信且不含秘密的模型目录；不要把真实配置直接提交到公开仓库。
- 第三方 provider 的可用性、账号认证和模型权限仍需由用户自行确认。
- 该脚本不会自动重启 Desktop，也不会自动删除用户文件。

## 十一、版本说明

当前版本：`v0.1.0`

- 首个公开版本。
- 提供 Windows Codex 诊断与 CWD shim 修复路径。
- 提供配置备份和端到端验证说明。
- 不包含预编译二进制和任何个人环境文件。

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
