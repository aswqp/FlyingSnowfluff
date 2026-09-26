# 构建、测试与安装

## 环境

- Apple Silicon Mac；
- macOS 15.0 或更高；
- Xcode Command Line Tools；
- Swift 6.1（当前验证版本为 6.1.2）；
- 仅在重新生成素材或执行完整 hooks 安装时需要 Node.js 22+。

## 核心测试

```zsh
swift test
```

当前应执行 40 项核心测试，覆盖飞行边界、负坐标多显示器、设置迁移、事件隐私、状态优先级、TTL、动作策略、侧倾量化和布局。

## 素材测试

普通 Release 使用已提交的资源，不要求安装 Node。需要验证或重建素材时：

```zsh
npm install
npm run test:assets
npm run build:assets
```

`sharp` 固定为 0.35.4。App 图集和 Codex 专用皮肤采用两个独立验证契约，详见 `Resources/CodexPet/README.md`。

## AppKit 测试

这些测试会启动短暂的本机测试窗口：

```zsh
zsh scripts/test_app_harness.sh LivelyRenderingHarness
zsh scripts/test_app_harness.sh AppRenderingHarness fallback
zsh scripts/test_app_harness.sh AppBehaviorHarness
```

测试覆盖四档尺寸、Retina/1× 回退、8 种目镜表情、透明命中、右键菜单、点击、拖拽、悬停和 Codex 状态显示。

## Release 构建

```zsh
zsh scripts/build_release.sh
```

默认输出到 `dist/`；可以用 `OUTPUT_DIR=/absolute/path` 改写。旧产物会移动到同一输出目录的 `.backups/`。

构建后验证：

```zsh
codesign --verify --deep --strict dist/FlyingSnowfluff.app
unzip -t dist/FlyingSnowfluff-macOS-arm64.zip
unzip -t 'dist/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip'
(cd dist && shasum -a 256 -c '飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256')
```

所有 App 均为 ad-hoc 签名，没有 Apple Developer ID 公证。

## 两种安装方式

### 只运行桌宠

从 Release 下载中文分享 ZIP 与 `.sha256`，校验后解压。在 Finder 中右键 App 并选择“打开”。这一方式不写 hooks 或 Codex Pet。

### 完整本机安装

完整安装会修改当前用户的 `~/Applications`、`~/.codex` 和 Desktop，因此运行前必须阅读安装说明：

```zsh
zsh scripts/build_release.sh
zsh scripts/install_local.sh
```

安装器先校验候选 App、外层/内层哈希和签名，随后使用事务备份；硬失败会恢复原状态。安装后在 Codex `/hooks` 页面核对并信任实际列出的 `flyingsnowfluffctl` 处理器。

## 仓库发布检查

```zsh
zsh Tests/Integration/repository_contract.sh
zsh scripts/verify_repository.sh
```

检查包括：忽略规则、GitHub 100 MiB 限制、凭据样式、当前开发机绝对路径、临时截图路径和本机 socket 后缀。
