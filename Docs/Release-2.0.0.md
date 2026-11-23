# CampusGo Ultra 2.0.0

`main` 合并了 `Mac-Addon`，同时保留 Windows/Fedora 1.0.0 的 Tauri 实现。macOS 主应用与小组件、Tauri 桌面端统一使用 `2.0.0`；两套应用仍各自构建、独立保存数据。

- **macOS**：Agenda、Git 项目看板、原生提交 / PR / Issue / CI 详情、TCP 单页浏览器及本地样式、顶部标签页动画。
- **Windows/Fedora**：保留现有 Tauri 功能和打包脚本；上述 Swift 模块没有移植到 Tauri。
- **开发文档**：[外部插件开发指南](PluginDevelopment.md)、[Windows 开发指南](Windows.md)。应用版本升到 2.0.0，macOS 模块接口仍为 v1，贡献的模块通过源码编译。

此版本记录对应源码。各平台安装包需单独构建和验证；[1.0.0 的 Windows/Fedora 验证记录](Release-1.0.0.md)不适用于 2.0.0 安装包。
