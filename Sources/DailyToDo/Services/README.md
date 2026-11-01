# Services

本目录封装界面相关服务：RefreshScheduler、共享时钟环境、文件面板、窗口位置、确认与隔离GUI测量。通知/登录项的可替换命令层已移至Sources/TodoServices，避免和AppModel/窗口相互依赖，详见该模块README。

EditorLeaveConfirmation.swift只封装原生NSAlert与save/continueEditing/discard选择；AppModel决定保存是否成功及是否允许离开。测试可注入选择而不弹真实窗口，生产默认对话框文字和按钮保持原行为。

首次启动不请求通知权限；只有用户主动开启才请求。通知按未来时刻排序，全 App 最多排队 48 个请求，规则只展开有限窗口；完成、删除、归档后重核。通知失败不回滚已经保存的业务数据。登录项通过系统公开 API 注册，默认不主动启用。

界面刷新由数据命令、下一可见计划时刻/午夜一次性定时器、唤醒、激活、系统时钟与时区变动触发。日内时刻边界仅更新clockNow投影，午夜仍维护数据；不逐秒/逐分钟查询数据库。通知权限、实际投递、登录重启等依赖系统状态的项目需单独实机验证，不由单元测试推断通过。

`RefreshScheduler.swift`读取AppModel注入的AppClock，并使用可替换ServiceDeadline调度下一边界；`ClockEnvironment.swift`向日期控件注入相同时钟。AppTheme同步注入时区/Gregorian日历，NSDatePicker显式设置日历和时区，日期“今天”不再直接读取Date()。系统事件观察仍使用公开AppKit通知。

官方依据：[本地通知调度](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app)、[SMAppService 注册](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)。

`FileDialogs.swift`统一异步JSON保存/选择面板，父窗口可见时使用sheet。回调结束后先关闭面板再交还URL，避免异步命令内嵌同步文件面板循环。AppModel持有独占数据操作状态，覆盖文件选择、取消、校验、确认和提交；管理视图写入也加入计数。磁盘JSON读写放入后台任务，结束后恢复调度。依据：[NSSavePanel异步sheet](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:))。

`CardPosition.swift`读取公开NSScreen可用区与ColorSync显示器UUID，封装本机V1偏好和旧cardFrame迁移，不读取屏幕画面。PanelPlacement负责数学计算，DesktopCardController负责应用结果、空间不足提示和重定位编辑浮层。偏好不进入JSON业务备份。

`SeriesConfirmation.swift`以原生NSAlert显示已保存实例数量、完成保护说明和可滚动完整例外清单，避免SwiftUI动态表单嵌套约束。确认仅返回用户决定；AppModel提交同一SeriesReview快照，Persistence重验修订后才写入。

`LocalTimeConfirmation.swift`显示手动设置异常时分的日期/时区/实际解释，继续编辑不写入。计划日期时分仍保留，确认本身不创建提醒；规则自动展开不重复弹确认，由共享说明展示实际解析。

`GUIProbe.swift`仅在--ui-test=与--ui-performance同时存在时运行。记录真实窗口的layout-ready检查点、稳定后的自进程CPU差、输入事件计数和模式；不记录键值或事项文本。报告只写当前隔离数据目录；正常运行无采样。RSS由独立采集脚本读取活进程，详见docs/GUI_PERFORMANCE.md。

`GUIInteractionProbe.swift`使用相同双参数门控，围绕真实完成命令记录refresh返回和下一队列/原生布局检查点、两窗口外框和倒计时锚点不变量；文件最多100样本，不含业务标题/ID。正常启动不创建token或报告。检查点不含输入分发、合成器或完整动画结束。

SystemServices用QueueHealth区分关闭、就绪、权限未允许和排队失败；保存界面读取结构化状态，不解析提示字符串。并发reconcile等待当前循环及追加核对结束后返回，避免显示上一次的成功状态。实际OS授权/投递仍须实机验证。
