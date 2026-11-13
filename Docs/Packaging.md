# 桌面版打包记录 · 2026-11-13

版本：`0.2.0-alpha.1`。基础源码提交：
`eabe31b10c1035625866fbe2a00590679058dfd7`。
本地修改为打包元数据、许可证资源、Linux RPM 配置、构建脚本和文档；
没有修改 Mac SwiftUI 工程或桌面版业务逻辑。Windows 预览包使用独立的
`desktop-v0.2.0-alpha.1` 发布标识，保留原有 Mac 版产物。

## Windows x86_64

- 使用 Rust 1.99.1、MSVC 14.44、Windows SDK 10.0.26100 和 Node.js 24.13.1。
- 生产构建和 16 项前端逻辑测试通过；此前 4 项 Edge / Playwright 交互测试通过。
- MSVC Release 模式下的 4 项 Rust 测试通过，包括 Windows 原子替换和旧版本备份。
- Tauri NSIS 安装程序生成成功，大小为 4,132,643 字节，未配置发布者签名。
- 安装到工作目录成功（退出码 0），安装文件包含主程序、LICENSE、NOTICE 和卸载程序。
- 实际运行安装后的程序，确认从内嵌生产资源加载，不依赖 Vite 开发服务器。
- WebView2 原生检查通过：四页切换、主题切换、Rust 从本地测试服务器下载日历、
  生产资源中的 Worker 解析 ICS；没有前端运行异常，演示检查未改写原生保存状态。
- 测试副本退出并卸载成功（退出码 0），临时调试端口关闭。

上述检查使用本机 Windows 11 x64 和 WebView2 157.0.4341.46，
不能替代其他 Windows 版本、真实订阅服务或全部功能的验证。
最终安装包使用 MSVC；另外下载的 GNU 工具链没有用于本次产物。

## Fedora x86_64

按用户选择交付源码和构建脚本，本机没有编译或运行 Fedora RPM。
Linux 配置通过当前安装的 Tauri CLI JSON Schema 校验，Bash 脚本语法检查通过。
在 Fedora 上执行 `bash Tools/build-fedora.sh --install-deps`，脚本会运行测试、
生成 RPM，并输出依赖列表、文件清单和 SHA-256 校验和。详见 [Fedora 指南](Fedora.md)。

## 重复构建

在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File Tools/build-windows.ps1
```

```bash
bash Tools/build-fedora.sh --install-deps
```

脚本使用 npm / Cargo 锁文件，Rust 测试使用与生产包相同的 Release 模式及
`tauri/custom-protocol` 功能，复用编译缓存。源码套件不包含依赖缓存或编译工具。
