# 构建与验证

- `./scripts/test.sh`：运行标准 Swift Testing 测试。在 Apple Command Line Tools 环境自动补齐 Testing 框架路径，并关闭缺失模块的 Foundation cross-import overlay；不修改系统安装。
- `./scripts/build-app.sh [release|debug]`：编译原生二进制、生成矢量绘制图标、组装 `.app` 并进行签名校验。默认仅做本机 ad-hoc 签名，不代表完成对外公证。
- `make-icon.swift`：用 AppKit 路径绘制图标，不依赖网络、图像服务或付费 API。

当前打包产物用于阶段内启动验证。可提供明确标注的本机预览用于人工确认；正式对外发布必须满足 IMPLEMENTATION 与 PLAN 的完整发布门槛。

可用 `APP_OUTPUT="$HOME/Applications/DailyToDo-Preview.app" APP_BUNDLE_ID=local.tododesktop.preview APP_DISPLAY_NAME=待办预览 ./scripts/build-app.sh debug` 生成独立预览 bundle；启动参数 `--ui-test=唯一标识 --ui-demo` 只在空的测试库填入合成样例。正常启动不生成示例。

签名在系统临时目录的独立 staging bundle 内执行，再无扩展属性复制到输出位置并二次校验，避免 Desktop/iCloud 在签名期间重新附加 FinderInfo 的竞争。只清理脚本自己创建的临时目录。

`./scripts/package-app.sh [--install-local]` 从临时目录签名源生成 `dist/DailyToDo-macOS-arm64-preview.zip`，解压后复验签名；可选安装到本机 `~/Applications`。桌面同步目录可能重新附加 bundle 元数据，预览分发使用 ZIP，不以桌面目录内 bundle 的后续元数据状态作为签名源。

`--ui-stress`与`--ui-demo`配合在空测试库生成100项当天任务/200倒计时；`--ui-dark`在明确`--ui-test`时仅修改该App外观。测试说明见docs/ACCEPTANCE.md。


`./scripts/run-ui-preview.sh acceptance-20261031 [--ui-stress] [--ui-dark]` 是推荐的隔离验收入口：检查ASCII测试标识，拒绝重复验收进程，构建独立bundle后以明确测试库启动。不要在正在运行的可执行文件上重建。退出后先确认进程确已结束；某些GUI自动化观察可能重新启动无参数App，不能把观察到的另一个库当成原验收会话。

`--ui-login`模拟后台登录启动，仅与明确--ui-test命名空间共同生效；脚本默认仍不改变SMAppService或系统登录项。当前系统启动诊断只输出背景标志/可见主窗口数/卡片状态；在GUI工具可能触发重开之前采集。该模拟不能替代实际登录重启或最低系统验收。

时区合成验收可在启动命令前设置仅进程TZ，例如TZ=America/Los_Angeles ./scripts/run-ui-preview.sh local-time-review-20261101；仅影响该进程及其构建子进程，不写系统时区，正常App保持系统环境。不要对正常命名空间注入示例。

Release GUI基线：run-gui-benchmark.sh new-id normal|stress card|main。准备独立样本、拒绝已有进程并启动Release；保持空闲至报告有效后，用collect-gui-benchmark.py new-id --output path.json采集。采集器验证Release/完整样本/活进程，读取RSS和已存数量，不操作界面。四组当前报告和测量边界见docs/GUI_PERFORMANCE.md。

package-app.sh --install-local在构建开始与替换前均拒绝仍运行的DailyToDo.app，返回3且不改安装副本。ZIP先在临时目录验证后发布并更新SHA256；若App在构建时重开，保留有效ZIP但取消安装。旧安装包不会在验证前被未验证ZIP替换。

采样完成后可操作真实UI，再用collect-gui-benchmark.py new-id --interactions --output path.json收集最多100次完成命令检查点。采集器核对相同活进程/build及状态校验结果，不含初始输入分发/合成器延迟。先保存启动样本再操作，避免把输入后的RSS当成空闲快照。

`generate-xcode-project.py [--check]`管理独立UI验收工程及共享scheme/测试计划/宿主Info；App使用同一Sources/DailyToDo和四个本地库。--check通过原生plutil解析、引用清单及Swift Package产品检查；添加源码后过期清单会以状态2拒绝，不能把它当成Xcode构建成功。

`run-ui-tests.sh`需要完整Xcode16+和Mac图形会话，缺失工具返回3并明确未执行；已有结果/日志不覆盖，运行中的独立宿主/Runner不重建。DEVELOPER_DIR可只作用于当前命令；默认输出独立xcresult和run.log。当前CLT预检拒绝路径已实际验证，实际Xcode build/test尚未执行。详细步骤及8个用例见UITests/README.md。

`run-ui-preview.sh test-id --ui-minimum-card`只在隔离命名空间将卡片初始设为600×340，不把该初始框写入位置偏好；实际物理缩放仍单列。配合--ui-stress可检查100项当天任务/200倒计时。--ui-dark/--ui-light只覆盖验收App外观，不改系统；两者同时传入时深色优先。普通启动没有--ui-test时忽略这些验收外观/尺寸参数。

--ui-open-reminder=task-UUID或countdown-UUID可重放隔离库的冷启动通知目标，配合--ui-login可检查后台来源；这不发送OS通知，不请求权限。非法目标参数在构建前以2拒绝，已实际检查。App无--ui-test时忽略该重放参数。真实系统投递仍须另验，见docs/NOTIFICATIONS.md。

## V24 构建输出保护

构建需要Python 3；app-output-guard.py仅用标准库与macOS公开libproc。build-app.sh在编译前和复制前校验目标Info.plist的Bundle ID及DailyToDo可执行名，并按解析符号链接后的实际可执行路径检查活进程。相对argv[0]、空格/中文与正则字符不会绕过检查；同名前缀的另一bundle不会误拒。package-app.sh --install-local共用相同检查。

非法参数/非App或无关目标返回2；运行中或无法完成进程检查返回3，不写目标、不终止进程。进程路径可能因权限或消失而不可读取；这是当前可见进程的双次检查，不是LaunchServices锁，不承诺最后检查到复制之间完全无竞争。macOS14 API可用性由SDK声明确认，最低系统实跑仍待验。

`python3 -m unittest discover -s scripts/tests -v`运行5项独立脚本回归，见[测试说明](tests/README.md)。当前全部通过；另实测正常App运行时仅打包ZIP成功、--install-local返回3且不覆盖安装版。

V25：产品/可执行名为DailyToDo，默认输出dist/DailyToDo.app，安装到~/Applications/DailyToDo.app。为兼容旧库保留Bundle ID和数据路径。安装还检查旧TodoDesktop.app；旧副本不会自动删除。构建保护6项回归通过。
