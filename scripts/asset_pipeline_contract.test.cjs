#!/usr/bin/env node

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const LOCAL_NODE_MODULES = process.env.NODE_MODULES
  ?? path.resolve(__dirname, "../node_modules");
process.env.NODE_PATH = process.env.NODE_PATH || LOCAL_NODE_MODULES;

function loadSharp() {
  try {
    return require("sharp");
  } catch (error) {
    if (error?.code !== "MODULE_NOT_FOUND") throw error;
    return require(path.join(LOCAL_NODE_MODULES, "sharp"));
  }
}

const sharp = loadSharp();

const PROJECT_DIR = path.resolve(__dirname, "..");
const APP_2X = path.join(PROJECT_DIR, "Resources/App/spritesheet@2x.png");
const APP_1X = path.join(PROJECT_DIR, "Resources/App/spritesheet.png");
const FRAMES_2X = path.join(PROJECT_DIR, "Resources/App/frames@2x");
const FRAMES_1X = path.join(PROJECT_DIR, "Resources/App/frames@1x");
const CODEX = path.join(PROJECT_DIR, "Resources/CodexPet/spritesheet.webp");
const VALIDATION = path.join(PROJECT_DIR, "Resources/QA/validation.json");
const MASTER = path.join(PROJECT_DIR, "Resources/v2/aemeath-pose-sheet-v2-alpha.png");
const BUILDER = path.join(PROJECT_DIR, "scripts/build_sprite_atlases.cjs");
const VALIDATOR = path.join(PROJECT_DIR, "scripts/encode_and_validate_assets.cjs");
const BUILD_SCRIPT = path.join(PROJECT_DIR, "scripts/build_assets.sh");
const RELEASE_SCRIPT = path.join(PROJECT_DIR, "scripts/build_release.sh");
const FRAME_COUNTS = [6, 8, 8, 4, 5, 8, 6, 6, 6];
const APP_2X_SPEC = { width: 3072, height: 3744, cellWidth: 384, cellHeight: 416, baselineLimit: 8 };
const APP_1X_SPEC = { width: 1536, height: 1872, cellWidth: 192, cellHeight: 208, baselineLimit: 4 };
const decodeCache = new Map();

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function expectedFrameNames() {
  return Array.from({ length: 9 }, (_, row) => (
    Array.from({ length: 8 }, (_, column) => `r${row}-c${column}.png`)
  )).flat();
}

function directoryHashes(directory) {
  return Object.fromEntries(expectedFrameNames().map((name) => [name, sha256(path.join(directory, name))]));
}

async function decode(filePath) {
  if (!decodeCache.has(filePath)) {
    decodeCache.set(filePath, (async () => {
      const image = sharp(filePath, { failOn: "error" });
      const metadata = await image.metadata();
      const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      return { metadata, raw: data, info, bytes: fs.statSync(filePath).size };
    })());
  }
  return decodeCache.get(filePath);
}

function isGreenFringe(red, green, blue, alpha) {
  if (alpha === 0) return false;
  const pureGreenKey = green > 175 && red < 75 && blue < 75;
  const translucentGreenSpill = alpha < 240
    && green >= 100
    && green - red >= 40
    && green - blue >= 40;
  return pureGreenKey || translucentGreenSpill;
}

function clearTransparentRgb(raw) {
  for (let offset = 0; offset < raw.length; offset += 4) {
    if (raw[offset + 3] !== 0) continue;
    raw[offset] = 0;
    raw[offset + 1] = 0;
    raw[offset + 2] = 0;
  }
}

function neutralizeGreenFringe(raw) {
  for (let offset = 0; offset < raw.length; offset += 4) {
    if (isGreenFringe(raw[offset], raw[offset + 1], raw[offset + 2], raw[offset + 3])) {
      raw[offset + 2] = raw[offset + 1];
    }
  }
}

function frameBounds(raw, atlasWidth, spec, row, column) {
  let minX = spec.cellWidth;
  let minY = spec.cellHeight;
  let maxX = -1;
  let maxY = -1;
  let visiblePixels = 0;
  let greenFringePixels = 0;
  let transparentRGBResidue = 0;
  const originX = column * spec.cellWidth;
  const originY = row * spec.cellHeight;
  for (let y = 0; y < spec.cellHeight; y += 1) {
    for (let x = 0; x < spec.cellWidth; x += 1) {
      const offset = ((originY + y) * atlasWidth + originX + x) * 4;
      const red = raw[offset];
      const green = raw[offset + 1];
      const blue = raw[offset + 2];
      const alpha = raw[offset + 3];
      if (alpha > 0) {
        visiblePixels += 1;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
        if (isGreenFringe(red, green, blue, alpha)) greenFringePixels += 1;
      } else if (red !== 0 || green !== 0 || blue !== 0) {
        transparentRGBResidue += 1;
      }
    }
  }
  return {
    row,
    column,
    visiblePixels,
    greenFringePixels,
    transparentRGBResidue,
    bounds: visiblePixels ? { minX, minY, maxX, maxY } : null,
  };
}

function inspectAtlas(decoded, spec, label, requireTransparentRgbZero) {
  const frames = [];
  let greenFringePixels = 0;
  let transparentRGBResidue = 0;
  let maxBaselineDrift = 0;
  for (let row = 0; row < 9; row += 1) {
    const usedInRow = [];
    for (let column = 0; column < 8; column += 1) {
      const frame = frameBounds(decoded.raw, spec.width, spec, row, column);
      frames.push(frame);
      greenFringePixels += frame.greenFringePixels;
      transparentRGBResidue += frame.transparentRGBResidue;
      if (column < FRAME_COUNTS[row]) {
        assert.ok(frame.visiblePixels >= 100, `${label} row ${row} frame ${column} must be populated`);
        assert.ok(frame.bounds.minX > 0, `${label} row ${row} frame ${column} touches left edge`);
        assert.ok(frame.bounds.minY > 0, `${label} row ${row} frame ${column} touches top edge`);
        assert.ok(frame.bounds.maxX < spec.cellWidth - 1, `${label} row ${row} frame ${column} touches right edge`);
        assert.ok(frame.bounds.maxY < spec.cellHeight - 1, `${label} row ${row} frame ${column} touches bottom edge`);
        usedInRow.push(frame);
      } else {
        assert.equal(frame.visiblePixels, 0, `${label} row ${row} unused frame ${column} alpha must be zero`);
      }
    }
    const baselines = usedInRow.map((frame) => frame.bounds.maxY);
    const drift = Math.max(...baselines) - Math.min(...baselines);
    maxBaselineDrift = Math.max(maxBaselineDrift, drift);
    assert.ok(drift <= spec.baselineLimit, `${label} row ${row} baseline drift ${drift} exceeds ${spec.baselineLimit}`);
  }
  assert.equal(greenFringePixels, 0, `${label} has expanded-rule green fringe`);
  if (requireTransparentRgbZero) assert.equal(transparentRGBResidue, 0, `${label} transparent RGB must be zero`);
  return { frames, greenFringePixels, transparentRGBResidue, maxBaselineDrift };
}

function meanSaturation(raw) {
  let weightedSaturation = 0;
  let alphaWeight = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    const alpha = raw[offset + 3] / 255;
    if (alpha === 0) continue;
    const red = raw[offset] / 255;
    const green = raw[offset + 1] / 255;
    const blue = raw[offset + 2] / 255;
    const max = Math.max(red, green, blue);
    const min = Math.min(red, green, blue);
    weightedSaturation += (max > 0 ? (max - min) / max : 0) * alpha;
    alphaWeight += alpha;
  }
  return weightedSaturation / alphaWeight;
}

function assertRasterMetadata(decoded, expected, label) {
  assert.equal(decoded.metadata.width, expected.width, `${label} width`);
  assert.equal(decoded.metadata.height, expected.height, `${label} height`);
  assert.equal(decoded.metadata.hasAlpha, true, `${label} alpha`);
  assert.equal(decoded.info.channels, 4, `${label} RGBA decode`);
  assert.equal(decoded.metadata.format, expected.format, `${label} format`);
  assert.equal(decoded.metadata.space, "srgb", `${label} sRGB declaration`);
  assert.ok(decoded.metadata.icc && decoded.metadata.icc.length > 0, `${label} embedded sRGB ICC`);
}

function extractAtlasCell(raw, spec, row, column) {
  const cell = Buffer.alloc(spec.cellWidth * spec.cellHeight * 4);
  for (let y = 0; y < spec.cellHeight; y += 1) {
    const sourceStart = (((row * spec.cellHeight + y) * spec.width) + column * spec.cellWidth) * 4;
    const targetStart = y * spec.cellWidth * 4;
    raw.copy(cell, targetStart, sourceStart, sourceStart + spec.cellWidth * 4);
  }
  return cell;
}

async function assertFrameDirectory(directory, atlas, spec, label) {
  assert.ok(fs.existsSync(directory), `${label} directory must exist`);
  const actualNames = fs.readdirSync(directory).sort();
  assert.deepEqual(actualNames, expectedFrameNames().sort(), `${label} must contain exactly 72 named PNG files`);
  for (let row = 0; row < 9; row += 1) {
    for (let column = 0; column < 8; column += 1) {
      const name = `r${row}-c${column}.png`;
      const frame = await decode(path.join(directory, name));
      assertRasterMetadata(frame, { width: spec.cellWidth, height: spec.cellHeight, format: "png" }, `${label}/${name}`);
      const expectedRaw = extractAtlasCell(atlas.raw, spec, row, column);
      assert.equal(Buffer.compare(frame.raw, expectedRaw), 0, `${label}/${name} must equal atlas cell RGBA`);
      if (column >= FRAME_COUNTS[row]) {
        assert.ok(frame.raw.every((value) => value === 0), `${label}/${name} unused frame must be fully transparent black`);
      }
    }
  }
}

test("build_assets defaults to the v2 1254px pose sheet", () => {
  const script = fs.readFileSync(BUILD_SCRIPT, "utf8");
  assert.match(script, /Resources\/v2\/aemeath-pose-sheet-v2-alpha\.png/);
});

test("real App atlas files independently satisfy metadata, frame, edge, and baseline contracts", async () => {
  const [app2x, app1x] = await Promise.all([decode(APP_2X), decode(APP_1X)]);
  assertRasterMetadata(app2x, { ...APP_2X_SPEC, format: "png" }, "app2x");
  assertRasterMetadata(app1x, { ...APP_1X_SPEC, format: "png" }, "fallback1x");
  inspectAtlas(app2x, APP_2X_SPEC, "app2x", true);
  inspectAtlas(app1x, APP_1X_SPEC, "fallback1x", true);
});

test("build publishes exactly 72 pixel-identical standalone frames at each scale", async () => {
  const [app2x, app1x] = await Promise.all([decode(APP_2X), decode(APP_1X)]);
  await assertFrameDirectory(FRAMES_2X, app2x, APP_2X_SPEC, "frames@2x");
  await assertFrameDirectory(FRAMES_1X, app1x, APP_1X_SPEC, "frames@1x");
});

test("real 1x App pixels derive from 2x and meet color limits", async () => {
  const [app2x, app1x] = await Promise.all([decode(APP_2X), decode(APP_1X)]);
  const { data: expected1x } = await sharp(APP_2X)
    .resize(APP_1X_SPEC.width, APP_1X_SPEC.height, { kernel: sharp.kernel.lanczos3, fit: "fill" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  clearTransparentRgb(expected1x);
  neutralizeGreenFringe(expected1x);
  assert.equal(Buffer.compare(expected1x, app1x.raw), 0, "fallback1x must exactly match the sanitized Lanczos3 2x downsample");

  const saturation = meanSaturation(app2x.raw);
  assert.ok(saturation >= 0.31 && saturation <= 0.35, `actual saturation ${saturation} outside 0.31...0.35`);
});

test("validation report hashes and key metrics correspond to real artifacts", async () => {
  const report = JSON.parse(fs.readFileSync(VALIDATION, "utf8"));
  const app2x = await decode(APP_2X);
  assert.equal(report.ok, true);
  assert.deepEqual(report.errors, []);
  assert.deepEqual(report.frameCounts, FRAME_COUNTS);
  assert.equal(report.app2x.sha256, sha256(APP_2X));
  assert.equal(report.fallback1x.sha256, sha256(APP_1X));
  assert.ok(Math.abs(report.color.meanSaturation - meanSaturation(app2x.raw)) < 1e-12);
  assert.ok(Number.isFinite(report.color.skinDeltaE76) && report.color.skinDeltaE76 < 4);
});

test("validator self-test rejects zero silver-white samples and distinguishes cyan from green spill", () => {
  const result = spawnSync(process.execPath, [VALIDATOR, "--self-test"], { encoding: "utf8", env: process.env });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /PASS.*zero-sample.*green-spill/i);
});

test("builder is byte-deterministic in two isolated private tmp output directories", { timeout: 30000 }, (t) => {
  const tempRoot = fs.mkdtempSync("/private/tmp/flying-snowfluff-determinism.");
  assert.ok(tempRoot.startsWith("/private/tmp/flying-snowfluff-determinism."));
  t.after(() => fs.rmSync(tempRoot, { recursive: true, force: true }));
  const hashes = [];
  for (const name of ["run-a", "run-b"]) {
    const outputDir = path.join(tempRoot, name);
    fs.mkdirSync(outputDir, { recursive: true });
    const outputs = {
      app2x: path.join(outputDir, "spritesheet@2x.png"),
      app1x: path.join(outputDir, "spritesheet.png"),
      contact: path.join(outputDir, "contact-sheet.png"),
      frames2x: path.join(outputDir, "frames@2x"),
      frames1x: path.join(outputDir, "frames@1x"),
    };
    const result = spawnSync(process.execPath, [
      BUILDER,
      MASTER,
      outputs.app2x,
      outputs.app1x,
      outputs.contact,
      outputs.frames2x,
      outputs.frames1x,
    ], {
      encoding: "utf8",
      env: process.env,
      timeout: 30000,
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    hashes.push({
      app2x: sha256(outputs.app2x),
      app1x: sha256(outputs.app1x),
      contact: sha256(outputs.contact),
      frames2x: directoryHashes(outputs.frames2x),
      frames1x: directoryHashes(outputs.frames1x),
    });
  }
  assert.deepEqual(hashes[0], hashes[1]);
});

test("release bundle packages both the 2x atlas and 1x fallback", () => {
  const script = fs.readFileSync(RELEASE_SCRIPT, "utf8");
  assert.match(script, /Resources\/App\/spritesheet@2x\.png/);
  assert.match(script, /APP_RESOURCES\/spritesheet@2x\.png/);
  assert.match(script, /Resources\/App\/spritesheet\.png/);
  assert.match(script, /APP_RESOURCES\/spritesheet\.png/);
  assert.match(script, /Resources\/App\/frames@2x/);
  assert.match(script, /APP_RESOURCES\/frames@2x/);
  assert.match(script, /Resources\/App\/frames@1x/);
  assert.match(script, /APP_RESOURCES\/frames@1x/);
});
