# Codex Pet 素材说明

`spritesheet.webp` 是从 `Resources/v3/` 已批准的灵动角色素材导出的 Codex 专用兼容图集，不要求与 App 的 `spritesheet.png` 逐像素相同。

- `scripts/asset_pipeline_contract.test.cjs` 验证 App 2×/1× 图集及基础素材管线报告。
- `scripts/codex_skin_sync.test.cjs` 单独验证这里发布的 Codex Pet：1536×1872、透明/sRGB、57 个有效单元、15 个透明单元、无绿幕残边、无边缘裁切、每行动画具有变化，并确认中性姿势来自 `Resources/v3/neutral.png`。

这两个管线有不同的显示目标；重新运行基础 App 图集生成器时，不应把 Codex 专用动效图集的验证契约改回“逐像素等于 App 1× 图集”。
