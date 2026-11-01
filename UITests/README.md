# Xcode UI 测试入口

此目录与根目录的DailyToDo.xcodeproj提供独立UI验收入口；正式本机预览继续使用scripts/build-app.sh和package-app.sh。当前机器只有CLT，**尚未用Xcode编译或执行这些XCUITest**，也没有产生xcresult。工程结构检查和Swift语法解析不能替代它们。

| 文件 | 职责 |
| --- | --- |
| DailyToDoUITests.swift | 9个原生UI用例、条件等待、每用例独立数据库与截图附件 |
| DailyToDo.xctestplan | 串行测试计划，关联独立App与UI测试target |
| Host-Info.plist | 独立App元数据，用构建变量取得Bundle ID/版本 |
| ../DailyToDo.xcodeproj | 同一正式App源码、四个本地Swift Package库、共享DailyToDo-UI scheme |
| ../scripts/generate-xcode-project.py | 标准库生成工程，校验成员清单、引用及plist/XML/JSON结构；无需第三方生成器 |
| ../scripts/run-ui-tests.sh | 完整Xcode预检、运行中副本保护、串行执行、独立结果/派生目录 |

测试宿主为DailyToDoValidation.app，Bundle ID为local.tododesktop.xcuitest；测试bundle为local.tododesktop.xcuitests，Runner由Xcode生成。两者均不同于正常App和现有CLI验收App。宿主直接编译Sources/DailyToDo的实际界面代码，链接TodoDomain/Persistence/Interaction/Services本地库，采用相同沙盒entitlements。没有复制业务实现。它不生成发行图标，外观及发行验收仍以CLI签名的正式预览为准。

每个用例通过XCUIApplication.launchArguments传入新的`--ui-test=xcui-UUID`；不向普通数据库写样本，不清空任何旧库。除最小卡片压力用例明确使用--ui-demo/--ui-stress，其余均为空库。语言、时区和桌面固定模式只对测试进程设置，不改系统设置；不请求通知授权、不注册登录项。关闭/显示卡片仅影响验收App自身偏好。首次说明通过真实“开始使用”按钮处理。

数据位于测试宿主沙盒的Library/Application Support/DailyToDo-UITests/xcui-UUID。失败时保留以便排查；脚本不会删除用户数据或旧结果。手动运行scheme使用xcode-manual命名空间，也与正常App分离。

## 运行

需要完整Xcode16+、Swift6与可登录的Mac图形会话。若当前xcode-select仍为CLT，可以只为此命令指定已有Xcode的开发目录，无需改全局配置：

```sh
python3 scripts/generate-xcode-project.py --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/run-ui-tests.sh
```

也可以在Xcode打开DailyToDo.xcodeproj，选择DailyToDo-UI scheme、DailyToDo测试计划，再执行Product → Test。首次运行若系统或Xcode要求本机配置/测试授权，由操作者按实际提示处理；脚本不接受协议、不更改系统权限、不安装Xcode。

默认结果位于build/ui-tests/时间-PID/DailyToDo.xcresult及run.log，派生数据位于build/XcodeDerivedData。可使用UI_TEST_RESULTS_DIR、UI_TEST_DERIVED_DATA指定其他目录；已有结果/日志拒绝覆盖。运行中的独立宿主或Runner会阻止重建。默认签名为本机ad-hoc，不进行远程签名、公证或提交。

## 覆盖与限制

1. 周/月展示切换、日期空白新增、右侧编辑栏与日期带入。
2. 必填错误保留表单，保存并继续保留日期/时间/类型并清空标题。
3. 卡片完成隐藏、App日历保留完成、撤销恢复。五秒提示已收起时使用公开业务撤销快捷键。
4. App新增倒计时、卡片修改、App立即显示新事件和日期。
5. 关闭主窗口选择不保存，卡片找回主窗口后不出现已放弃草稿。
6. 每日规则预览、本次完成不完成明天实例，返回今天仍隐藏。
7. 600×340最小卡片分别以进程内浅/深外观启动，在100项当天任务/200倒计时下保留双栏、滚动区域及固定添加入口；保留两份截图附件。
8. 类型浮层获得列表焦点，方向键浏览、回车/空格确认；Escape保持原选择和草稿，普通回车只确认类型，明确⌘Return才保存事项。该用例尚未运行。

等待基于控件存在/值/可用状态，保存后等待“保存并继续”按钮消失和编辑器恢复可用，不用固定sleep掩盖事务时序。关键控件使用稳定accessibilityIdentifier；macOS原生侧栏会合并行内容而不导出内部Label ID，因此该处使用主窗口内的明确中文行标签。V23类型列表也由原生行表示，按category-options容器内中文行及选中状态定位；选择通过方向键/回车，不依赖被合并的内部按钮ID。卡片操作前通过现有显示入口将普通面板带到前方。

这些用例不等于全部发布矩阵：真实中文输入法候选、VoiceOver语音、物理滚轮/触控板惯性、OS辅助显示设置、通知实际投递、登录重启、多显示器/Spaces和最低系统仍按docs/ACCEPTANCE.md人工验证。当前9个用例未执行，不能加到142项已通过的Swift Testing总数里。CUA已在CLI构建的同源界面核对关键定位与流程，仍不等于XCTest Runner验证。

## 维护

添加/删除/移动Swift源码或更新Resources/Info.plist版本后执行：

```sh
python3 scripts/generate-xcode-project.py
python3 scripts/generate-xcode-project.py --check
```

生成器只管理pbxproj、共享scheme、测试计划和宿主Info；测试Swift源与此README不被覆盖。--check拒绝过期清单，防止SwiftPM已包含新文件而Xcode遗漏它。完整Xcode可用后应先执行xcodebuild -list与实际build-for-testing/test，保留原始xcresult；若发现工程或用例不兼容，应修正后重跑，不把静态校验当作通过。

系统依据：[Apple启动参数](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launcharguments)、[Apple测试计划](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback)、[Apple运行测试与结果](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results)。

V26：桌面卡片在普通窗口后方，卡片helper关闭干净主窗口后再操作，需要核对日历时从卡片打开；新增隐藏App后仍可编辑并找回主窗口。9项用例仍未运行。
