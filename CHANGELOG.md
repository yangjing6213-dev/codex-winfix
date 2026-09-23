# Changelog

## v0.2.0 - 2026-09-23

- 总结 GPT-5.5 正常、GPT-5.6+ 工具失败的模型对照排查。
- 增加 WindowsApps 加密插件文件导致 bundled marketplace staging 失败的诊断。
- 增加混用 C 盘/E 盘 Codex 安装和 Code Mode host 路径的处理说明。
- 将固定 shim 热替换改为版本化 shim 安全暂存。
- 增加 StageOnly 模式；普通 Apply 在进程活跃或无法枚举时 fail-closed。
- 明确禁止在活跃 app-server 内停止进程，避免 thread not found 和其他项目中断。
- 增加终端、文件编辑、子智能体三类真实回归要求。

## v0.1.0 - 2026-09-22

- 首个公开版本。
- 提供 Windows Codex 配置诊断、CWD shim 修复路径和配置备份说明。
