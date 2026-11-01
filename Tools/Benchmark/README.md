# 性能基线

执行 `swift run -c release TodoBenchmark --output docs/benchmark.json`。

使用独立临时 SQLite，固定业务时钟，分别创建 PLAN 中的常用（1000 任务 /20 规则 /50 倒计时）和压力（10000 /100 /200）样本，测量导入、重开、首次月份展开、七天、2099 年目标月份、单次保存及导出。

程序检查远期查询的持久化增长仍由目标月份/七天范围约束，退出清理自己生成的临时目录，不读取用户数据库。测量结果是领域/持久化 CLI 基线，不等同 GUI 冷启动或 GUI 内存，进程峰值也包含生成样本与导出 JSON 的开销。

本次原始结果保留在docs/benchmark-before.json、benchmark-after.json。压力首次月份由1721.51ms降至269.39ms、远期月由2010.44ms降至183.81ms。每份是单次运行，导入/保存存在波动，不宣称全操作提速；CLI峰值不用于证明GUI内存目标。

V17原始补测为docs/benchmark-v17.json；常用/压力首次月31.52/233.15ms、远期21.03/110.84ms、七天6.06/45.89ms。不同日期单次数据不作统计提速结论；压力峰值182.86MiB仍包含样本和导出，GUI矩阵未关闭。

新增--prepare-ui-fixture test-id [--stress]模式，复用同一生成器，以当前本地日期在validation命名空间准备1000/20/50或10000/100/200的真实SQLite并关闭；已存在目录拒绝覆盖。该模式不运行CLI计时，不对正常用户库写入；错误以状态2退出。GUI入口与采集方法见docs/GUI_PERFORMANCE.md。
