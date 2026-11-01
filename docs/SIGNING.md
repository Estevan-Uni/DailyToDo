# 本机构建与分发边界

当前产物为Apple silicon、macOS14部署目标的本机预览，实际仅在macOS26.6.2验证；未完成Intel、最低系统或其他Mac的下载运行验收。发布版本与签名复核结果以ACCEPTANCE记录为准。

`scripts/build-app.sh`从Resources/Info.plist取得版本/构建号和默认Bundle ID，从DailyToDo.entitlements取得沙盒及用户选择文件读写权限。脚本支持：

| 配置 | 当前默认 | 用途 |
| --- | --- | --- |
| APP_OUTPUT | dist/TodoDesktop.app | 输出路径；安装副本使用本机Applications |
| APP_BUNDLE_ID | local.tododesktop.mac | 验收副本另用local.tododesktop.validation |
| APP_DISPLAY_NAME | 待办与倒计时 | 验收副本另名“待办验收” |
| CODE_SIGN_IDENTITY | `-` | 默认ad-hoc；可指定本机已有签名身份，当前未以外部证书验证 |

`package-app.sh`只交付临时目录签名源生成的ZIP，独立解压并严格校验，生成SHA256；可选安装前要求正常App已退出。Desktop/iCloud中的松散旧bundle可能附有Finder元数据，不用它替代ZIP签名源。

正式外部分发需要单独选择Developer ID或商店渠道、确定实际账号/团队与稳定Bundle ID，配置对应签名、运行时和提交验证，并记录公证/渠道结果及另一台Mac的下载启动。当前脚本不会因设置CODE_SIGN_IDENTITY而自动完成这些步骤，也不会自动上传或使用账号。此阶段不交付或保存任何证书私钥/凭据。

现有本机ZIP不宣称已公证、已通过Gatekeeper下载路径或已提交商店。人工验收可使用已明确标注的本机安装版；正式发行是后续独立配置与验证工作。

Xcode独立UI宿主固定local.tododesktop.xcuitest，测试bundle为local.tododesktop.xcuitests，使用相同沙盒entitlements和本机ad-hoc配置。工程/计划已生成并静态校验，但本机缺完整Xcode，未验证Xcode签名/Runner启动；不能将CLI包的签名结果转记为UI宿主通过。详见UITests/README.md。

V24：通用构建与可选安装共用app-output-guard.py，在编译前/替换前检查目标身份与实际进程可执行路径；无关App返回2，运行中返回3。Python 3为本机构建依赖。仅打包不要求另一安装路径的App退出；本机运行正常安装版时已实际打包成功，安装分支拒绝PID 87645。检查不等同原子安装锁；实际分发边界不变。
