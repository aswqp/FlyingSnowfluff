# FlyingSnowfluff GitHub 私有仓库发布设计

## 目标

把当前飞行雪绒桌宠整理为 `aswqp/FlyingSnowfluff` 私有 GitHub 仓库，使获得仓库权限的人能够：

1. 阅读完整源码、架构与隐私边界；
2. 在 Apple Silicon、macOS 15+、Swift 6.1 环境复现测试与构建；
3. 从 GitHub Release 下载已经签名校验过的 v1.4.4 App、分享包和 Codex Pet；
4. 验证下载文件的 SHA-256，并明确 ad-hoc 签名不等于 Apple Developer ID 公证。

## 仓库边界

仓库根目录采用当前 `work/flying-snowfluff/`，提交以下内容：

- `Sources/`、`Tests/`、`scripts/`、`Package.swift`；
- 构建 App 所需的 `Resources/App/`、`Resources/CodexPet/`、`Resources/v2/`、`Resources/v3/` 标准素材和母版；
- `Packaging/`、项目 README、版本、变更记录、架构与构建说明；
- 体积可控的预览图和验证元数据。

不提交以下本机或可再生内容：

- `.build*`、`dist/`、外层 `outputs/`；
- `work/` 中的历史备份、安装恢复包和升级快照；
- `Resources/v3/qa/preview-frames/`、`Resources/v3/qa/runtime/` 等逐帧测试产物；
- `.superpowers/` 执行报告、临时缓存、Finder 元数据；
- `~/.codex/hooks.json`、信任记录、socket、UserDefaults、桌面别名和真实安装副本。

## 可复现构建

- 运行时继续保持纯 Swift/AppKit，不新增第三方运行依赖。
- `swift test` 验证核心逻辑；AppKit harness 验证渲染与交互。
- `scripts/build_release.sh` 默认把输出写入仓库内 `dist/`，不依赖仓库所在的绝对路径。
- Release 构建不再引用特定用户名的 VFS overlay；当前 Swift 6.1.2 直接编译作为验收路径。
- 已提交的预生成资源足以构建 App；只有重新生成高清图集时才需要 Node.js 22+ 和固定版本 `sharp`。
- `scripts/build_assets.sh` 优先使用环境变量 `NODE_BIN` / `NODE_MODULES`，否则使用 PATH 中的 Node 与仓库本地 `node_modules`。

## 下载与安装

Git 仓库只保存源码和必要素材。v1.4.4 GitHub Release 附加：

- `FlyingSnowfluff-macOS-arm64.zip`；
- `飞行雪绒·爱弥斯-分享包-macOS-arm64.zip` 及其 `.sha256`；
- `FlyingSnowfluff-CodexPet.zip`；
- 预览图、安装说明、经典台词来源和本次验收记录。

普通使用者下载分享包即可；只有需要从源码重建或安装 Codex hooks 的协作者才需要克隆仓库。私有仓库的 Release 也要求接收者拥有仓库访问权限。

## 隐私、许可与角色素材

- 仓库保持 private，不自动公开或添加协作者。
- 提交前扫描密钥格式、访问令牌、个人绝对路径和超过 GitHub 100 MiB 限制的单文件。
- README 明确：默认离线、静音、无遥测，不读取提示词正文。
- 代码与原创工程文件供仓库获授权成员个人、非商业使用；角色名称与形象权利归其权利人所有。本仓库不声明对第三方角色 IP 的所有权，也不提供游戏原声音频。
- 因没有用户授权开放源代码再分发，不添加宽泛的 MIT/Apache 许可。

## Git 与发布结构

- 默认分支：`main`。
- 远程：`git@github.com:aswqp/FlyingSnowfluff.git`。
- 初始提交使用 Conventional Commits，并创建 annotated tag `v1.4.4`。
- Release notes 来自 `CHANGELOG.md` 的 v1.4.4 区段。
- 任何本地测试、敏感信息、签名、ZIP 或远程创建失败都停止后续推送；不把局部成功表述为完整发布。

## 验收

- Git 忽略规则生效，暂存区不含构建缓存、备份、安装态数据或 QA 帧。
- 暂存文件敏感信息扫描为 0 个发现，单文件均小于 100 MiB。
- `swift test`、素材测试、AppKit 渲染/行为测试、Release 构建、严格 codesign 和 ZIP 校验通过。
- 从全新临时克隆执行测试和 Release 构建成功。
- GitHub 仓库确认为 private，`main` 与 `v1.4.4` 已推送，Release 资产可列出且远端 SHA-256 与本地一致。
