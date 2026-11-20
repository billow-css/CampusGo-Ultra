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
| navigation | 顶栏独立入口，使用模块 detail 视图 |
| calendarIndicator | 课表日期左侧的小圆点，通过 calendarIndicator(on:calendar:) 返回计数、描述和强调色 |

声明一种能力必须实现对应视图方法；没有实现的能力不要声明。视图方法返回 AnyView?，状态归模块自有的 ObservableObject。适配器可直接给自身视图注入该对象。

## 生命周期与存储

模块注册后调用 setEnabled，之后仅在开关变化时调用。关闭时应暂停工作、取消定时器与后台任务；启用不应悄悄重新开始已暂停的操作。支持 enabledPublisher 将模块设置或右键菜单的开关变化同步回宿主。

ModuleContext.storage 支持 Codable JSON save/load/remove，键带经过校验的模块 ID 隔离。模块实例获得自己的存储对象，不直接读写课表文件。已上线的番茄钟和桌宠继续使用其原偏好键，避免丢失计时、台词与位置；新模块使用独立存储。

模块布局保存在 campus.modules.layout.v1。关闭模块会隐藏卡片但保留位置；从摘要移除仅取消固定，不关闭功能。首次安装采用模块默认固定状态，用户移除后重启不会自动加回。

升级引入新模块时，只对从未出现在已保存 enabled 表中的模块应用 defaultPinned；不会重新固定用户已移除的旧模块。navigation 与 calendarIndicator 能力按注册与启用状态统一挂载，页面不写具体模块 ID 分支。描述符可通过可选 accent 声明固定强调色。模块 changesPublisher 向宿主转发状态变化，让课表标记随计划变更更新；视图自己的状态仍由模块维护。

Agenda 是首个同时实现 summary、detail、navigation 和 calendarIndicator 的模块，使用独立存储。可参考 [Agenda 使用及数据规则](GoSci.md)。声明 navigation 的模块也必须提供 detail 内容。

## 顶栏标签页

Plans 是主应用内置的个人日程与作业页面，不作为可关闭模块注册。设置 → 标签页可隐藏 Plans、发现及模块提供的顶栏入口；摘要和课表始终保留。标签页偏好独立保存在 `campus.navigation.v1`，不会修改计划、作业或模块摘要固定状态。

隐藏当前标签页时返回课表；隐藏模块入口不会关闭模块、移除摘要卡片或课表日期标记。模块处于关闭状态时，在标签页设置中开启其入口会同时启用模块。移除入口后仍可通过发现或摘要打开已启用模块。

模块可通过 `defaultNavigationVisible` 指定顶栏入口的首次默认状态，默认 true；番茄钟为 false。首次引入记录保存在 `campus.navigation.introduced.v1`，重启不会覆盖用户之后设置的显示状态。`ModuleContext.navigationVisible` 为提供 navigation 能力的模块传入可选绑定，可在模块设置中控制常驻入口。

从摘要等入口展开独立内容页时，当前模块若没有可见的常驻入口，则显示带图标、名称和关闭按钮的临时标签；已有常驻入口时直接高亮该入口，不重复显示。临时标签由当前页面派生，退出内容页或切换模块后自动收起，不写入显示偏好。设置页面本身不创建临时标签。

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

模块还可提供可选 `navigationTitle`，由宿主用于常驻及临时标签；变更时通过 changesPublisher 通知宿主。未提供时使用描述符名称。顶栏为超长名称提供固定宽度滚动，避免挤压其他标签。


## Git

`campus.git` 使用相同的注册、启用、摘要卡片和可选标签页接口。仓库书签仅保存在模块本地存储，Git 进程在后台运行，不读取宿主的课程或待办数据。使用边界见 [Git 使用说明](Git.md)。
