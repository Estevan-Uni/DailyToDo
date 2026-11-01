# DailyToDo

原生 macOS 14+ 应用。安排仅包含“日程”和“倒计时”，默认日程为月历；周切换为七个日期列。新增或点击事项时才出现右侧编辑栏。完成事项在日历原日期勾选划线保留，桌面卡片只显示未完成事项。

- `App`：场景、共享可观察状态、命令调度、草稿离开保护与文件备份恢复。
- `Features`：日历、倒计时、按需编辑栏、桌面卡片、类型/规则/最近删除管理、设置。
- `Services`：午夜与系统事件刷新、时钟环境、文件/窗口服务、确认与GUI测量；通知/登录命令委托TodoServices。

UI 使用 TodoDomain 值快照。数据库写入统一交给 TodoRepository actor，不在视图中修改 Core Data 对象。文本输入只改独立草稿，显式保存时检查字段与修订号。

AppModel装配同一个AppClock给仓库、恢复后的仓库、SystemServices、编辑会话和SwiftUI日期环境；时区变化时更新displayTimeZone，保留民用日期/时分。正常启动仅装配服务，不请求通知授权或注册登录项。协议与失败测试位于TodoServices，测试不依赖UI进程或系统权限。

桌面卡片是 AppKit NSPanel，不是 WidgetKit；保持左七天未完成待办、右倒计时的等宽布局。卡片使用 App 内局部事件监视器，不请求辅助功能或屏幕录制权限。

独立 UI 验证使用 `./scripts/run-ui-preview.sh acceptance-20261031`，数据写入独立目录，不改变正常数据库。脚本拒绝在已有验收进程上重建或重复打开同一测试库。测试状态与实际支持矩阵见 `docs/IMPLEMENTATION.md`。

另有根目录Xcode工程与UITests共享scheme/计划，直接编译本模块而不复制界面。当前结构与语法检查通过，完整Xcode编译和8个UI用例未执行；见UITests/README.md。正常发布仍由CLI脚本打包，独立宿主不替代本机发行App。
