# 原生界面截图

2026-10-31，macOS26.6.2、Apple silicon，独立local.tododesktop.validation与business-review-20261031合成库。由原生App截图直接保存，未绘制替代界面。

- [周日历](week-calendar.png)：七列周历、完成原位划线、周三单次改到周四，侧栏仅两入口。
- [倒计时](countdowns.png)：同一主窗口的简约事件卡片与日期天数。
- [桌面卡片](desktop-card.png)：左七天未完成待办、右倒计时、1000天、固定外框与局部滚动。

这些截图不能替代深色/减少透明度/长文本/大字号/多屏/真实手势的完整矩阵，已执行的其他UI流程见IMPLEMENTATION.md。

- [六行月历](month-calendar.png)：2026-11-01，async-recovery-20261101隔离合成库；修复后每格显示事项及剩余数量，恢复数据已完成启动补移。

V13使用color-forward-20261101隔离合成库：
- [深色前向编辑](forward-editor-dark.png)：原生右侧栏、范围菜单、每周多选与完成历史。
- [浅色纯白主题卡片](white-theme-card-light.png)：原始主题#FFFFFF、白色学习类型，显示色与描边保护可读性。
- [深色纯黑主题卡片](black-theme-card-dark.png)：原始主题#000000、1000天、白色学习类型，背景保护后的真实窗口。

V14合成验收：
- [卡片固定导航](card-navigation-v14.png)、[非今天页](card-non-today-v14.png)：quick-actions-20261101，左下新增、回今天、右侧计数。
- [今天及过去倒计时](countdown-today-past-v14.png)：当天/昨天/远期同时保留。
- [全部完成和零倒计时](card-complete-empty-v14.png)：6条完成记录仍在数据库，3事件均归档而非删除。
- [真正空库](card-empty-unplanned-v14.png)：empty-state-20261101，无样本注入，文案与全部完成不同。
- [两列压力末项](card-stress-bottom-v14.png)：stress-v14-20261101、原生无障碍滚动，100任务/200事件、9999天、固定新增入口。

V15使用recurrence-review-20261101合成库：
- [停止影响清单](series-impact-v15.png)：12条未完成、1条已完成保留、1条改期例外的原日和实际日。
- [复制新规则预览](series-copy-preview-v15.png)：明确新开始日期及独立新系列，预览位于可滚动编辑栏下部；完整三次文本另经原生辅助树核对。

V16合成验收：
- [类型选择](category-choice-v16.png)、[卡片内类型返回](card-category-v16.png)：category-picker-20261101，色点/名称/底部操作与保留草稿。
- [显式提醒联动](reminder-shift-v16.png)：reminder-shift-20261101，新时刻先预览，未开启通知权限。
- [最大天数排版](card-large-days-v16.png)、[到时状态卡片](card-time-status-v16.png)、[周历时间提示](week-time-status-v16.png)：status-layout-20261101，2,912,138天完整显示，14:10前后原生辅助树另核对自动更新；截图中的卡片已滚动，顶条标题部分离开可视区。

V17使用local-time-review-20261101、仅验收进程TZ=America/Los_Angeles（系统与正常App仍Asia/Shanghai）：
- [缺失时分确认](local-time-gap-v17.png)、[重复时分确认](local-time-fold-v17.png)：显示解析结果、时区/偏移、继续编辑及明确保存。
- [键盘切页后的卡片](card-paging-v17.png)：Home/左右键和边界辅助树已验证；静态截图不证明动画或VoiceOver语音。

V18合成验收：

- [冲突草稿另存](conflict-copy-v18.png)：entrypoints-review-20261101，另存前后辅助树/SQLite核对两条独立记录。
- [压力样本月历](gui-stress-month-v18.png)：gui-stress-main-v18-20261101，初始10000/100/200，月历6291项安排；截图在性能采样完成后保存。

V19合成验收：

- [不可编辑原记录草稿](unavailable-draft-v19.png)：原规则实例被抑制，卡片旧草稿仍可另存；截图为修复验收阶段，最终红色文案已改为“原记录已删除或不再可编辑”。
- [连续录入](continuous-entry-v19.png)：固定规则保存后下一条保留日期/时分/生活类型，标题清空，重复和提醒关闭。
- [倒计时保存反馈](countdown-save-feedback-v19.png)：倒计时页面底部固定显示保存成功与通知尚未开启，并提供业务撤销。
- [紧凑编辑栏](compact-editor-v19.png)与[必填定位](compact-editor-validation-v19.png)：本App系统窗口尺寸菜单缩小后，右栏独立滚动，底部保存从滚动末尾定位标题，错误与按钮可见。

V20合成验收：

- [系统服务默认状态](services-defaults-v20.png)：通知关闭、队列未开启；完整原生辅助树另核对登录off。没有操作系统授权。
- [共享时钟的缺失时分确认](clock-zone-confirm-v20.png)：仅验收进程洛杉矶时区，02:30→03:00 UTC−07，存储仍保留原分钟150。
- [共享时钟的目标日提醒](clock-zone-reminder-v20.png)：实际界面03/14 09:00；SQLite核对16:00Z。日期辅助树被工具按宿主时区表示，验收以截图和存储联合判断。

V21合成验收（以下文件均为原生JPEG）：

- [最小卡片](minimum-card-v21.jpg)、[两列末项](minimum-card-bottom-v21.jpg)：minimum-card-v21-20261101，600×340逻辑点，截图1200×680；当天100项/98未完成、200倒计时。两列分别通过原生可访问性滚动到底。
- [最小深色卡片](minimum-card-dark-v21.jpg)、[深色两列末项](minimum-card-dark-bottom-v21.jpg)：minimum-dark-card-v21-20261101，同尺寸和压力规模，长标题与9999天仍可读，固定新增可达。
- [最终Release浅色最小卡片](minimum-card-light-release-v21.jpg)、[同进程浅色主日历](main-light-release-v21.jpg)：显式隔离外观Aqua；日志cardSize=600x340、contained=true，不改OS外观。主日历图片是主窗口，不能当作最小卡片尺寸证据。
- [普通启动忽略验收尺寸](minimum-flag-ignored-v21.jpg)：独立预览bundle不带--ui-test、仅带--ui-minimum-card，0项且680×400，截图1360×800；不使用正常用户库。

这些静态截图不验证物理惯性、真实减少透明度/动态效果、大字号、VoiceOver或XCTest Runner。完整Xcode UI入口已有7项用例，当前未执行。

V22隔离通知目标重放（原生JPEG，非系统通知投递）：

- [已完成待办](reminder-completed-replay-v22.jpg)：notification-open-v22-20261101，启动前入队，打开原日期及完成时间，日历仍划线、右侧详情存在。
- [倒计时](reminder-countdown-replay-v22.jpg)：同一隔离库，进入倒计时页与对应右侧栏，事件/日期与记录一致。
- [最终Release失效目标](reminder-missing-replay-v22.jpg)：合法格式但不存在的UUID只显示失效说明，没有新编辑器或记录。普通启动忽略重放参数另由原生辅助树核对0项/无失效提示。

未开启系统通知权限，未验证实际横幅/声音、通知中心点击或系统冷启动唤起；具体边界见../NOTIFICATIONS.md。

V23类型键盘验收（原生JPEG）：

- [主窗口类型列表](category-keyboard-v23.jpg)、[卡片编辑类型列表](card-category-keyboard-v23.jpg)：keyboard-flow-v23-20261101独立库。同一Release另通过辅助树核对方向键/回车/空格/Escape和明确保存；SQLite验证原字段与修订。
- 截图按所属窗口裁剪，超出其窗口的浮层部分会被截图边缘截去；这不是完整屏幕截图，不能据此推断真实越界或屏幕适配通过。原生行的实际指针点击、全控件Tab与VoiceOver/IME仍待验，键盘成功不代替这些项目。

V24：[独立验收提醒排队](notification-queued-v24.jpg)，1040×1364原生JPEG。设置明确显示允许事项提醒on、排队1条、登录off；随后辅助树记录到期归0。截图只证明App队列状态，不是系统横幅或点击证据；权限变化只作用于已授权独立uipreview。

V27：[日历仅显示事件](calendar-title-only-v27.jpg)，独立optional-time-v27-20261101，2240×1440 JPEG。该记录详情保存18:00，日历格只显示名称；空时间保存/重开与清空后的卡片另由原生辅助树核对。


V28：[浅色卡片外观控制](card-material-controls-light-v28.jpg)、[深色卡片外观控制](card-material-controls-dark-v28.jpg)，1360×800原生JPEG，仅含card-material-v28-20261101合成库。两图均为默认18%/染色开启；0%/100%、60%双入口同步与重启保留另由原生辅助树验证。单窗裁剪不包含完整桌面合成，右侧浮层可能被窗口边缘截去；不证明实际壁纸取色、物理拖动或真实辅助设置矩阵。用户提供的参考截图没有复制或上传。
