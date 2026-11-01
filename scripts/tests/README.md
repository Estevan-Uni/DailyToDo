# 构建脚本测试

执行`python3 -m unittest discover -s scripts/tests -v`。需要macOS、Python3标准库和CLT clang；不安装测试依赖。

5项AppOutputGuardTests检查新路径/精确匹配、非法或无关Info、参数、进程信息不可用，以及真实相对argv[0]/符号链接/空格及正则字符路径的拒绝。原生集成测试只编译一个pause等待的临时C子进程，运行中通过实际build-app.sh检查拒绝、二进制哈希及子进程保持；结束后终止自己的子进程并清理自己的临时目录，不操作用户App或数据库。

这些测试单列为Python构建工具测试，不计入142项Swift Testing或8项未运行的XCUITest。进程视图是当前macOS可读信息；检查不是Launch Services锁，也不能替代真实安装/启动、最低系统和签名验收。

V25：累计6项；补充旧TodoDesktop可执行名升级检查，实际新产品名DailyToDo。旧名称运行中仍返回3，关闭后可继续。
