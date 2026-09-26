# 架构说明

## 运行结构

```text
Codex lifecycle hook
        │ versioned JSON, no prompt body
        ▼
flyingsnowfluffctl ── Unix socket 0600 ──► PetEventServer
                                               │
                                               ▼
                                  PetStateCoordinator / UI
                                               │
                     ┌─────────────────────────┴─────────────────────────┐
                     ▼                                                   ▼
             SpriteView + MotionRig                              Flight planner
             AppKit / Core Animation                       safe-screen Bézier path
```

## 组件

### `FlyingSnowfluffCore`

不依赖 AppKit 的核心逻辑：

- 多显示器与安全区域几何；
- 贝塞尔飞行路径与随机区间；
- 设置 schema、迁移和持久化数据模型；
- Codex 事件解析、状态优先级和 TTL；
- 动作抑制、冷却、低电量帧率策略；
- 人物窗口与气泡的等比布局。

核心模块通过 SwiftPM 测试，不需要打开窗口。

### `FlyingSnowfluffApp`

AppKit 桌宠进程：

- `PetApplication.swift`：生命周期、窗口、菜单、输入、飞行和设置；
- `SpriteAtlas.swift`：Retina 图集、实际人物矩形和透明命中；
- `LivelyMotion.swift`：待机分层、目镜表情、动作片段和局部运动；
- `PetSpeechBubble.swift`：爱弥斯主题气泡；
- `PetDialogue.swift`：集中管理台词、场景和持续时间；
- `PetEventServer.swift`：只监听本机 Unix socket。

### `flyingsnowfluffctl`

Codex hook 的 fail-open helper。它把允许的事件名、会话/回合 ID 和时间封装为版本化 JSON，向 `/private/tmp/flying-snowfluff-$UID.sock` 发送。输入无效、桌宠关闭或 socket 不存在时静默退出 0。

### 资源层

- `Resources/App/`：App 2× 图集、1× 回退图集和独立帧；
- `Resources/v3/`：当前灵动姿势、分层待机部件、动作描述和母版；
- `Resources/CodexPet/`：Codex 自定义宠物 manifest 与专用 WebP 图集；
- `Resources/QA/`：App 图集验证结果；
- `Resources/v3/qa/`：只提交紧凑预览，不提交逐帧捕获。

App 图集与 Codex Pet 有不同显示目标，分别由 `asset_pipeline_contract.test.cjs` 和 `codex_skin_sync.test.cjs` 验证。

## 隐私与信任边界

- 默认离线、静音、无遥测、无麦克风和运行时网络访问；
- helper 不接收或保存提示词正文、工具参数、转录或输出；
- socket 权限必须为 `0600`；
- hooks 信任由每台机器上的用户在 Codex `/hooks` 页面确认，不能随仓库或安装包迁移；
- GitHub Release 的 SHA-256 只证明文件完整性，ad-hoc 签名不证明发布者身份。
