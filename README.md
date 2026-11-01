# DailyToDo · macOS

本地保存的原生 Mac App。主窗口只有「日程 / 倒计时」两项；日程使用月历或七列周历，点击日期空白新建、点击事项在右侧编辑。桌面卡片左侧浏览今天起七天的未完成待办，右侧浏览倒计时。

完成事项在 App 原日期勾选划线保留，在卡片中消失。非周期待办当天未完成会自动顺延；离线多天后补移到今天。每日/每周固定待办保留各次日期。主题颜色、类型名称和类型颜色均可自定义。

## 安装预览

运行 `./scripts/package-app.sh` 生成 Apple silicon 本机预览包 `dist/DailyToDo-macOS-arm64-preview.zip`，解压后将 DailyToDo.app 放到本机 Applications 文件夹打开。当前机器安装副本位于 `~/Applications/DailyToDo.app`。

这是供人工验收的 **0.1.0 build 16 本机预览**：已做沙盒 ad-hoc 签名及解压验证，未做 Developer ID 公证。当前实测 macOS 26.6.2、Apple silicon；macOS 14 为部署目标，最低系统和 Intel 未实测。

本轮交付状态与建议验收顺序见 [HANDOFF.md](docs/HANDOFF.md)。

使用方法及验收步骤见 [ACCEPTANCE.md](docs/ACCEPTANCE.md)，实现证据与待验证项目见 [IMPLEMENTATION.md](docs/IMPLEMENTATION.md)，详细产品边界见 [PLAN.md](PLAN.md)。真实 Release GUI 基线及测量边界见 [GUI_PERFORMANCE.md](docs/GUI_PERFORMANCE.md)。

## 使用

- 点击日历日期下的空白或顶部 + 添加；点击事项修改。日期格内没有加号。
- 待办必填日期、事项和类型，时分选填；周/月日历只显示事件名称；重复规则在同一表单设置。倒计时只必填日期和事件。
- 卡片左右日期/箭头切换，列表上下滚动；卡片标题区可拖动，设置可显示、隐藏或置顶。
- 类型可在表单内新建/管理；重复规则和最近删除从对应页面「更多」进入。设置可导出 JSON 备份、替换恢复。
- ⌘N 新建待办，⇧⌘N 新建倒计时，⌘↩ 保存，⇧⌘↩ 保存并继续，⌘F 搜索，⌘, 设置。文本内 ⌘Z 撤销文字；⌥⌘Z 撤销最近支持的业务操作。
- 关闭主窗口不退出 App，可通过菜单栏或 Dock 找回；真正退出后卡片消失。提醒和登录启动默认关闭。
- 第一次在表单主动选择提醒会请求通知权限；拒绝仍可保存事项。点击有效通知可打开当前事项，已完成记录保留；已失效通知不会恢复删除数据。边界见 [NOTIFICATIONS.md](docs/NOTIFICATIONS.md)。

## 工程

| 目录 | 职责 |
| --- | --- |
| Sources/TodoDomain | 日期、值模型、校验、重复与提醒计算 |
| Sources/TodoPersistence | Core Data SQLite、范围查询、串行命令、修订与恢复 |
| Sources/TodoInteraction | 可测试的滚动、月历布局、颜色及位置计算 |
| Sources/TodoServices | 可替换通知/登录/偏好/定时器与队列核对 |
| Sources/DailyToDo | SwiftUI/AppKit 窗口、卡片、草稿与系统服务 |
| Tests | 151 项领域、事务、恢复、业务、系统服务、模型与交互测试 |
| Tools/Benchmark | 独立临时 SQLite 的性能基线 |
| scripts / Resources / docs | 构建打包、资源、说明与验收记录 |

各目录包含模块 README。无第三方包、账户或服务依赖。

独立Xcode UI入口见[UITests/README.md](UITests/README.md)：共享工程、scheme、测试计划和10个用例已提供。当前仅完成结构/语法检查与同源界面的原生操作核对，尚未在完整Xcode运行；10个用例不计入142项已通过测试。

## 构建与验证

需要 Mac、Swift 6 工具链、macOS SDK 和 Python 3（构建输出保护使用标准库，无第三方依赖）。CLT 可构建，不要求完整 Xcode。

```sh
./scripts/test.sh
python3 -m unittest discover -s scripts/tests -v
./scripts/build-app.sh debug
./scripts/package-app.sh
swift run -c release TodoBenchmark --output docs/benchmark.json
```

`package-app.sh --install-local` 另外安装到 `~/Applications`。默认运行不填入示例；合成验收推荐 `./scripts/run-ui-preview.sh acceptance-20261031`，脚本拒绝重复进程并使用独立测试库。详见 scripts/README.md。

名称更新保留 `local.tododesktop.mac`、原本机数据路径及 V1 存储模型，已有记录无需迁移。旧截图和 V24 之前记录使用当时名称；当前工程检查见 [ENGINEERING_CHECK.md](docs/ENGINEERING_CHECK.md)。

V26默认固定卡片在桌面，其他窗口可以覆盖；可选置顶。App需后台运行，退出后卡片关闭。实现与原生验收边界见[DESKTOP_CARD.md](docs/DESKTOP_CARD.md)。

时分留空不会补成00:00，也不显示已过时间；每日/每周可不设时间，重复相对提醒仍需具体时分。详情见[OPTIONAL_TIME.md](docs/OPTIONAL_TIME.md)。
