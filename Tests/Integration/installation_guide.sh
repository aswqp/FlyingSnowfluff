#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
GUIDE="$PROJECT_DIR/Packaging/安装与使用说明.md"
missing=0

require_text() {
  local expected="$1"
  if ! rg -Fq -- "$expected" "$GUIDE"; then
    print -u2 "MISSING: $expected"
    missing=1
  fi
}

require_text '## 本机完整安装（`install_local.sh`）'
require_text '## 接收者仅解压分享 ZIP'
require_text '在解压目录中右键 `FlyingSnowfluff.app` 并选择“打开”'
require_text '也可自行将 `FlyingSnowfluff.app` 移动到 `~/Applications`'
require_text '不会自动创建桌面 Finder 别名、安装 Codex 宠物、写入 hooks 或启用登录项'
require_text '必须同时发送 `飞行雪绒·爱弥斯-分享包-macOS-arm64.zip` 与同名 `.zip.sha256`'
require_text 'SHA-256 仅验证传输完整性'
require_text 'ad-hoc 本机签名不证明发布者身份，也不等于 Apple Developer ID 公证'
require_text '可信的本机安装流程'
require_text '仅适用于已在本机完成 `install_local.sh` 完整安装的用户'
require_text '`~/.codex/flying-snowfluff-backups/`'
require_text '`~/.codex/hooks.json.backup-<timestamp>`'
require_text '不要将 hooks 合并器备份误认为位于 `flying-snowfluff-backups`'
require_text '配置 6 个只调用本地 `flyingsnowfluffctl` 的命令'
require_text '可能只列出 5 个可执行处理器'
require_text '不要仅因此从配置中删除它'

if (( missing )); then
  print -u2 'FAIL: installation/share guide contract'
  exit 1
fi

print 'PASS: installation/share guide contract'
