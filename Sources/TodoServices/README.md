# TodoServices

可替换通知、登录项、偏好和单次定时器适配器，以及主线程队列核对。业务提醒候选来自ReminderSource；TodoRepository直接满足该协议。UI不持有系统通知对象，也不通过解析中文状态文案判断成功与否。

| 文件 | 职责 |
| --- | --- |
| ServicePorts.swift | NotificationClient、LoginItemClient、ServicePreferences、ServiceDeadline与只读ReminderSource；PendingReminder为可发送值 |
| NativeServiceAdapters.swift | UserNotifications/SMAppService边界、UserDefaults偏好、可取消的一次性Timer |
| SystemServices.swift | 可观察状态、授权意图顺序、最多48条队列核对、失败反馈、暂停/恢复与后续补充 |
| NotificationInteraction.swift | 原生前台显示/默认点击回调、稳定目标解析、主线程冷启动/串行打开队列 |

SystemServices在MainActor串行协调异步调用；新核对令旧快照过期，加入者等待最新一轮完成。恢复数据库或关闭通知期间迟到的添加会被清理；下一轮使用最新数据源。授权等待期间关闭提醒时，迟到的允许结果不能重新开启偏好。

匹配请求保留，过期/删除/完成/归档或已不在计划内的请求移除。单条替换失败后移除相同ID的旧请求，避免旧标题/旧时间继续投递；记录失败并允许重试，不写业务数据。停用或权限不可用时清除待发送请求；不清除已投递通知。队列重填只安排一次下一时间点，不轮询。

AppClock同时提供当前时刻与动态本地时区；Gregorian日历由同一上下文派生。服务计时器与UI状态计时器均可替换，原生Timer取消也使已排入主队列的旧回调失效。通知候选的30天规则范围仍由TodoRepository约束。

18项SystemServicesTests覆盖：默认关闭、拒绝/未决定/授权错误、迟到授权不覆盖关闭、最新数据源、保留/替换/清除、部分失败/重试、只读数据源失败、48条补充、关闭/恢复时的在途添加、暂停与旧定时回调、加入者等待、缺失数据、登录批准/失败/实际状态、独立UserDefaults持久化，以及真实SQLite规则提醒随时区变化重算且原记录不改写。测试全部注入内存OS客户端，不弹系统权限、不注册登录项；真实OS授权/投递/登录重启仍须人工验收。

默认装配在AppModel中创建原生适配器。生产系统API依据：[Apple通知请求](https://developer.apple.com/documentation/usernotifications/unnotificationrequest)、[Apple待发送请求](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:))、[Apple登录项等待批准状态](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)。

V22：AppLifecycle在启动完成前安装并强持有NativeNotificationInteraction，设置delegate不请求权限。识别的本机提醒显式选择banner/list/sound，最终提示受OS设置影响；默认点击只传ReminderTarget到主线程，入队后应答系统，不等待数据库或用户对话框。关闭/未知动作不导航。NotificationOpenQueue等模型和窗口动作就绪后串行执行，未连接时保留冷启动目标；4项交互回归覆盖前台策略、动作过滤、冷启动和在途确认期间的次序。真实OS回调/投递/点击仍待验，完整边界见docs/NOTIFICATIONS.md。
