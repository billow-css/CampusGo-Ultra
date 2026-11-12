# CampusGo Ultra

<img width="112" height="112" alt="b143421a-2101-444f-b95f-6ec6777c67f5" src="https://github.com/user-attachments/assets/51d81ac5-cac0-4bba-9c4d-1a6c31c3407d" />

面向大学生的 macOS 原生日程应用，把一周课表、考试、作业和个人待办放在一起。使用 SwiftUI 构建，配套 WidgetKit 桌面小组件，支持本地数据保存与可扩展的内置模块。

> 当前版本为早期开发版，主要界面语言为简体中文。提供未经 Apple 公证的 DMG 测试版，也可自行构建源码。本项目为个人项目，与南京信息工程大学或其他学校无官方隶属关系。

## 下载与安装

前往 [GitHub Releases](https://github.com/billow-css/CampusGo-Ultra/releases) 下载 **DMG 测试版**，支持 macOS 14+、Apple 芯片与 Intel Mac。打开后将应用拖入 Applications（应用程序）。DMG 内附有安装与首次打开教程，完整说明见 [安装指南](Docs/Installation.md)。

测试版采用临时签名，没有 Developer ID 签名与 Apple 公证。首次被系统阻止时，可在确认来源后按教程进入 **系统设置 → 隐私与安全性 → 仍要打开**。小组件跨设备共享数据访问尚未验证，可能需要自行配置签名和 App Group；此操作不会自动补齐这些能力。

## 功能

| 页面 / 功能 | 内容 |
| --- | --- |
| 课表 | 默认启动页，按周显示课程，突出当天课程；显示时间、教室、手动配置的老师和固定五位课程编号；不同学科有稳定配色 |
| 日历来源 | 选择已添加到 macOS 日历的课表，也支持订阅链接或导入 ICS 文件 |
| 摘要 | 登机牌式课程提醒、当前 / 下节课程倒计时、后续课程与考试提醒，以及自选模块卡片 |
| 考试 | 将课表内课程标记为考试，或手动添加考试；橙色强调，提前七天提醒，并同步到小组件 |
| 作业与日程 | 独立双栏页面：左侧个人日程，右侧按科目组织作业；顶部显示状态面板 |
| 作业 | 子任务、进度、备注、置顶、可选截止时间；分配唯一 `H0000`–`H9999` 编号，截止信息同步到课表与提醒 |
| 个人待办 | 标题、图标、置顶、完成勾选及可选时间 / 截止时间 |
| 桌面小组件 | 中号、大号课程登机牌，显示课程、倒计时、考试和作业截止提醒 |
| 发现 | 启用 / 关闭内置模块、打开设置、加入 / 移出摘要，并调整摘要卡片顺序 |
| 番茄钟 | 25 分钟专注、5 分钟休息，支持 1–12 轮循环、暂停恢复及全窗口专注视图 |
| 窗口桌宠 | 自定义图片、拖动位置、大小调整、点击弹跳、长按蓄力和自定义台词；仅在应用窗口内显示 |
| 外观 | 跟随系统 / 浅色 / 深色模式，以及六种强调色 |

### 自定义桌宠图片

前往 **发现 → 窗口桌宠 → 设置 → 选择图片**，或在应用设置的桌宠页面选图。

- 支持 PNG、JPEG 等系统支持的图片格式，建议使用透明 PNG。
- 保留图片比例与透明通道，后台处理为最长边不超过 1024 像素的 PNG 副本；文件上限为 30 MB。
- 副本保存在本机应用支持目录，移动或删除原文件不会影响已导入图片；支持恢复默认。
- 动图目前只使用第一帧。
- **公开仓库不包含作者的私人桌宠图片。** 没有本地图像时显示系统爪印图标；你可以自行选择自己的图片。

## 环境要求

- macOS 14.0 或更高版本。
- Xcode 15 或更高版本，包含 macOS SDK 与 Swift 工具链。
- Python 3：用于重新生成 Xcode 工程。
- 无第三方运行时依赖。

## 快速开始

```sh
git clone https://github.com/billow-css/CampusGo-Ultra.git
cd CampusGo-Ultra
python3 Tools/generate_project.py
open CampusSchedule.xcodeproj
```

在 Xcode 中选择 **CampusGo Ultra** Scheme 运行。首次使用可点击“先看示例”，也可选择 **CampusGo Ultra Demo** Scheme 查看演示数据。演示模式不会覆盖正式课表数据。

### 配置日历

1. 如果学校提供日历订阅，先将其添加到 macOS 自带的“日历”应用。
2. 打开 CampusGo Ultra 的课表设置，授权日历访问并选择对应课表日历。
3. 同步课程后，可在“课程与老师”中补充老师姓名；不填写则不显示。
4. 也可以直接输入自己的订阅地址或导入 ICS 文件。

学校订阅链接可能包含个人访问标识，不要将真实订阅地址或导出的课表提交到仓库。仓库不附带任何个人订阅和日程数据。

### 开发签名与小组件

查看演示界面和运行核心测试不需要配置开发者团队。运行签名应用、访问日历或使用桌面小组件时，需要在自己的开发环境中配置合适的签名与权限。

```sh
cp Signing.example.json Signing.local.json
```

修改本机的 `Signing.local.json`：

- 将 `teamID` 换成自己的 Apple 开发团队标识。
- 将 `appGroup` 换成自己团队可使用的共享组，确保主应用与小组件使用相同值。
- 在 `Tools/generate_project.py` 中为主应用和小组件选择自己的唯一 Bundle ID；分发版本还需同步配置相关能力。
- 重新运行 `python3 Tools/generate_project.py`，在 Xcode 中检查两个 Target 的 **Signing & Capabilities**。

`Signing.local.json` 已被 Git 忽略。不要提交证书、私钥或配置描述文件。小组件依赖主应用和扩展都能访问同一个 App Group；仅主应用本地存储可用时，小组件不能读取该本地回退目录。

命令行检查无签名构建：

```sh
xcodebuild -project CampusSchedule.xcodeproj \
  -scheme "CampusGo Ultra" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

这条命令用于检查编译，生成的无签名产物不等同于可分发、可正常启用小组件的安装包。

添加桌面小组件前，请先运行已正确签名的主应用，选择课表并完成一次同步。小组件由 macOS 管理刷新；应用内倒计时的更新频率与小组件时间线并不相同。

## 测试

```sh
swift test
```

Swift Package 仅包含可独立测试的核心逻辑，不构建整个 SwiftUI 应用。当前包含 121 项核心测试，覆盖日历解析、周课表布局、考试与截止提醒、作业编号、番茄钟状态机、桌宠定位、模块注册与布局，以及数据兼容。

上述测试和无签名编译可用于本地检查。系统授权、桌面小组件注册和完整鼠标交互仍需要在实际 Mac 环境中验证。

## 制作 DMG 测试版

在 macOS 上完成上面的通用无签名 Release 编译后，可运行：

```sh
python3 Tools/package_dmg.py \
  --app "DerivedData/Build/Products/Release/CampusGo Ultra.app" \
  --output dist/CampusGo-Ultra-0.1.0-universal.dmg
```

构建时应指定 `ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`。脚本检查双架构与私人图片排除，为主应用及扩展添加临时签名，生成包含 Applications 快捷入口、安装教程、LICENSE 和 NOTICE 的 DMG，并输出 SHA-256 校验文件。该过程不会进行 Apple 公证，也不授予跨设备共享组能力。

## 项目结构

```text
App/                      SwiftUI 页面、状态管理和模块适配器
Shared/                   课表 / 作业模型、解析、提醒、共享存储与布局
Widget/                   WidgetKit 扩展入口
Resources/                应用图标；不包含私人桌宠图片
Configuration/            Info.plist、沙盒与共享组权限
Tests/                    Swift Package 核心测试
Tools/                    Xcode 工程和图标生成工具
Design/                   应用图标源图
Docs/Modules.md            内置模块接口说明
CampusSchedule.xcodeproj/  主应用与小组件工程
```

`CampusSchedule`、部分 `NUISTGo` 内部名称与旧 Scheme 保留用于兼容；当前产品名称为 **CampusGo Ultra**。

## 模块接口

目前使用编译进应用的统一原生模块接口，支持：

- 稳定 ID、版本、描述和界面能力声明。
- 摘要卡片、独立页面、设置与窗口悬浮层。
- 启用 / 关闭生命周期及摘要固定和排序。
- 独立存储与明确声明的数据访问能力。

番茄钟与桌宠通过同一套接口注册。关闭番茄钟会暂停计时并停止刷新；关闭桌宠会移除悬浮层。详见 [模块接口说明](Docs/Modules.md)。

**当前不支持下载、安装或执行外部第三方插件。** 接口中的权限声明是进程内编程约束，并非针对不可信代码的隔离机制。

## 数据与隐私

- 日程、作业、老师信息、考试及设置保存在本机；仓库不附带用户数据。
- 配置了共享组时，课表快照供主应用与小组件共同读取；主应用还支持本地存储回退与备份恢复。
- 自定义桌宠图片会复制到本机应用支持目录，不上传到 GitHub。
- 日历来源可能通过 EventKit 或用户指定订阅地址联网读取。
- 旧评价页面与评分逻辑已移除；旧备份中的评价字段只保留兼容读写，以避免保存课表时意外丢失旧记录。

## 贡献

欢迎通过 Issues 提交问题和建议，或通过 Pull Request 改进代码。报告问题时请附上 macOS / Xcode 版本、复现步骤与必要的脱敏信息。新增 Swift 文件后运行工程生成工具，并执行核心测试和应用编译。

请勿提交私人课表、订阅地址、用户备份、开发签名或未经授权的图片。个人桌宠图片可在本机导入，不需要加入源码。

## 许可证

本项目采用 **Apache License 2.0**，完整文本见 [LICENSE](LICENSE)。作者的私人桌宠图片未包含在公开仓库中，也不在本次开源授权范围内。自行导入图片时请确认具有相应使用权。
