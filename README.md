# MacBook Duo

让桌面随 MacBook 屏幕开合呈现透视与毛玻璃效果。当前 Fork 版本 **1.2.0（构建 13，测试版）**，基于 jlxc2001/MacBook-Duo。

## 后台运行

- 应用默认常驻菜单栏，图标是两个重叠的矩形。
- 关闭或最小化设置窗口，已启用的效果继续运行；从菜单栏选择「打开设置」可以随时回来。
- 「在 Dock 中显示图标」可随时切换；隐藏 Dock 图标不会停止效果。
- 「停止效果」只关闭效果，应用仍留在菜单栏；「退出 MacBook Duo」才结束程序。
- 本版本不自动配置开机登录项。退出后再次启动，需要重新启用效果。

## 使用

1. 打开设置，确认「完全清晰的角度」。默认 **100°**，已有校准值会保留；可点击「恢复 100°」或「使用当前屏幕角度」。
2. 点击「启用实时桌面效果」。首次使用或系统尚未认可新构建时，需要在 macOS 中允许屏幕录制。
3. 设置窗口会收起；在终点及以上恢复清晰，低于终点时显示过渡效果。
4. 从菜单栏打开设置时暂时隐藏覆盖效果，方便操作；关闭设置后继续按真实角度显示。
5. 可用「测试效果（8 秒）」预览固定角度；结束后回到真实角度控制。截图模式支持导入图片和手动模拟。

快捷键：**⌘⇧G** 开关效果，**⌘⇧Esc** 停止效果并打开设置，**⌘⇧K** 保存真实角度。截图调试页保留 ⌘H、Esc、⌘K 和 ⌘B。

## 节能实现

- 传感器静止时以 10 Hz 监测，运动时升至 30 Hz；只发布有变化的角度。
- 通过传感器和新帧事件更新画面，移除独立的 60 Hz 控制轮询。
- 完全清晰时，屏幕捕获上限降至 1 fps；隐藏覆盖层期间仅保留最新帧，不复制 GPU 纹理、不生成 mipmap。
- 动画由 MetalKit 驱动并在收敛后暂停；新帧或参数改变才恢复绘制。
- 锁屏与休眠时停止捕获和传感器定时器，等待系统通知恢复；瞬时错误采用有界延迟重试。
- 效果关闭且设置窗口收起后，停止传感器监测。

上述频率是代码策略，实际耗电与画面变化、硬件及系统状态有关。测试方法与测量结果见 [PERFORMANCE.md](PERFORMANCE.md)，职责划分见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 要求与限制

Apple Silicon、macOS 15.0 及以上。实时效果需要可读取的铰链传感器和 MacBook 内建屏幕；不保证所有机型兼容，没有传感器时可使用截图模式。

画面变形不会改变系统真实点击位置，精确操作应在画面恢复清晰后进行。捕获使用逻辑分辨率；本版本仍使用未公开的 HID report 1 通路。完整合盖、不同外接屏和全屏空间需要按机型验证。

捕获和渲染仅在本机进行，不录制文件、不上传画面。权限说明见 [PERMISSIONS.md](PERMISSIONS.md)。可使用本机已有的 Apple Development 证书签名；未配置签名身份时使用 ad-hoc。两者都不等同于 Developer ID 公证。

## 开发与验证

需要 Xcode 或包含 macOS SDK 的 Apple Command Line Tools。

```sh
zsh test.sh                        # 无需传感器或录屏权限的策略测试
zsh build.sh                       # 构建、测试、签名，不启动
./script/build_and_run.sh --verify  # 备份旧版、安装至应用程序、启动并确认进程
```

构建在本机临时目录中进行，产物路径记录在被 Git 忽略的 `.build/app-path.txt`。运行脚本固定安装到 `/Applications/MacBook Duo.app`，旧版 ZIP 备份位于 `.build/backups/`。不要同时运行不同路径下的同标识副本。

GitHub Actions 构建并打包开发产物，不执行公证。签名优先使用显式指定的 `SIGNING_IDENTITY`，其次读取被 Git 忽略的本地 `.codex/signing-identity`；均未设置时使用 ad-hoc 签名。固定的开发证书有助于让系统在更新后识别同一应用。

## 参考与归属

- [上游项目](https://github.com/jlxc2001/MacBook-Duo)
- [Atomicx7/Duo-animation](https://github.com/Atomicx7/Duo-animation)：投影模型参考，改为 MacBook 底部水平铰链。
- [elijah-semyonov/DuoLikeAnimation](https://github.com/elijah-semyonov/DuoLikeAnimation)：上述项目注明的 Swift 原型，间接参考。
- [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)：HID 铰链读取参考。

工程未通过包管理器引入这些仓库，但这不等于无参考或无版权义务。当前源码包未新增开源许可证，不应将公开可见等同于授予自由使用许可；公开再分发前需确认代码归属与参考许可证要求。

旧开发记录已移入 `docs/archive/`，仅作为历史参考，以当前源码与本 README 为准。
