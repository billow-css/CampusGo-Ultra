# CampusGo Ultra 外部插件开发指南

欢迎在自己的 fork 中开发模块，或通过 Pull Request 提交给主项目。当前的模块接口 v1 是 **macOS Swift 源码接口**：模块随应用编译和分发。已安装的应用不能加载外部二进制或脚本。Windows/Fedora 使用 `Desktop/` 下独立的 Tauri 实现，不能运行这些 Swift 模块。

## 从一个摘要卡片开始

1. Fork 仓库，从 `main` 新建分支。在 `App/ReadingModule.swift` 写入以下代码：

   ```swift
   import SwiftUI

   @MainActor
   struct ReadingModule: CampusModule {
       let descriptor = ModuleDescriptor(
           id: "example.reading",
           name: "今日阅读",
           description: "在摘要展示当天的阅读提示。",
           icon: "book",
           surfaces: [.summary]
       )

       func summaryCard(context: ModuleContext) -> AnyView? {
           AnyView(Label("今天读一页", systemImage: "book"))
       }
   }
   ```

2. 在 `App/CampusModules.swift` 的 `ModuleHostState` 中，把 `ReadingModule()` 加进传给 `ModuleManager(modules:defaults:)` 的数组。发布前用你自己的命名空间替换 `example`。ID 一旦发布就保持稳定：启用状态、卡片位置和存储都依赖它。
3. 在仓库根目录运行 `python3 Tools/generate_project.py`，打开 `CampusSchedule.xcodeproj`，运行 **CampusGo Ultra Demo** Scheme。进入「发现」，把「今日阅读」加入摘要。确认关闭模块后卡片隐藏，重新开启后恢复原位置。
4. 提交新 Swift 文件、注册改动及生成后的 Xcode 工程。运行 `swift test` 检查核心逻辑，并按 [README](../README.md) 编译主应用。`swift test` 本身不会编译 `App/` 中的 SwiftUI 模块。

## 扩展能力与数据

- 摘要、详情、设置、悬浮层、顶栏入口和课表日期标记分别声明在 `surfaces`。如果声明 `.navigation`，同时声明 `.detail` 并实现详情视图。使用 `context.openDetail()`、`context.openSettings()` 和 `context.close()` 让宿主管理跳转。
- 模块私有数据通过 `context.storage` 保存。用 `Codable` 类型表示存储数据；修改结构时保留旧值读取能力。需要读课表、读待办或写作业时，在描述符中声明对应的 `ModulePermission`，再调用 `context.data`。未经声明的调用会失败，界面应能处理失败。
- 带定时器、网络或后台任务的模块，在 `setEnabled(false)` 中停止工作。耗时操作不要阻塞主线程；外部服务不可用时保留其他页面可用。
- 权限声明是宿主接口的调用约束。模块与主应用在同一进程运行，因此维护者需要审查代码及依赖。不要提交访问令牌、真实订阅地址、签名文件、私人图片或用户数据。

[模块接口参考](Modules.md) 列出了全部能力、生命周期和权限。番茄钟是摘要、设置与独立页面的参考；[Agenda](GoSci.md) 展示日期标记和计划数据；[Git](Git.md) 展示带外部服务的原生模块。

提交 PR 时说明模块解决的问题、提供的界面、申请的数据权限、外部服务与依赖，以及如何复现并验证。用示例数据附上浅色与深色界面截图；如果涉及联网，补充离线和失败时的表现。
