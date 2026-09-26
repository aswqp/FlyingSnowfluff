#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");

const [sourcePath, app2xPath, app1xPath, contactSheetPath, frames2xPath, frames1xPath] = process.argv.slice(2);
if (!sourcePath || !app2xPath || !app1xPath || !contactSheetPath || !frames2xPath || !frames1xPath) {
  console.error("usage: build_sprite_atlases.cjs source.png app2x.png app1x.png contact-sheet.png frames@2x frames@1x");
  process.exit(2);
}

const SOURCE_SIZE = 1254;
const SOURCE_CELL = 418;
const ROWS = 9;
const COLUMNS = 8;
const CELL_WIDTH_2X = 384;
const CELL_HEIGHT_2X = 416;
const WIDTH_2X = CELL_WIDTH_2X * COLUMNS;
const HEIGHT_2X = CELL_HEIGHT_2X * ROWS;
const FRAME_COUNTS = [6, 8, 8, 4, 5, 8, 6, 6, 6];
const BASELINE_2X = 390;
const SATURATION_FACTOR = 1.3;

// Motions remain inside an eight-device-pixel baseline window. Each frame is
// independently resampled from its 418x418 master pose, never from the 1x atlas.
const MOTION = [
  { scale: [0.99, 1.0, 1.01, 1.02, 1.01, 1.0], x: [0, 0, 0, 0, 0, 0], y: [2, 1, 0, -1, 0, 1] },
  { scale: [1, 1, 1, 1, 1, 1, 1, 1], x: [-4, -2, 0, 2, 4, 2, 0, -2], y: [2, 1, 0, -1, -2, -1, 0, 1] },
  { scale: [1, 1, 1, 1, 1, 1, 1, 1], x: [4, 2, 0, -2, -4, -2, 0, 2], y: [2, 1, 0, -1, -2, -1, 0, 1] },
  { scale: [1, 1.01, 1, 0.99], x: [0, 1, 0, -1], y: [1, 0, -1, 0] },
  { scale: [0.99, 1, 1.01, 1, 0.99], x: [0, 0, 0, 0, 0], y: [4, 0, -4, 0, 4] },
  { scale: [1, 1, 1, 1, 1, 1, 1, 1], x: [-3, 3, -2, 2, -3, 3, -1, 1], y: [0, 1, 0, -1, 0, 1, 0, -1] },
  { scale: [0.99, 1, 1.01, 1, 0.99, 1], x: [0, 0, 0, 0, 0, 0], y: [1, 0, -1, 0, 1, 0] },
  { scale: [1, 1.01, 1, 0.99, 1, 1.01], x: [-1, 0, 1, 0, -1, 0], y: [1, 0, -1, 0, 1, 0] },
  { scale: [0.99, 1, 1.01, 1.02, 1.01, 1], x: [-2, -1, 0, 1, 2, 0], y: [3, 0, -3, -5, -2, 2] },
];

function rgbToHsv(red, green, blue) {
  const r = red / 255;
  const g = green / 255;
  const b = blue / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  let hue = 0;
  if (delta > 0) {
    if (max === r) hue = 60 * (((g - b) / delta) % 6);
    else if (max === g) hue = 60 * ((b - r) / delta + 2);
    else hue = 60 * ((r - g) / delta + 4);
    if (hue < 0) hue += 360;
  }
  return { hue, saturation: max > 0 ? delta / max : 0, value: max };
}

function hsvToRgb(hue, saturation, value) {
  const chroma = value * saturation;
  const x = chroma * (1 - Math.abs(((hue / 60) % 2) - 1));
  const match = value - chroma;
  let rgb;
  if (hue < 60) rgb = [chroma, x, 0];
  else if (hue < 120) rgb = [x, chroma, 0];
  else if (hue < 180) rgb = [0, chroma, x];
  else if (hue < 240) rgb = [0, x, chroma];
  else if (hue < 300) rgb = [x, 0, chroma];
  else rgb = [chroma, 0, x];
  return rgb.map((channel) => Math.round((channel + match) * 255));
}

function selectivelyTuneColor(raw) {
  const adjusted = Buffer.from(raw);
  for (let offset = 0; offset < adjusted.length; offset += 4) {
    const alpha = adjusted[offset + 3];
    if (alpha === 0) {
      adjusted[offset] = 0;
      adjusted[offset + 1] = 0;
      adjusted[offset + 2] = 0;
      continue;
    }
    const hsv = rgbToHsv(adjusted[offset], adjusted[offset + 1], adjusted[offset + 2]);
    // Start cyan at 180 degrees. Green-cyan pixels below that boundary are not
    // part of the palette adjustment and must never be pushed toward green.
    const cyanOrPurple = hsv.hue >= 180 && hsv.hue <= 330 && hsv.saturation >= 0.18;
    const vividPink = (hsv.hue > 330 || hsv.hue < 12) && hsv.saturation >= 0.35;
    if (!cyanOrPurple && !vividPink) continue;
    const [red, green, blue] = hsvToRgb(
      hsv.hue,
      Math.min(1, hsv.saturation * SATURATION_FACTOR),
      hsv.value,
    );
    adjusted[offset] = red;
    adjusted[offset + 1] = green;
    adjusted[offset + 2] = blue;
  }
  return adjusted;
}

function findBounds(raw, width, pose) {
  const originX = (pose % 3) * SOURCE_CELL;
  const originY = Math.floor(pose / 3) * SOURCE_CELL;
  let minX = SOURCE_CELL;
  let minY = SOURCE_CELL;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < SOURCE_CELL; y += 1) {
    for (let x = 0; x < SOURCE_CELL; x += 1) {
      const alpha = raw[((originY + y) * width + originX + x) * 4 + 3];
      if (alpha === 0) continue;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }
  if (maxX < 0) throw new Error(`source pose ${pose} is empty`);
  return { originX, originY, minX, minY, maxX, maxY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function clearTransparentRgb(raw) {
  let cleared = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    if (raw[offset + 3] !== 0) continue;
    if (raw[offset] || raw[offset + 1] || raw[offset + 2]) cleared += 1;
    raw[offset] = 0;
    raw[offset + 1] = 0;
    raw[offset + 2] = 0;
  }
  return cleared;
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

function neutralizeGreenFringe(raw) {
  let corrected = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    const red = raw[offset];
    const green = raw[offset + 1];
    const blue = raw[offset + 2];
    if (isGreenFringe(red, green, blue, raw[offset + 3])) {
      // Lanczos can undershoot the blue channel by a few values around the
      // cyan data-light edges. Restore cyan chroma without touching alpha.
      raw[offset + 2] = green;
      corrected += 1;
    }
  }
  return corrected;
}

async function writeSrgbPng(raw, width, height, outputPath) {
  await sharp(raw, { raw: { width, height, channels: 4 } })
    .withIccProfile("srgb")
    .png({ compressionLevel: 9, adaptiveFiltering: false, palette: false })
    .toFile(outputPath);
}

function prepareFrameDirectory(directory, expectedBasename) {
  const resolved = path.resolve(directory);
  if (path.basename(resolved) !== expectedBasename || resolved === path.parse(resolved).root) {
    throw new Error(`refusing to clean unexpected frame directory: ${resolved}`);
  }
  fs.rmSync(resolved, { recursive: true, force: true });
  fs.mkdirSync(resolved, { recursive: true });
}

function extractAtlasCell(raw, atlasWidth, cellWidth, cellHeight, row, column) {
  const cell = Buffer.alloc(cellWidth * cellHeight * 4);
  for (let y = 0; y < cellHeight; y += 1) {
    const sourceStart = (((row * cellHeight + y) * atlasWidth) + column * cellWidth) * 4;
    const targetStart = y * cellWidth * 4;
    raw.copy(cell, targetStart, sourceStart, sourceStart + cellWidth * 4);
  }
  return cell;
}

async function writeFrameDirectory(raw, atlasWidth, cellWidth, cellHeight, directory) {
  for (let row = 0; row < ROWS; row += 1) {
    await Promise.all(Array.from({ length: COLUMNS }, async (_, column) => {
      const cell = extractAtlasCell(raw, atlasWidth, cellWidth, cellHeight, row, column);
      await writeSrgbPng(cell, cellWidth, cellHeight, path.join(directory, `r${row}-c${column}.png`));
    }));
  }
}

(async () => {
  const source = sharp(sourcePath, { failOn: "error" });
  const metadata = await source.metadata();
  if (metadata.width !== SOURCE_SIZE || metadata.height !== SOURCE_SIZE || !metadata.hasAlpha) {
    throw new Error(`source must be ${SOURCE_SIZE}x${SOURCE_SIZE} RGBA`);
  }
  const { data: sourceRaw, info } = await source.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (info.channels !== 4) throw new Error(`source decoded with ${info.channels} channels, expected 4`);
  prepareFrameDirectory(frames2xPath, "frames@2x");
  prepareFrameDirectory(frames1xPath, "frames@1x");
  const adjustedSource = selectivelyTuneColor(sourceRaw);
  const sourceImage = sharp(adjustedSource, {
    raw: { width: SOURCE_SIZE, height: SOURCE_SIZE, channels: 4 },
  });
  const bounds = FRAME_COUNTS.map((_, pose) => findBounds(adjustedSource, SOURCE_SIZE, pose));
  const overlays = [];

  for (let row = 0; row < ROWS; row += 1) {
    const crop = bounds[row];
    for (let column = 0; column < FRAME_COUNTS[row]; column += 1) {
      const motion = MOTION[row];
      const scale = 0.92 * motion.scale[column];
      const width = Math.round(crop.width * scale);
      const height = Math.round(crop.height * scale);
      const { data } = await sourceImage
        .clone()
        .extract({
          left: crop.originX + crop.minX,
          top: crop.originY + crop.minY,
          width: crop.width,
          height: crop.height,
        })
        .resize(width, height, { kernel: sharp.kernel.lanczos3, fit: "fill" })
        .ensureAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });
      clearTransparentRgb(data);
      const leftInCell = Math.round((CELL_WIDTH_2X - width) / 2) + motion.x[column];
      const topInCell = BASELINE_2X + motion.y[column] - (height - 1);
      if (leftInCell < 0 || topInCell < 0 || leftInCell + width > CELL_WIDTH_2X || topInCell + height > CELL_HEIGHT_2X) {
        throw new Error(`row ${row} frame ${column} would be clipped`);
      }
      overlays.push({
        input: data,
        raw: { width, height, channels: 4 },
        left: column * CELL_WIDTH_2X + leftInCell,
        top: row * CELL_HEIGHT_2X + topInCell,
      });
    }
  }

  const { data: atlas2xRaw } = await sharp({
    create: { width: WIDTH_2X, height: HEIGHT_2X, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite(overlays)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  clearTransparentRgb(atlas2xRaw);
  neutralizeGreenFringe(atlas2xRaw);
  await writeSrgbPng(atlas2xRaw, WIDTH_2X, HEIGHT_2X, app2xPath);

  const { data: atlas1xRaw, info: atlas1xInfo } = await sharp(app2xPath)
    .resize(WIDTH_2X / 2, HEIGHT_2X / 2, { kernel: sharp.kernel.lanczos3, fit: "fill" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  clearTransparentRgb(atlas1xRaw);
  neutralizeGreenFringe(atlas1xRaw);
  await writeSrgbPng(atlas1xRaw, atlas1xInfo.width, atlas1xInfo.height, app1xPath);
  await writeFrameDirectory(atlas2xRaw, WIDTH_2X, CELL_WIDTH_2X, CELL_HEIGHT_2X, frames2xPath);
  await writeFrameDirectory(atlas1xRaw, atlas1xInfo.width, CELL_WIDTH_2X / 2, CELL_HEIGHT_2X / 2, frames1xPath);
  fs.copyFileSync(app1xPath, contactSheetPath);

  console.log(`BUILT app2x=${WIDTH_2X}x${HEIGHT_2X} app1x=${atlas1xInfo.width}x${atlas1xInfo.height} standaloneFrames=72x2 frames=${FRAME_COUNTS.join(",")}`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
