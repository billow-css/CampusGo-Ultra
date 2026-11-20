# Git 项目动态看板（macOS）

入口：发现 → Git。可在插件设置中开启常驻标签，或将卡片加入摘要。

## 关注项目

- GitHub：点击“添加项目”，输入仓库的 HTTPS 链接或 `owner/repo`，即可查看默认分支的近期提交、开放 PR、开放 Issue 和最近 CI 运行。
- 本地：在添加窗口选择本地项目根目录，读取工作区、全部本地引用的提交图和活跃度。已有书签和仓库列表继续保留。
- 移除关注仅移除入口，保留原文件。

此模块用于查看进展，不提供暂存、提交、分支切换、推送或拉取。项目更新和代码操作请在编辑器或 Git 客户端进行。本地 Git 查询禁用可选锁和外部 fsmonitor。

## 图与动态

- 提交图根据真实提交 hash 和 parent hash 绘制，支持分叉与合并。最多显示最近 80 条；范围以外的父提交连线在边缘结束。本地包含全部已有引用，GitHub 使用默认分支列表，并不代表全部远程分支。
- 本地活跃度显示近 84 天、全部已有引用中按提交作者时间统计的提交。不是 GitHub 个人贡献日历。
- 本地提交可点击查看补丁；GitHub 提交、PR、Issue 和 CI 可点击打开对应网页。
- PR 最近 20 条、Issue 从最近 30 条 issue 记录中排除 PR、CI 最近 10 条。页面计数仅表示已加载列表，不是仓库总量，不是分配给当前用户的任务。
- CI 失败在顶部强调；历史失败不意味着当前分支最近一次构建失败，请点击运行查看详情。

## 刷新与限制

手动刷新会检查 GitHub 的限流等待期。在页面打开、应用回到前台或页面前台计时检查时，距上次请求超过 15 分钟才自动刷新当前项目；不在后台轮询全部仓库。关闭插件取消在途请求。网络失败时保留当前项目上次成功内容和更新时间。

公开仓库可匿名查看。从项目标题旁的钥匙按钮打开访问设置，保存 GitHub 访问令牌可提高请求额度。私有仓库应为细粒度令牌选择仓库，并按需授予 Contents、Pull requests、Issues 和 Actions 读取权限。令牌仅保存在 macOS 钥匙串。

看板会区分限流、令牌无效、权限不足与仓库不可访问。限流期间按 GitHub 响应暂停请求。同一次运行内，切换项目可复用此前成功加载的数据，刷新会通过 ETag 检查内容是否变化。某一动态接口不可用时，其他成功部分仍可查看。

本地查询使用 Apple 命令行工具或 `/Applications/Xcode.app` 中的 Git。目录权限使用本机安全作用域书签；外部 worktree 元数据目录可能需要重新授权。本地远程追踪状态以用户在外部工具最近一次同步为准，不自动 fetch。

接口依据：[GitHub 提交 API](https://docs.github.com/en/rest/commits/commits)、[PR API](https://docs.github.com/en/rest/pulls/pulls)、[Issue API](https://docs.github.com/en/rest/issues/issues)、[Actions API](https://docs.github.com/en/rest/actions/workflow-runs)。
