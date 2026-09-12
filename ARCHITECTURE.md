# 代码结构与资源所有权

| 文件 | 唯一职责 |
| --- | --- |
| HingeGlassApp.swift | 应用入口、设置窗口、Dock 显示策略；窗口关闭与程序退出分开处理 |
| AppModel.swift | 可观察设置、校准持久化、界面动作接口 |
| RootView.swift | 设置页与截图预览页 |
| GlobalDesktopController.swift | 停止、启动、运行、暂停之间的协调；捕获与传感器的启停决策 |
| DesktopControls.swift | 菜单栏和 Carbon 快捷键；统一注册和释放 |
| DesktopLifecycle.swift | 系统休眠、锁屏、显示器与空间通知；按所属通知中心注销 |
| CaptureSession.swift | ScreenCaptureKit 会话、帧校验、配置更新和帧率重试 |
| DesktopOverlay.swift | 不抢焦点的覆盖窗口、显示与隐藏 |
| GlassRenderer.swift | GPU 纹理、Metal 管线、动画收敛与着色器 |
| LidAngleSensor.swift | HID 读取、自适应轮询、变化通知 |
| LiveEffectPolicy.swift | 可脱离硬件验证的角度、帧率、重试和后台监测策略 |
| ScreenCaptureSettings.swift | 仅打开系统录屏权限设置，不重置权限记录 |

## 数据与生命周期

传感器变化和捕获新帧触发控制器更新。没有独立的逐帧控制定时器；MetalKit 只在画面或角度需要更新时绘制。

控制器保留一个最新 CVPixelBuffer，覆盖层不可见时不提交 GPU 上传。重新显示时才上传最新帧。GPU 提交期间保留源 buffer 和 CVMetalTexture，完成后释放；捕获停止时清空缓存。

显示器枚举在启动、配置变更与低频健康检查时执行，避免每个动画帧查找显示器。捕获帧率更新串行执行；只有成功完成的请求才写入已生效帧率，期间到达的新请求会随后应用。旧会话的异步回调通过代次和对象身份检查丢弃。

休眠或锁屏时释放捕获资源、停止传感器，依靠系统通知恢复。后台模式的窗口收起、最小化或 Dock 隐藏不会修改效果启用状态。用户选择退出时统一清理通知、快捷键和会话。

## 验证边界

策略测试覆盖校准、终点边界、帧率更新失败与并发请求、自适应轮询、关闭设置后的监测需求、休眠暂停。真实窗口关闭和进程存续需要在 macOS 上验证；录屏、GPU 画面与物理合盖不能由纯策略测试替代。
