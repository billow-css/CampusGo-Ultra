# CampusGo Ultra · Tauri 桌面预览版

此目录是 Windows / 跨平台版本的首个实现，React + TypeScript 界面、Tauri 2 + Rust 主进程。现有 Mac SwiftUI 应用仍保留在仓库根目录。

界面沿用 Mac 版的顶部下划线导航、紧凑彩色周课表、白底大标题登机牌、橙色考试、右侧上下排列的个人日程与作业，以及独立的作业 / 日程双栏和发现模块库。系统原生控件和字体会随 Windows 改变，SwiftUI 控件无法直接复用。

## 本地预览

安装 Node.js 22.12+（或 24 / 26） 后：

```sh
cd Desktop
npm ci
npm run dev
```

打开终端显示的地址，默认 `http://localhost:1420`。数据初始为空，可点击“先看示例”。演示数据与真实数据隔离；浏览器预览保存在当前浏览器 localStorage。

```sh
npm run build
npm test
npx playwright install chromium
npm run test:e2e
```

Windows 端交接步骤见 [Windows 构建指南](../Docs/Windows.md)。

## Tauri 开发与 Windows 构建

安装 Rust stable。Windows 还需 Microsoft C++ Build Tools 与 WebView2，详见 [Tauri 官方环境要求](https://v2.tauri.app/start/prerequisites/)。

```sh
npm run tauri dev
npm run tauri build
```

Windows 构建输出 NSIS `.exe` 安装程序，位于 `src-tauri/target/release/bundle/nsis/`。请在 Windows 主机上构建并测试；本机 Mac 的检查不能代替 Windows WebView2 与安装器验证。本目录没有自动向 GitHub Release 上传或覆盖现有 Mac DMG。

## 已实现

- 默认课表页、摘要、作业与日程、发现；浅色 / 深色 / 跟随系统与强调色。
- ICS 文件导入，重复事件展开、排除日期和重复例外；后台 Worker 解析。读取范围为过去 180 天至未来 370 天。原有老师与科目编号按来源 / 科目保留。
- Tauri 原生订阅下载支持 HTTP / HTTPS / webcal，超时及 8 MB 上限；浏览器预览不绕过跨域限制，使用 ICS 文件。
- 课次考试标记、手动考试、提前七天提醒、倒计时和每周任务 DDL。
- 个人待办、按科目添加作业、多行子项与完成勾选、唯一作业编号及不复用记录。
- 番茄钟循环、暂停、休眠时间补算、全窗口视图与关闭模块时暂停。
- 模块开关、摘要固定与顺序；窗口内桌宠、自定义图片、大小、拖动、长按、弹跳与多行台词。没有包含私人桌宠图片。
- Rust 本机数据文件、串行写入、原子替换及上一次备份；存储失败可见报错，损坏或未知版本数据不会自动重置。

## 当前边界

这是开发预览版，不是已验证的 Windows 正式安装包。尚未实现 Windows 系统小组件、托盘 / 后台系统提醒、自动更新、Mac 原始 JSON 备份迁移、完整任务编辑和模块拖拽排序；摘要模块当前通过“前移 / 后移”调整。桌宠目前为窗口内显示，保留图片比例但手势边界使用方形占位。

原 Mac 版 JSON 使用 Swift 日期编码，不能直接当作本版数据导入；当前两个应用的数据相互独立。桌面版备份可能包含个人课表、订阅地址与自定义图片，请勿上传。

模块接口仍为内置声明，不加载不可信第三方代码。Tauri 权限仅授予主窗口核心能力，不开放 shell 或任意路径文件接口；订阅下载与存储通过限定的 Rust 命令执行。
