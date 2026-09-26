# 飞行雪绒·爱弥斯

一个原生 Swift/AppKit macOS 桌宠：会在桌面待机、卖萌、拖拽和曲线飞行，也可以通过本地生命周期 hooks 显示 Codex 的工作、等待确认、失败和完成状态。

![动作预览](Resources/v3/qa/contact-sheet.png)

## 下载后直接使用

1. 在仓库的 **Releases** 页面下载 `飞行雪绒·爱弥斯-分享包-macOS-arm64.zip` 和同名 `.sha256`。
2. 在两者所在目录运行：

   ```zsh
   shasum -a 256 -c 飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256
   ```

3. 解压后，可直接在 Finder 中右键 `FlyingSnowfluff.app` 并选择“打开”，也可以把它移到 `~/Applications`。

分享包面向 Apple Silicon、macOS 15+。它采用 ad-hoc 本机签名，没有 Apple Developer ID 公证；首次打开可能需要 Finder 右键“打开”。仅解压不会写入 Codex hooks、安装 Codex Pet、创建桌面别名或启用登录项。

> 这是私有仓库。只有已经获得仓库权限的 GitHub 用户才能看到源码和下载 Release。

## 功能

- 透明置顶窗口，在所有 Space 显示；透明区域不会挡住鼠标。
- 单击互动、双击飞行、拖拽定位、悬停目镜回应。
- 176 / 208 / 256 / 320 pt 四档等比尺寸，默认 208 pt。
- 60 Hz 飞行，低电量模式自动降为 30 Hz；支持减少动态效果和安静陪伴。
- 右键人物或菜单栏 ✨ 打开设置；隐藏后重新打开 App 即可恢复。
- Codex 本地状态联动，不传输提示词正文、工具参数、转录或输出内容。
- 默认离线、静音、无麦克风、无遥测、无 AI 对话和运行时网络依赖。

## 从源码构建

环境：Apple Silicon、macOS 15+、Xcode Command Line Tools、Swift 6.1。

```zsh
git clone git@github.com:aswqp/FlyingSnowfluff.git
cd FlyingSnowfluff
swift test
zsh scripts/build_release.sh
codesign --verify --deep --strict dist/FlyingSnowfluff.app
```

构建产物默认位于 `dist/`。App 使用提交到仓库的预生成高清资源，因此普通构建不需要 Node.js。重新生成图集才需要 Node.js 22+：

```zsh
npm install
npm run build:assets
```

完整构建、测试、安装与排错说明见 [docs/BUILD.md](docs/BUILD.md)，组件关系见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## Codex 联动

完整本机安装可以运行 `zsh scripts/install_local.sh`，它会先校验 App、分享包和签名，再事务式安装 App、Codex Pet、桌面入口并合并本地 hooks。运行前请阅读 [Packaging/安装与使用说明.md](Packaging/安装与使用说明.md)。

安装完成后仍须在自己的 Codex `/hooks` 页面逐项核对并信任只调用本机 `flyingsnowfluffctl` 的处理器；仓库和安装器都不会伪造或转移信任记录。

## 隐私边界

联动 helper 只向权限为 `0600` 的 `/private/tmp/flying-snowfluff-$UID.sock` 发送事件名称、会话/回合 ID 和时间。桌宠未运行、socket 不存在或输入无效时，会在 300 ms 内静默放行，不阻塞 Codex。

## 权利说明

本仓库为私人、非商业桌宠工程。角色名称与形象相关权利归其权利人所有；仓库不声明对第三方角色 IP 的所有权，也不包含游戏原声音频。代码、工程文件和二进制的使用边界见 [NOTICE.md](NOTICE.md)。

## 版本

当前版本：**1.4.4（build 9）**。变更记录见 [CHANGELOG.md](CHANGELOG.md)。
