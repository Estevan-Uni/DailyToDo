# 固定在桌面的卡片

2026-11-01 · V26 · 0.1.0 build 15。默认行为改为桌面固定，不再作为普通App窗口参与“显示桌面”收起。其他窗口可以覆盖卡片；需要始终压在其他窗口上方时，在设置开启“卡片保持在其他窗口上方”。App需后台运行，退出后卡片关闭。

## 实现

- 使用系统公开`CGWindowLevelForKey(.desktopIconWindow)+1`，不硬编码负层级。卡片位于普通窗口后方、桌面图标平面上方。
- 创建非激活NSPanel，设置hidesOnDeactivate=false、canHide=false、stationary/canJoinAllSpaces/ignoresCycle/fullScreenNone；不添加fullScreenAuxiliary或私有窗口服务。
- 编辑使用独立可激活normal窗口；置顶时编辑同步floating。编辑器不再作为桌面层父窗口的子窗口，避免继承低层级而无法输入。拖动父卡片重新锚定编辑器；隐藏卡片暂时隐藏编辑器，草稿留在会话。
- 显式打开主窗口、设置或编辑器前先unhide，再激活。默认卡片展示不激活整个App；App仍可通过卡片标题、菜单栏或Dock找回。

Apple公开说明：[stationary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)、[canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)、[desktopIconWindow](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow)、[canHide](https://developer.apple.com/documentation/appkit/nswindow/canhide)。本机SDK头文件及Apple文档JSON均核对stationary的桌面静止语义。

## 原生验收与限制

独立身份local.tododesktop.desktopreview、desktop-stationary-v26-20261101，测试数据与用户库隔离。初次后台启动记录visibleMain=0、card=true，680×400且在屏内。

- 向Finder发送显示桌面快捷键后，卡片辅助树与卡片单窗截图可获取；执行隐藏App操作后仍可通过卡片打开编辑、输入并保存“桌面固定验收”2099-03-18，倒计时由3项变4项。这里证明原生控件操作和保存链路，不是整个桌面合成画面的证明。
- 隐藏后打开主窗口曾不能正常找回，补充unhide后同入口实际打开DailyToDo主日历。通过Finder正常打开动作也可找回窗口。
- 工具对Finder桌面空白坐标点击返回noWindowsAvailable，低层级/隐藏窗口的抓图和键盘路由也有限制；因此不把本轮记录写成“实际桌面空白点按/所有系统隐藏组合均通过”。真实鼠标点击桌面、跨App遮挡、完整置顶切换、物理键盘与多屏/Spaces/全屏/台前调度仍需用户复验。
- 本轮没有开启通知或登录权限，没有修改系统显示桌面偏好，没有向正常库写验收事项。

142项Swift测试/17套件与6项脚本回归通过。UI用例适配桌面层操作入口，并增加隐藏后卡片可编辑/主窗口可找回，累计9项；仅做结构/语法检查，完整Xcode运行仍未执行。

## 用户复验

1. 打开DailyToDo，设置中关闭置顶、显示卡片，再关闭主日历。
2. 点击桌面空白、切换其他App、使用显示桌面：确认卡片保留，其他App窗口能覆盖它。
3. 在卡片勾选/切日/新增倒计时，输入和保存正常；标题箭头能找回日历。
4. 在主窗口用隐藏App，再从卡片找回主窗口/编辑器；关闭卡片后能从设置显示，草稿保留。
5. 开启/关闭置顶，分别检查遮挡行为；真正退出后卡片消失。

本轮替换PLAN早期普通窗口默认策略；完整设备门槛仍按ACCEPTANCE和REQUIREMENTS记录。

最终安装版build 15已原生启动，确认置顶off、设置说明为桌面固定；关闭主日历后仅保留desktop-card窗口，原有用户内容仍在。未记录或上传用户日程截图。独立桌面验收副本已正常退出。


## V28 半透明磨砂外观

2026-11-01 · 0.1.0 build 17。在原桌面固定行为之上，使用underWindowBackground系统材质与behindWindow混合，移除原80%/86%实色覆盖。默认背景遮罩18%，少量主题色染色；不会读取壁纸或申请屏幕录制权限。

卡片右上角“卡片外观”按钮与设置→桌面卡片提供同一组即时控制：

- 背景不透明度0%–100%（1%步长），0%仍保留系统磨砂，100%为实色背景；只影响背景，不改变文字、按钮或窗口整体alpha。
- 使用主题色染色：跟随已有主题颜色，可关闭；恢复默认磨砂将遮罩重置18%、染色开启，保持主题色不变。
- 偏好在本机保存并随重启恢复，非法非有限值回退默认，越界值钳位。
- 系统“减少透明度”开启时改用实色并解释原因，控制禁用但保留偏好；“增强对比度”开启时遮罩至少65%、描边加深。没有更改任何系统辅助设置。

实际效果由系统、外观与窗口后方内容共同决定；单窗截图不包含完整桌面合成，不能代替在用户壁纸上的人工确认。此前关于多屏/Spaces/全屏、最低系统/Intel和完整辅助设置的验收缺口继续保留。


V28原生验证：独立local.tododesktop.materialreview、card-material-v28-20261101合成库，正常库未写入测试数据。默认18%；设置中点击滑块到50%、原生增量到60%，卡片浮层同步60%。染色关闭后，背景不透明度升至100%；正常退出、以独立深色外观重开仍保留100%/染色关闭。浮层原生递减至0%且继续递减不越界，恢复默认返回18%/染色开启；浅/深色均有原生界面核对。滑块保留原生Increment/Decrement辅助动作，不覆盖原生可访问性值。

当前工具对低层级卡片的坐标点击返回noWindowsAvailable，验证采用原生控件辅助动作；不把这次操作写成物理拖动已验收。系统减少透明度/增强对比度没有实际切换，分支已实现但真实系统矩阵仍待复验。截图仅包含合成日程，按卡片窗口裁剪，外伸浮层可能被截；不能从图中确认实际壁纸取色或整屏边界。


最终安装build 17通过ZIP独立解压严格签名/SHA256核对；正常安装版启动后卡片外观入口存在，背景默认18%、染色开启。正常日程保留，未写入合成数据；独立外观验收App已正常退出。浅色重启另确认默认18%/染色开启保留，截图见[screenshots/README.md](screenshots/README.md)。
