# Release GUI 基线

2026-11-01，V18 / build 8，macOS 26.6.2（25G83），Apple M4、Mac16,12、arm64、10 个处理器。使用独立验收 bundle 和四个新 SQLite 命名空间；正常用户数据未参与。

## 方法与边界

- 预先生成并关闭数据库，分别为1000待办/20规则/50倒计时与10000/100/200。规则尚未展开；首次启动后仅按目标月/七天展开，存储任务分别为1260与11300。
- 每次启动新进程，使用Release。`card`模拟后台登录路径，只显示卡片；`main`同时显示主窗口与卡片。已正常完成首次说明，未开启通知或注册真实登录项。
- 启动计时从Swift main的采样入口开始，到原生窗口可见、布局/显示检查及下一轮主事件队列完成。这是 **layout-ready检查点**，不包含LaunchServices及main之前加载的耗时，不是屏幕合成首帧或真实输入响应的替代证明。未清空OS文件缓存。
- 允许3秒稳定，再以`getrusage`的进程用户+系统CPU秒差/实际经过秒数×100测量至少5秒。样本期间没有本App的鼠标/键盘/滚动事件、窗口模式变化或数据操作；记录仅含计数，不记录按键或事项文本。
- RSS来自样本完成后活进程的一次`ps rss`读数，KiB×1024。它不是峰值、physical footprint或Instruments分配分析；CPU和RSS采集时刻分别保留在原始报告中。
- 四种情况各一次，不能据此推断分位数、长期内存稳定性、所有机器或最低系统。当前SDK仅CLT，`xcrun --find xctrace`不可用。

## 结果

| 初始数据 | 窗口 | layout-ready | 空闲CPU | RSS快照 | 原始报告 |
| --- | --- | --- | --- | --- | --- |
| 1000 /20 /50 | 单卡片 | 306.9 ms | 0.027% | 112.9 MiB | [normal-card](gui-benchmark-v18-normal-card.json) |
| 1000 /20 /50 | 主窗口+卡片 | 733.9 ms | 0.069% | 165.7 MiB | [normal-main](gui-benchmark-v18-normal-main.json) |
| 10000 /100 /200 | 单卡片 | 604.8 ms | 0.031% | 154.1 MiB | [stress-card](gui-benchmark-v18-stress-card.json) |
| 10000 /100 /200 | 主窗口+卡片 | 1442.8 ms | 0.071% | 215.4 MiB | [stress-main](gui-benchmark-v18-stress-main.json) |

本轮单卡片常用数据的RSS观察值低于PLAN约150MB目标；主窗口并存和压力情况分别报告。所有检查点均低于2秒，但未由此宣称完成屏幕首帧或300ms端到端交互验收。完整门槛继续见[FULL_AUDIT](FULL_AUDIT.md)。

## 复现

先退出“待办验收”，使用新的ASCII标识。脚本拒绝已存在目录和已有验收进程，不覆盖旧样本。

```sh
./scripts/run-gui-benchmark.sh fresh-normal-card normal card
```

不要在采样期间操作验收App。启动日志之后约8秒，`gui-probe.json`包含`idleSampleValid: true`时，另开终端收集：

```sh
python3 scripts/collect-gui-benchmark.py fresh-normal-card --output docs/my-gui-result.json
```

采集器要求Release、完整有效样本与仍存活的相同验收进程；同时读取样本数量和启动后的任务数。通过原生UI退出验收App后，另用新标识运行`stress card`、`normal main`、`stress main`。不要重建正在运行的bundle，也不要对正常命名空间注入样本。

`--ui-performance`只有同时存在`--ui-test=`时生效；正常启动没有该采样任务或报告写入。

## V19 真实完成命令与日历分组

同机Release build 9，新命名空间先空闲采样，再通过原生UI依次执行6次日历完成/取消完成及6次卡片完成。日历对同一事项交替操作，卡片完成不同事项；每次核对原生辅助树状态。常用/压力分别为1000/20/50和10000/100/200初始数据；使用真实整月日历与卡片同时打开。

`GUIInteractionProbe`从异步业务命令入口计时：`modelPublishedMS`记录完整refresh返回（包括通知队列核对），`layoutCheckpointMS`还包括下一主事件队列、可见窗口布局/显示检查。它们**不包含初始输入分发、屏幕合成，也不等待160ms淡出动画全部结束**，不是输入到屏幕的端到端时延。AX观察仅核对结果，不用作计时器。只记录命令类型、时间、窗口类别和不变量，不写标题或业务ID。

| 数据/版本 | 来源窗口 | 次数 | refresh返回最大 | 布局检查点中位数 | 布局检查点最大 |
| --- | --- | --- | --- | --- | --- |
| 常用/分组后 | 日历 | 6 | 70.67ms | 99.17ms | 116.77ms |
| 常用/分组后 | 卡片 | 6 | 75.86ms | 98.71ms | 131.45ms |
| 压力/分组前 | 日历 | 6 | 301.11ms | 593.10ms | 603.11ms |
| 压力/分组前 | 卡片 | 6 | 328.75ms | 591.55ms | 662.75ms |
| 压力/分组后 | 日历 | 6 | 309.12ms | 375.73ms | 379.43ms |
| 压力/分组后 | 卡片 | 6 | 331.62ms | 379.50ms | 414.52ms |

日历现在只筛选一次并按日期分组，月格/周列读取对应数组，保留原排序；此前每格会反复扫描整月。压力布局开销下降，但整月重查仍占约300ms，不能据此宣称压力交互已低于300ms或所有操作达到目标。

36个样本均验证目标完成状态、主窗口/卡片外框不变、倒计时模型锚点不变。锚点相等不等于像素级滚动位置验证。分组后的周/月搜索结果与完成记录保留另经原生核对。原始报告：[常用](gui-interactions-v19-normal.json)、[压力前](gui-interactions-v19-stress-before.json)、[压力后](gui-interactions-v19-stress.json)。每类仅6次，不能推断长期分位数。

启动复测：常用主窗口+卡片693.2ms、空闲0.076%、RSS165.9MiB；压力988.5ms、0.060%、218.1MiB。原始[常用启动](gui-benchmark-v19-normal-main.json)、[压力启动](gui-benchmark-v19-stress-main.json)。交互文件的RSS为输入后的另一次快照，不和启动RSS混用；仍非峰值。测量后同一常用库另做功能验收，公开性能文件保存的是此前受控样本。随后统一底部状态行，最终界面流程另验，不以此观测推断所有后续改动的性能。

采样完成后，在仍运行的同一进程中操作，再收集：

```sh
python3 scripts/collect-gui-benchmark.py new-id --interactions --output docs/my-interactions.json
```

采集器拒绝缺失/旧进程/不同build或状态校验失败的交互样本。正常用户库不启用探针。

## V20 系统服务与时钟封装后复测

同机Release build 10，两个新命名空间，初始1000待办/20规则/50倒计时。原生默认装配与实际系统时区，通知关闭；沿用上述layout-ready、CPU/RSS与交互检查点定义，没有清空OS缓存。

| 模式 | layout-ready | 空闲CPU | 启动后RSS快照 | 报告 |
| --- | --- | --- | --- | --- |
| 单卡片/模拟后台 | 321.5ms | 0.026% | 113.3MiB | [card](gui-benchmark-v20-normal-card.json) |
| 主窗口+卡片 | 665.1ms | 0.087% | 166.0MiB | [main](gui-benchmark-v20-normal-main.json) |

单卡片报告visibleMain=0；采样完成后原生树也为七天卡片。主窗口进程随后执行6次日历完成/取消、6次卡片完成，均核对原生状态。日历refresh最大62.92ms、布局中位91.82ms/最大106.49ms；卡片refresh最大61.17ms、布局中位108.39ms/最大112.19ms。目标状态、两窗口外框及倒计时模型锚点全部通过，原始[12次交互](gui-interactions-v20-normal.json)。输入后的RSS是另一次快照，不替代启动后空闲RSS。

未见常用场景明显退化；每类仍只有一次启动/6次交互，不能据此推断长期分位数或所有机器。没有复测压力全矩阵，不把V19压力结果当作V20实测。物理输入到合成画面、完整淡出、像素滚动位置与Instruments仍需独立验证。
