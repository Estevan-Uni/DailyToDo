# 工程说明

- `IMPLEMENTATION.md`：当前 PLAN 对照、实现证据、剩余验证与架构决策。
- `REQUIREMENTS.md`：P0逐条证据审查与仍需完成的工作。
- `screenshots/README.md`：本机原生界面截图与数据来源。
- `ACCEPTANCE.md`：安装、操作、自动顺延约定及人工验收矩阵。
- `benchmark-before.json` / `benchmark-after.json`：真实临时 SQLite 的优化前后原始基线，说明见 Tools/Benchmark/README.md。

不要用计划中的目标状态覆盖实际结果。自动化测试、原生 UI 验证和真实设备/系统权限验收分别记录。

- `FULL_AUDIT.md`：汇总门槛之外的PLAN全文细项、实际证据和未完成实现，不以代码存在代替验收。
- `PLAN_STAGE_AUDIT.md`：M0–M3逐项实现、证据与尚需验证，M4明确P1。
- `SIGNING.md`：当前本机签名配置、ZIP安装流程与外部分发边界。
- `NOTIFICATIONS.md`：授权意图、前台策略、冷启动/点击队列、当前状态定位及OS投递验收边界。
- `../UITests/README.md`：Xcode UI入口、8个未执行用例、隔离数据与实际运行步骤；区分静态检查、CUA核对和Runner结果。

- `benchmark-v17.json`：本地时分解析更新后的CLI单次原始补测，不能替代GUI性能矩阵。

- `GUI_PERFORMANCE.md`与`gui-benchmark-v18-*.json`：真实Release GUI检查点/CPU/RSS基线、机器、复现方法及未测范围。

- [HANDOFF.md](HANDOFF.md)：当前交付入口、十项人工验收与反馈格式。

- [ENGINEERING_CHECK.md](ENGINEERING_CHECK.md)：V25 DailyToDo命名、旧数据兼容与上传前检查。

- [DESKTOP_CARD.md](DESKTOP_CARD.md)：V26桌面固定策略、独立编辑窗口与实际验证边界。
