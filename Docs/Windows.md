# CampusGo Ultra Windows 开发指南

从仓库 `main` 开始。Windows 界面使用 `Desktop/` 中的 React、TypeScript 和 CSS；Tauri 2 与 Rust 负责窗口、订阅下载和文件存储。SwiftUI、EventKit 和 WidgetKit 属于 macOS 工程；改动不会自动同步到 Windows。

## 准备环境

- 使用 Windows x64 和 PowerShell。仓库的正式打包脚本针对 `x86_64-pc-windows-msvc`。
- 安装 Git、Node.js 22.12 或以上（可用 24 LTS）及 npm。保留 `package-lock.json` 和 `src-tauri/Cargo.lock`。
- 安装 Visual Studio Build Tools 的「使用 C++ 的桌面开发」工作负载、MSVC 和 Windows SDK，再通过 rustup 安装 Rust stable MSVC 工具链。
- 确认已安装 Microsoft Edge WebView2 Runtime。原生窗口用它渲染；缺失时安装 Evergreen Runtime。更多说明见 [Tauri 环境要求](https://v2.tauri.app/zh-cn/start/prerequisites/)。

重新打开 PowerShell，然后执行：

```powershell
node --version
npm.cmd --version
rustc -vV
rustup default stable-x86_64-pc-windows-msvc

git clone https://github.com/billow-css/CampusGo-Ultra.git
cd CampusGo-Ultra\Desktop
npm.cmd ci
npm.cmd run tauri dev
```

日常改界面也可运行 `npm.cmd run dev`，打开终端显示的本地地址（默认 1420 端口）。浏览器预览用 `localStorage`，可以导入 ICS 文件；订阅下载、原生保存与 Windows 首次访问校验需要实际启动 Tauri。可用「先看示例」体验课表，演示数据与正式数据分开。

## 从哪里改

| 路径（相对 `Desktop/`） | 内容 |
| --- | --- |
| `src/main.tsx`、`src/style.css` | 页面、交互、布局与主题 |
| `src/core.ts`、`src/calendar.worker.ts` | 课程、考试、待办与 ICS 解析 |
| `src/storage.ts`、`src-tauri/src/main.rs` | 前端存储适配、原生数据读写与日历下载 |
| `src/AccessGate.tsx`、`src-tauri/src/access.rs` | Windows 首次访问的本地逻辑，见 [维护说明](Windows-Access-Check.md) |
| `src-tauri/tauri.conf.json`、`src-tauri/windows/` | 应用窗口、权限相关配置及 NSIS 安装钩子 |

新增原生命令时，限制输入、可访问的资源与返回的数据；避免让界面直接执行 shell 命令或读写任意路径。Windows 版没有 macOS 桌面小组件，也不加载 macOS 的 Swift 插件或兼容其原生 JSON 备份。迁移课表可重新导入 ICS 或在 Windows 版重新设置订阅。

## 测试与打包

在 `Desktop/` 中执行：

```powershell
npm.cmd run build
npm.cmd test
cargo test --locked --manifest-path src-tauri/Cargo.toml
npx.cmd playwright install chromium
npm.cmd run test:e2e
```

正式打包从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File Tools/build-windows.ps1
```

脚本执行前端和 Rust 测试，用锁定的 Cargo 依赖构建 x64 NSIS 安装程序，并输出到 `dist/windows-x86_64/`：`CampusGo-Ultra_<版本>_windows-x86_64-setup.exe`、`LICENSE`、`NOTICE` 和 `SHA256SUMS.txt`。原始安装程序在 `Desktop/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/`。脚本不配置发布者签名，也不上传 GitHub Release。

提交前至少在 Windows 实机检查安装、从开始菜单启动、导入 ICS、订阅同步、重启后数据恢复、主题和窗口缩放。若改动首次访问逻辑或安装钩子，额外检查卸载和重装（访问校验标记可能保留）。在报告中注明系统、架构、WebView2 版本和复现步骤，并使用脱敏日志。1.0.0 的历史验证范围见 [发布记录](Release-1.0.0.md)。

遇到 `link.exe` 或 SDK 错误时，检查 C++ 工作负载、`rustc -vV` 的 `host` 是否为 MSVC，必要时用 Developer PowerShell 重试。窗口空白时先检查 WebView2 和 `npm.cmd run tauri dev` 的终端输出。如果只是浏览器预览中的订阅失败，改用 Tauri 或先导入本地 ICS。
