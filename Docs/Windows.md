# Windows / Codex 构建交接

Windows 版代码在 `Desktop/`，使用 Tauri 2 + Rust + React/TypeScript。根目录的 SwiftUI 工程仍为 Mac 版；请勿用它构建 Windows。

## 环境

- Node.js 22.12+（或 24 / 26），附带 npm。
- Rust stable，Windows 默认 MSVC 工具链。
- Microsoft C++ Build Tools，安装“使用 C++ 的桌面开发”工作负载及 Windows SDK。
- Microsoft Edge WebView2 Runtime。

官方环境要求：https://v2.tauri.app/start/prerequisites/

安装工具后重新打开终端，让 PATH 生效。若依赖下载失败，检查本机网络、代理和受信任证书；不要复制作者 Mac 的代理地址、证书路径或禁用 TLS 校验。

## 拉取与编译（PowerShell）

```powershell
git clone https://github.com/billow-css/CampusGo-Ultra.git
cd CampusGo-Ultra\Desktop
npm ci
npm run build
npm test
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri build
```

如果已经克隆仓库，先在没有未提交修改的情况下执行 `git pull`，然后进入 `Desktop`。保留 `package-lock.json` 和 `src-tauri/Cargo.lock`，不要为了编译随意升级全部依赖。

NSIS 安装程序输出在 `Desktop/src-tauri/target/release/bundle/nsis/`。这是开发预览版；本次 Windows 构建与安装检查见 [打包记录](Packaging.md)。安装包尚未配置发布者代码签名。

也可在仓库根目录运行可重复打包脚本：

```powershell
powershell -ExecutionPolicy Bypass -File Tools/build-windows.ps1
```

脚本固定构建 `x86_64-pc-windows-msvc`，执行前端 / Rust 测试并使用 Cargo
`--locked`，然后将安装程序、许可证和 SHA-256 校验和复制到
`dist/windows-x86_64/`。指定目标后，Tauri 原始产物位于
`Desktop/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/`。
首次启动安装程序需要 Windows WebView2；若机器未安装，安装程序会联网获取运行时。

## 运行与检查

```powershell
npm run tauri dev
```

首次启动默认课表为空，可点击“先看示例”，或者从设置导入自己的 ICS / 订阅链接。正式数据与示例数据隔离；Tauri 保存至自身应用数据目录，不访问现有 Mac 应用的数据。

浏览器交互测试：

```powershell
npx playwright install chromium
npm run test:e2e
```

浏览器预览：`npm run dev`，默认地址 `http://127.0.0.1:1420`。浏览器版使用 localStorage，订阅下载需要 Tauri 主进程，浏览器检查时用 ICS 文件导入。

## 交付前必查

- 四页切换、紧凑课表、深浅色及窗口缩放正常。
- 在 Windows 上导入 ICS、同步自己的订阅、标记 / 添加考试。
- 添加日程与多行作业子项，退出重开后检查保存；切换演示不写入真实数据。
- 番茄钟循环 / 暂停 / 重开、桌宠选图 / 拖动 / 台词正常。
- 实际运行 NSIS 安装、启动、退出及卸载。记录 Windows 版本、CPU 架构和测试结果。
- 保留原 Mac 版 Release，不用 Windows 预览覆盖 Mac 的 v0.1.0 资产。若之后需要发布 Windows，使用单独的版本说明及附件。

本次已有 Mac 上的前端生产构建、16 项前端逻辑测试、4 项 Playwright 检查、Rust 编译及 4 项测试；这些不能代替 Windows 测试。功能边界见 `Desktop/README.md`。

## 可以交给 Windows Codex 的任务

> 在 Windows 上读取 Docs/Windows.md 和 Desktop/README.md，安装或检查必要环境，在 Desktop 中使用锁文件安装依赖，完成前端 / Rust 测试与 Tauri NSIS 打包；修复实际遇到的 Windows 兼容问题，并实测安装与启动。尽量保留现有界面，避免改动 Mac SwiftUI 版，不上传个人课表、订阅、签名配置或私人桌宠图片。先交付本地安装程序和测试记录。
