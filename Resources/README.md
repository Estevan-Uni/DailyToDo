# App 资源

`Info.plist` 定义显示名称、稳定本地 Bundle ID 与 macOS 14 最低版本。

`DailyToDo.entitlements` 仅开启 App Sandbox 和用户选择文件的读写能力。未申请网络、日历、联系人、辅助功能或屏幕录制权限。

图标由构建脚本从 AppKit 路径生成。默认 ad-hoc 签名适合本机验证，其他 Mac 的下载分发与 Gatekeeper 行为需单独验证与说明。

签名配置与当前渠道边界见docs/SIGNING.md；仅设置CODE_SIGN_IDENTITY不会自动公证或上传。

Xcode UI宿主另用生成的UITests/Host-Info.plist，通过构建变量取得独立Bundle ID/版本；仍引用本目录沙盒entitlements。它不包含发行图标生成步骤，正常App的Info与图标路径保持由CLI打包负责。
