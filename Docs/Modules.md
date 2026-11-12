# CampusGo Ultra 模块接口 v1

当前是编译进应用的原生 Swift 模块接口。没有动态加载、不可信代码执行、下载市场或远程更新能力。新增模块只需注册一次，发现、摘要与悬浮宿主按能力展示；不需要在导航中新增模块专属判断。

## 组成

- Shared/Modules.swift：描述符、注册校验、布局和独立 JSON 存储，无 SwiftUI 依赖，可单独测试。
- App/CampusModules.swift：CampusModule、ModuleContext、ModuleDataAccess、ModuleManager，以及番茄钟和桌宠适配器。
- App/DiscoveryView.swift：统一发现页、摘要卡片宿主、页面和悬浮宿主。

描述符包含稳定 ID、显示名、说明、SF Symbol、模块版本与接口版本，以及 surfaces 和 permissions。ID 为 3–80 位小写 ASCII 字母、数字、点、连字符或下划线，必须以字母开头。重复 ID、未知接口版本及无界面能力的模块在注册时拒绝。

## 界面能力

| surface | 提供内容 |
|---|---|
| summary | 摘要小卡片，可加入、移除、拖动排序 |
| detail | 全窗口内容页，通过 context.openDetail / close 导航 |
| settings | 模块设置，公共启用开关由宿主提供 |
| overlay | 仅模块启用时存在的窗口悬浮层 |

声明一种能力必须实现对应视图方法；没有实现的能力不要声明。视图方法返回 AnyView?，状态归模块自有的 ObservableObject。适配器可直接给自身视图注入该对象。

## 生命周期与存储

模块注册后调用 setEnabled，之后仅在开关变化时调用。关闭时应暂停工作、取消定时器与后台任务；启用不应悄悄重新开始已暂停的操作。支持 enabledPublisher 将模块设置或右键菜单的开关变化同步回宿主。

ModuleContext.storage 支持 Codable JSON save/load/remove，键带经过校验的模块 ID 隔离。模块实例获得自己的存储对象，不直接读写课表文件。已上线的番茄钟和桌宠继续使用其原偏好键，避免丢失计时、台词与位置；新模块使用独立存储。

模块布局保存在 campus.modules.layout.v1。关闭模块会隐藏卡片但保留位置；从摘要移除仅取消固定，不关闭功能。首次安装采用模块默认固定状态，用户移除后重启不会自动加回。

## 数据能力

ModuleDataAccess 通过值快照和明确操作访问数据，不暴露 AppStore、共享文件路径或学校订阅地址。调用前检查描述符权限：readCourses、readHomework、readTodos、createTodo、writeHomework。未经声明的调用抛出 missingPermission。当前两个内置模块均不申请课表或作业权限。

这是同一进程内的编程约束，不是面向不可信外部代码的安全隔离。将来开放第三方模块时，需要另行设计独立进程、用户授权和消息协议，不能直接加载任意 Swift 代码。

## 新增模块示例

```swift
@MainActor
struct ExampleModule: CampusModule {
    let descriptor = ModuleDescriptor(
        id: "campus.example", name: "示例", description: "模块说明",
        icon: "sparkles", surfaces: [.summary, .detail])
    func summaryCard(context: ModuleContext) -> AnyView? {
        AnyView(Button("打开", action: context.openDetail))
    }
    func detail(context: ModuleContext) -> AnyView? {
        AnyView(Button(context.returnTitle, action: context.close))
    }
}
```

在 ModuleHostState 初始化的注册数组中添加 ExampleModule()，再运行工程生成工具更新新文件并构建。不要往 DiscoveryView 或 HomeView 添加模块 ID 分支。

## 旧评价数据

评分、评论、列表、编辑器及随机预览逻辑均已删除。LegacyReviewRecord 只维持旧备份的 JSON 字段兼容；没有对应的 UI、评分校验或修改入口。这样后续保存课表时不会意外抹掉已有个人记录。
