# DailyToDo 工程检查

2026-11-01 · V26 · 0.1.0 build 15。目标仓库：[Estevan-Uni/DailyToDo](https://github.com/Estevan-Uni/DailyToDo)，V25已首次提交源码，本轮更新桌面固定行为。此报告不等同正式外部分发验收。

## 名称与兼容

App/主窗口/菜单栏/桌面卡片、SwiftPM包与可执行文件、DailyToDo.xcodeproj、DailyToDo-UI scheme、DailyToDo测试计划、源码目录和构建输出统一命名DailyToDo。四个职责库保持原名，避免无关改动。

为读取已有数据保留local.tododesktop.mac、TodoDesktop Application Support目录、TodoDesktop.sqlite、TodoDesktopV1模型和既有偏好键；独立验收身份也保留。无需迁移或清空用户库。V25更名时正常库为0项；V26升级后用户已有内容仍在，未注入验收样本。本轮不公开用户日程字段，也不冒充数据库结构迁移实测。

旧TodoDesktop.app仍保留，本机当前入口为`~/Applications/DailyToDo.app`。同Bundle ID副本共享数据，勿同时运行；安装脚本在构建前和复制前检查新旧安装路径，发现运行中拒绝。检查是进程路径快照，不是系统原子锁。

## 实际检查结果

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| Swift Testing | 142项、17套件通过 | 临时SQLite/注入系统客户端 |
| Python构建保护 | 6项通过 | 新增旧可执行名升级识别；原生临时子进程覆盖路径别名 |
| 工程生成/一致性 | 30个App源码、1个UI测试文件、98个对象通过 | 不等同Xcode SDK编译 |
| 脚本 | Bash语法与Python模块编译检查通过 | 不执行系统授权 |
| Release | 构建、沙盒ad-hoc签名、ZIP独立解压严格签名、SHA256通过 | 本机Apple silicon；未公证 |
| 安装/启动 | 旧名称运行时安装返回3；退出后安装DailyToDo成功，原生窗口/菜单栏DailyToDo | 正常库没有注入样本 |
| UI测试 | 8项用例已提供，未运行 | 本机缺完整Xcode，CLT预检拒绝 |
| 提交内容 | 只含源码/测试/工程/脚本/合成验收文档与截图 | 排除.build、build、dist产物、数据库、pycache、个人工程状态与密钥文件 |

本地检查命令：

```sh
./scripts/test.sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/generate-xcode-project.py --check
bash -n scripts/*.sh
./scripts/package-app.sh
shasum -a 256 -c dist/DailyToDo-macOS-arm64-preview.zip.sha256
```

## 保留的验收门槛

完整Xcode构建与9项UI测试、实际通知横幅/点击、登录重启、真实午夜/休眠唤醒、IME/VoiceOver/全控件焦点、真实指针与滚轮/触控板、辅助显示/大字号/复杂壁纸、多屏/Spaces/全屏、macOS14与Intel、Instruments等仍按[验收清单](ACCEPTANCE.md)及[审查账本](REQUIREMENTS.md)处理。本轮完成桌面行为调整与已列工程检查，不宣告全部发布门槛通过。

仓库不附带用户原始参考截图、用户数据库、签名私钥或构建缓存；docs/screenshots是隔离样本/空库的原生验收截图，历史旧名称按当时证据保留。没有擅自选择开源许可证，仓库当前不附授权许可证。

V26默认固定卡片在桌面，其他窗口可以覆盖；可选置顶。App需后台运行，退出后卡片关闭。实现与原生验收边界见[DESKTOP_CARD.md](DESKTOP_CARD.md)。
