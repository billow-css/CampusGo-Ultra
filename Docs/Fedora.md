# Fedora x86_64 RPM 构建与部署

桌面版使用 `Desktop/` 内的 Tauri 2 + Rust + React。Linux 配置自动合并
`Desktop/src-tauri/tauri.linux.conf.json`，生成 RPM；Windows 仍生成 NSIS 安装程序。

## 在 Fedora 上构建

解压交付的源码包，进入包含 `Desktop/` 和 `Tools/` 的项目根目录：

```bash
# 首次构建：安装 Fedora 开发依赖、Node.js、Rust 和 Cargo，然后构建。
bash Tools/build-fedora.sh --install-deps

# 已配置环境时，只检查环境，或直接构建。
bash Tools/build-fedora.sh --check
bash Tools/build-fedora.sh
```

脚本需要联网下载锁文件指定的 npm / Cargo 依赖。Node.js 需要 22.12+；
Rust 需要 1.90+（锁文件内 Tauri 的最低要求），建议使用 stable。如果 Fedora 仓库中的 Rust 太旧，按
[Rust 官方说明](https://www.rust-lang.org/tools/install)安装 stable，重新打开终端。
构建过程使用 `npm ci` 与 Cargo `--locked`，不会主动升级项目依赖。
系统依赖只在显式传入 `--install-deps` 时通过 `sudo dnf install` 安装。
Silverblue / Kinoite 请先进入 Fedora Toolbx 容器；脚本不自动修改 OSTree 主机。

脚本依次执行前端生产构建、16 项前端逻辑测试、Rust 测试、Tauri RPM 打包，
随后检查 RPM 架构和主程序文件，并生成依赖列表、文件清单和 SHA-256 校验和。
输出目录为 `dist/fedora-x86_64/`。首次编译 Rust 依赖可能需要较长时间。

## 安装与卸载

```bash
cd dist/fedora-x86_64
sha256sum -c SHA256SUMS.txt
sudo dnf install ./campusgo-desktop-*.rpm
campusgo-desktop

# 卸载应用，保留个人数据。
sudo dnf remove campusgo-desktop
```

也可以从 GNOME / KDE 应用菜单启动 CampusGo Ultra。运行需要桌面会话及
WebKitGTK 4.1 / GTK 3；使用 `dnf install` 让包管理器解析依赖。
包包含 Apache-2.0 LICENSE 与 NOTICE。RPM 尚未配置发布者签名。

## 兼容性与验证边界

在计划支持的最旧 Fedora 版本上构建，并在同版本或更新版本上测试。
不能保证在较新系统上编译的二进制能在较旧系统运行，也不能直接使用 Windows
生成的 `.exe` 作为 Linux 程序。本脚本目标为 x86_64，不涵盖 ARM64。

本次 Windows 主机交付的是 Fedora 构建脚本和源码，没有生成或实测 RPM。
脚本成功后仍需在目标 Fedora 桌面验证：安装 / 启动 / 卸载、四页切换、ICS 导入、
原生订阅下载、个人日程保存并重启恢复、深浅色、番茄钟和桌宠。
浏览器测试不能替代 Linux WebKitGTK 或 Windows WebView2 的原生验证。

参考：[Tauri Linux 环境要求](https://v2.tauri.app/start/prerequisites/#linux)、
[Tauri RPM 打包与兼容性](https://v2.tauri.app/distribute/rpm/)。
