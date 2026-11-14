# 1.0.0 LTS for Windows/Fedora

桌面版 npm、Cargo 和 Tauri 版本统一为 `1.0.0`。
GitHub 使用 `v1.0.0` 标签，将原桌面预发布条目更新为正式发布；Mac `v0.1.0` 与 DMG 产物保留。

## 产物

- `CampusGo-Ultra_1.0.0_windows-x86_64-setup.exe`：Windows x64 NSIS 安装包。
- `CampusGo-Ultra_1.0.0_Fedora-build-kit.zip`：当前桌面版源码与 Fedora RPM 构建脚本。
- `SHA256SUMS.txt`：上述附件的 SHA-256。

Fedora 附件不是预编译 RPM；在 Fedora 上运行
`bash Tools/build-fedora.sh --install-deps` 生成 RPM。
本次没有在 Fedora 编译或实测，兼容性以目标系统构建和运行检查为准。

## 验证范围

1.0.0 使用最新桌面版代码，仅统一版本号和发布文档。生产构建成功。
此前对应代码的 8 项 Windows Rust 测试通过；原生集成检查覆盖首次校验、通过后重启、
应用内限制弹窗、退出操作、业务命令拦截，以及卸载后交互式 / 静默重装检查。
安装集成测试使用同一主程序与隔离的安装器标识，保留原有安装和数据。
相关功能与维护说明见 [Windows 本地访问校验](Windows-Access-Check.md)。

Windows 安装包尚未配置发布者签名，需要 WebView2；缺少时安装器会联网获取运行时。
功能边界沿用桌面版说明，不包含自动更新、系统小组件或 Mac 数据迁移。
