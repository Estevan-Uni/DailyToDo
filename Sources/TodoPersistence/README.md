# TodoPersistence

负责 Core Data SQLite、范围查询、唯一键与事务、修订冲突、快照导出恢复。

已实现程序化 Core Data 六实体模型，不依赖 `momc`：类型、系列、规则、实例、排除和倒计时各自独立，字段原生存储。UUID 关联由业务校验维护，不级联删除任务；发生键与类型规范名有数据库唯一约束。

- `StoreSchema.swift` 定义 V1 字段、唯一约束与日期/系列索引。
- `SQLiteStore.swift` 将 managed object 限定于 private context 队列，仅传递值快照。`@unchecked Sendable` 只用于该封装，所有数据库操作都进入 context 队列。
- `agendaInput(in:)` 合并实际安排日期与原发生日的命中，避免改期后的原日重新生成；数据库仅读取请求范围内的任务。
- `replace(with:)` 用于完整恢复，校验后更新、插入与删除，只有一次 context 保存；失败 rollback，不提前清空库。
- JSON 只作为 DTO 转换和导出格式，没有在数据库中使用整库 JSON 字段。

8 项真实 SQLite 测试已通过：新库种子与重启、无效恢复不动原库、只读存储保存失败回滚、改期例外按两种日期查询、增量修改保留其他行、旧修订拒绝覆盖、关联迁移不完整回滚、数据库唯一约束失败保留原实例。

`StoreChanges`/`RevisionExpectation` 是模块内的增量提交契约：事务验证更新后的配置和变更记录，只 upsert 指定 ID，提交前检查剩余引用，失败 rollback。删除类型不能留下未迁移引用。Repository 与编辑器通过这些契约保存；业务层已测试修订冲突，GUI 冲突流程另行验收。

初始化只读取类型、系列、规则和排除配置；不再全量读取任务备注。`snapshot()` 是明确的全量导出/恢复接口；普通界面必须使用范围读取。

Repository、完整类型迁移、规则前向变更与编辑器已接入。Release 临时库性能基线位于 docs/benchmark-before.json / benchmark-after.json；它不等同 GUI 性能。

## Repository 命令层

`TodoRepository` actor 串行处理保存、完成、软删除、规则前向修改/停止、撤销、类型替代与倒计时命令。每个命令在读修订号与事务提交之间不挂起，草稿冲突拒绝覆盖。完成/编辑/软删除和系列停止返回有限撤销快照；恢复、类型迁移和前向批量改写不伪装为普通撤销。

`agenda(interval, includeCompleted:)` 为 App 日历传 true，为卡片传 false。同一记录保留稳定 ID 与计划日期，UI 通过勾选/删除线表达完成，不另复制已完成任务。自然周/月查询最多处理目标区间；完成历史分页 API 保留为存储能力，当前产品不提供独立完成页面。

业务验证见 32 项 RepositoryTests；另有6项恢复测试；连同领域、交互与系统服务合计129项通过。

`rolloverUnfinishedSingles()` 只移动过去未完成且未删除的非系列事项，单事务、保留稳定 ID、增加修订号，重复调用幂等。跨日触发由 App 负责，周期实例不会被查询进来。


## 失败库恢复与批量读取

`StoreLocation`用受限文件名的原子manifest选择活动库，拒绝路径穿越、过大文件与未知版本。`StoreRecovery`先完整校验快照，创建唯一候选库，导入成功后发布manifest；失败只清理该候选，原失败库保留。旧manifest替换前另存备份。6项恢复测试覆盖原字节、重开、非法输入和损坏配置。

增量提交按实体和ID分块（512）读取修订与upsert对象，避免重复实例展开时逐行查询；没有省略任何预期修订检查，仍然一次保存/失败回滚。

活动manifest指向缺失文件或目录会失败并进入恢复路径；只有从未存在manifest的首次启动才允许按默认位置建立新库。

`quickEditTask`在actor内读取记录并检查修订，再复用完整保存逻辑，仅修改指定字段、默认仅本次。明天由注入时钟/时区计算，保留绝对提醒和其他字段；同值不增加修订。3项新增回归覆盖远期安排移到真正明天、例外/完成/字段保护、冲突、撤销与已删除拒绝。

`SeriesReview.swift`封装批量确认的已存数量/例外清单/修订快照，saveTask和stopSeries可接收已确认令牌并在提交前重验。upcomingSeries仅计算未来有限发生，合并规则版本、完成/排除/移动例外，不写数据库；管理入口编辑下一次时另走有界agenda实体化。

V19：countdown(id:)提供包含删除/归档状态的单条读取，编辑入口负责可编辑条件。saveCountdownWithUndo返回事件与可选撤销；新建不产生普通撤销，修改、归档、软删除可撤销，最近删除恢复除外。撤销快照包含修订期望，rebased(after:)仅在成功撤销后沿匹配的旧修订链更新本机旧动作；其他写入不放宽保护。已删除倒计时不能被旧归档/编辑命令修改，规则抑制事项不能被排队中的旧完成命令复活。

V20：StoreRecovery.create接收AppClock，恢复后Repository继续使用相同now/timeZone；新增跨年本地今天顺延回归，恢复测试现6项。TodoServices的ReminderSource只读协议由TodoRepository满足，通知失败不会获得数据库写入接口；其真实SQLite集成另验证时区变化时规则提醒重新解释而持久记录不变。

V27：待办draft.minute=nil归一化为明确未设时间，旧精确时分不变，不改变V1 SQLite结构。无时间每日/每周与实例例外、顺延、完成、JSON恢复均有真实SQLite回归；Repository累计36项。无时间相对重复提醒在提交前拒绝。
