# Codex Computer Use Fix

一个给 Windows 版 Codex 用的修复 skill。它主要解决：Codex 更新、重启、重装之后，突然显示 **Computer Use 插件不可用**，或者本地插件图标损坏、插件列表消失。

## 一句话介绍
使用方法：
把这个仓库地址发给 Codex，让它安装 `skills/computer-use-fix` 目录下的 skill，然后运行修复。

这个项目把一次已经验证过的修复流程整理成 skill。它主要处理的问题是：Codex 会把临时插件缓存 `.codex\.tmp\bundled-marketplaces\openai-bundled` 重建成不完整状态，导致 Computer Use 或其他 bundled 插件看起来像“丢了”。修复方式是把官方安装包里的 bundled 插件复制到一个稳定目录，再让 Codex 以后读这个稳定目录。

## 适合什么情况

- Codex 设置页显示 `Computer Use plugin unavailable`。
- 之前 Computer Use 能用，关闭/重开 Codex 后又不能用。
- Codex 更新后 Computer Use、LaTeX、Browser、Chrome、Sites 等本地插件不显示。
- 插件页面图标坏了，或者 `openai-bundled` 从插件列表里消失。
- `.codex\.tmp\bundled-marketplaces\openai-bundled` 里面只剩 `chrome` 之类的不完整内容。

## 详细用法

打开这个 GitHub 仓库后，把仓库地址发给 Codex，然后说：

```text
安装这个仓库里 skills/computer-use-fix 目录下的 skill。
```

安装后重启 Codex，再说：

```text
使用 computer-use-fix 修复 Computer Use。
```

如果你不想先安装，也可以让 Codex 直接打开这个仓库里的 `SKILL.md` 和修复脚本，让它照着做。

## Codex 会做什么

Codex 会按 skill 运行这个脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\computer-use-fix\scripts\repair-codex-windows-computer-use.ps1
```

脚本会自动：

- 找到当前安装的 Windows Store 版 `OpenAI.Codex`。
- 把官方 `openai-bundled` 插件 marketplace 复制到 `%USERPROFILE%\.codex\marketplaces\openai-bundled`。
- 修复 `%USERPROFILE%\.codex\config.toml` 里的插件路径和开关。
- 启用 `computer-use@openai-bundled`。
- 设置 `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`。
- 备份原来的 `config.toml`。

修完后，完全退出并重新打开 Codex。必要时新建一个对话，Computer Use 才会被注入到新对话里。

## 手动运行

如果你想自己在 PowerShell 里运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\computer-use-fix\scripts\repair-codex-windows-computer-use.ps1 -Force
```

## 安全说明

- 不会直接修改 `C:\Program Files\WindowsApps`。
- 不包含个人路径、账号、密码或 token。
- 会先备份 `config.toml` 再改配置。

## License

MIT
