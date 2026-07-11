<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="CodexLoginManager icon">
</p>

<h1 align="center">CodexLoginManager</h1>

<p align="center">
  一个原生 macOS SwiftUI 小工具，用于检查 Codex CLI 登录状态并启动官方 ChatGPT OAuth 登录流程。
</p>

<p align="center">
  <a href="https://github.com/xiaohei210509/CodexLoginManager/actions/workflows/build.yml"><img src="https://github.com/xiaohei210509/CodexLoginManager/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

CodexLoginManager 不自行实现或接管 OAuth。它只读取本机登录状态，并调用官方 `codex` 命令执行 `login status` 或 `login`。

## 功能

- 自动查找新版 ChatGPT app、旧版 Codex app 或 `PATH` 中的 Codex CLI。
- 检查 `~/.codex/auth.json` 中的登录模式，但不显示或保存 token 内容。
- 调用 `codex login status` 确认 ChatGPT OAuth 登录是否有效。
- 一键启动官方 `codex login` 浏览器授权流程。
- 对界面中显示的 API key、OAuth token 和 JWT 进行脱敏。
- 不直接修改 `~/.codex/config.toml`，不包含遥测或第三方网络请求。

## 系统要求

- macOS 14 或更高版本
- Swift 6 / Xcode 16 或更高版本
- 以下任意一种 Codex CLI 安装方式：

| 安装方式 | CLI 路径 |
| --- | --- |
| ChatGPT app（当前版本） | `/Applications/ChatGPT.app/Contents/Resources/codex` |
| Codex app（兼容旧版本） | `/Applications/Codex.app/Contents/Resources/codex` |
| 独立 CLI | `PATH` 中可执行的 `codex` |

## 从源码运行

```bash
git clone https://github.com/xiaohei210509/CodexLoginManager.git
cd CodexLoginManager
./script/build_and_run.sh
```

脚本会在 `dist/CodexLoginManager.app` 生成本地 ad-hoc 签名的应用并启动它。

仅构建应用包：

```bash
./script/build_and_run.sh --build
```

构建并检查应用能否启动：

```bash
./script/build_and_run.sh --verify
```

## 开发与测试

```bash
swift test --disable-index-store -j 1
```

GitHub Actions 会在 macOS runner 上运行单元测试、构建 `.app` 包，并验证其签名和 `Info.plist`。

## 隐私与安全

- 应用只在本机读取 `~/.codex/auth.json`，不会把文件内容发送到自己的服务器。
- 浏览器授权由官方 Codex CLI 发起；本应用不接收 GitHub、ChatGPT 或 OpenAI 密码。
- CLI 输出在显示前会经过脱敏，但仍建议不要把包含个人路径或账户状态的截图公开发布。
- 本项目初始版本只发布源码，不提供经过 Apple Developer ID 签名或公证的二进制文件。

## 许可证

本项目使用 [MIT License](LICENSE)。

## 声明

这是一个独立的社区项目，不是 OpenAI 官方产品，也不代表 OpenAI。ChatGPT、Codex 和 OpenAI 是其各自权利人的商标。
