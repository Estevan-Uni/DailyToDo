# 本机提醒与通知响应

默认关闭；启动、通知代理安装、原生界面重放、加载已有表单均不请求权限。用户从设置明确开启，或在编辑表单主动选择单次/重复提醒时才调用系统授权；已经启用不重复请求。拒绝后字段与草稿仍保留，表单显示提醒状态和系统设置入口，保存数据不因拒绝失败。正常App与独立验收bundle有各自系统权限；只允许验收App不等于正常App已允许。

排队与失败策略见TodoServices/README和PLAN第10节：全App共48条预算、固定规则未来30天、保存成功后核对、部分失败可重试。关闭只移除待发送请求，不清空通知中心历史；本地通知由系统处理，退出App后已有请求仍可能投递。长期退出后不能自动补充队列。系统设置、专注模式等会影响提示，不承诺精确闹钟。

## 收到及点击

- AppLifecycle在applicationWillFinishLaunching安装并强持有NativeNotificationInteraction；系统的delegate为弱引用。无需等业务库打开后才安装。
- 识别task-UUID/countdown-UUID后，前台回调显式选择banner/list/sound；未知标识不展示。最终是否出现横幅、声音或列表仍由用户系统设置决定。
- 默认点击动作按稳定ID排队；关闭通知、未知动作、非法ID不导航。只传值类型目标到MainActor，不跨任务传系统通知对象。收到有效目标并交给队列后立即应答系统，不等待数据加载或用户处理草稿。
- 冷启动点击保留到数据初始化和主窗口动作就绪；多个点击串行打开。中途继续编辑会取消本次定位，保留输入，不自动完成任何事项。
- 路由先检查目标，再确认离开草稿，之后重新读取当前记录与修订。非周期事项已顺延时打开现日期；已完成事项仍显示历史；已归档倒计时在右栏查看并明确提示；删除/抑制/缺失目标只说明失效，不复活记录。
- 打开有效目标会清空搜索及相关类型/完成过滤，使日历目标可见。已有卡片草稿保持原入口；通知路由只处理主窗口编辑。处理本机数据或存储尚未就绪时明确说明，不发起写入。

## 验证边界

当前有2项领域ID回归、4项通知交互回归和7项真实AppModel/临时SQLite回归；不调用系统授权/投递。原生独立副本另完成冷启动已完成任务、倒计时定位、失效目标说明与普通启动忽略重放参数。它们证明队列与模型/界面路径，**不证明OS实际投递和通知中心点击**。

隔离预览支持--ui-open-reminder=task-UUID或countdown-UUID，可配合--ui-login核对启动前排队与后台来源；普通启动没有--ui-test时忽略。目标ID须来自该隔离库，未知目标应显示失效说明。脚本参数先校验完整UUID，且拒绝重建运行中的验收副本。

真实OS验收：操作者允许对应验收App通知后，为临时事项设置未来提醒，分别检查前台与后台提示、点击定位、退出后冷启动定位、关闭动作不导航、完成/删除后旧通知及系统拒绝/禁用后的状态。保留系统实际结果；不能用重放参数替代这些步骤。改系统权限前取得操作者确认。

官方依据：[通知代理与安装时机](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)、[前台显示回调](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:))、[处理通知动作](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions)。

## V24 独立通知验收实际结果

用户已明确允许local.tododesktop.uipreview进行系统通知测试。2026-11-01在原有keyboard-flow-v23-20261101隔离库新增一条“本机通知验收”，没有修改正常App的数据或权限。首次请求系统返回“Notifications are not allowed for this application”，开关保持off，草稿可继续编辑；系统设置中该验收App实际为关闭。随后仅将该App“允许通知”打开，App内开启成功。登录项始终off。

保存事项18:25、单次提醒界面18:20；只读SQLite确认稳定ID A6EC9BC9-E64B-49B7-89F2-D3683754F793，绝对提醒为2026-11-01T10:20:58Z（本地18:20:58）。设置显示排队1条，过期后变0条/待补充0条。排队证据见[screenshots/notification-queued-v24.jpg](screenshots/notification-queued-v24.jpg)。只安排这一次测试，没有未来排队记录；隔离事项保留用于复核，系统对该验收App的允许状态保留。

**没有取得实际横幅或系统通知点击证据。** 当前CUA绑定通知中心仅返回天气组件窗口，SystemUIServer入口超时，不能从排队1→0推断已显示、播放声音或点击定位成功。前后台、退出冷启动、关闭动作、过期/删除通知等真实OS场景继续保留未验证；既有重放与模型测试不能替代。正常App权限未开启。
