#!/usr/bin/env node

const fs = require("node:fs");
const crypto = require("node:crypto");
const path = require("node:path");
const sharp = require("sharp");

const SELF_TEST = process.argv[2] === "--self-test";
const [app2xPath, app1xPath, codexPath, validationPath, masterPath, oldMasterPath] = SELF_TEST ? [] : process.argv.slice(2);
if (!SELF_TEST && (!app2xPath || !app1xPath || !codexPath || !validationPath || !masterPath || !oldMasterPath)) {
  console.error("usage: encode_and_validate_assets.cjs app2x.png app1x.png codex.webp validation.json master.png old-master.png");
  process.exit(2);
}

const CONTRACT = {
  rows: 9,
  columns: 8,
  frameCounts: [6, 8, 8, 4, 5, 8, 6, 6, 6],
  app2x: { width: 3072, height: 3744, cellWidth: 384, cellHeight: 416, baselineLimit: 8 },
  app1x: { width: 1536, height: 1872, cellWidth: 192, cellHeight: 208, baselineLimit: 4 },
};

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

function rgbToLab(red, green, blue) {
  const [r, g, b] = [red, green, blue].map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  const x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  const y = r * 0.2126729 + g * 0.7151522 + b * 0.072175;
  const z = (r * 0.0193339 + g * 0.119192 + b * 0.9503041) / 1.08883;
  const pivot = (value) => (value > 0.008856 ? value ** (1 / 3) : 7.787 * value + 16 / 116);
  const fx = pivot(x);
  const fy = pivot(y);
  const fz = pivot(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
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

function frameBounds(raw, atlasWidth, cell, row, column) {
  let minX = cell.cellWidth;
  let minY = cell.cellHeight;
  let maxX = -1;
  let maxY = -1;
  let visiblePixels = 0;
  let greenFringePixels = 0;
  let transparentRGBResidue = 0;
  const originX = column * cell.cellWidth;
  const originY = row * cell.cellHeight;
  for (let y = 0; y < cell.cellHeight; y += 1) {
    for (let x = 0; x < cell.cellWidth; x += 1) {
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
  const bounds = visiblePixels ? { minX, minY, maxX, maxY } : null;
  return {
    row,
    column,
    visiblePixels,
    greenFringePixels,
    transparentRGBResidue,
    cropped: Boolean(bounds && (minX === 0 || minY === 0 || maxX === cell.cellWidth - 1 || maxY === cell.cellHeight - 1)),
    bounds,
  };
}

function inspectFrames(raw, atlasWidth, cell, label, errors, warnings) {
  const details = [];
  let greenFringePixels = 0;
  let transparentRGBResidue = 0;
  let croppedFrames = 0;
  let maxBaselineDrift = 0;
  let usedFrames = 0;
  let unusedFrames = 0;
  for (let row = 0; row < CONTRACT.rows; row += 1) {
    for (let column = 0; column < CONTRACT.columns; column += 1) {
      const frame = frameBounds(raw, atlasWidth, cell, row, column);
      details.push(frame);
      greenFringePixels += frame.greenFringePixels;
      transparentRGBResidue += frame.transparentRGBResidue;
      if (frame.cropped) croppedFrames += 1;
      const shouldBeUsed = column < CONTRACT.frameCounts[row];
      if (shouldBeUsed) {
        usedFrames += 1;
        if (frame.visiblePixels < 100) errors.push(`${label} row ${row} frame ${column} is unexpectedly empty`);
        if (frame.cropped) errors.push(`${label} row ${row} frame ${column} touches a cell edge`);
      } else {
        unusedFrames += 1;
        if (frame.visiblePixels !== 0) errors.push(`${label} row ${row} frame ${column} must be fully transparent`);
      }
      if (frame.greenFringePixels > 0) {
        errors.push(`${label} row ${row} frame ${column} has ${frame.greenFringePixels} green fringe pixels`);
      }
    }
    const used = details.filter((frame) => frame.row === row && frame.column < CONTRACT.frameCounts[row]);
    const baselines = used.map((frame) => frame.bounds.maxY);
    const drift = Math.max(...baselines) - Math.min(...baselines);
    maxBaselineDrift = Math.max(maxBaselineDrift, drift);
    if (drift > cell.baselineLimit) errors.push(`${label} row ${row} baseline drift ${drift} exceeds ${cell.baselineLimit}`);
  }
  if (transparentRGBResidue > 0) warnings.push(`${label} has ${transparentRGBResidue} transparent pixels with RGB residue`);
  return { details, greenFringePixels, transparentRGBResidue, croppedFrames, maxBaselineDrift, usedFrames, unusedFrames };
}

function meanSaturation(raw) {
  let weightedSaturation = 0;
  let alphaWeight = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    const alpha = raw[offset + 3] / 255;
    if (alpha === 0) continue;
    weightedSaturation += rgbToHsv(raw[offset], raw[offset + 1], raw[offset + 2]).saturation * alpha;
    alphaWeight += alpha;
  }
  return weightedSaturation / alphaWeight;
}

function skinLab(raw) {
  const sums = [0, 0, 0];
  let weight = 0;
  let samples = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    const alpha = raw[offset + 3] / 255;
    if (alpha < 0.5) continue;
    const hsv = rgbToHsv(raw[offset], raw[offset + 1], raw[offset + 2]);
    const warm = hsv.hue >= 330 || hsv.hue <= 60;
    if (!warm || hsv.saturation < 0.025 || hsv.saturation > 0.24 || hsv.value < 0.72 || hsv.value > 0.99) continue;
    const lab = rgbToLab(raw[offset], raw[offset + 1], raw[offset + 2]);
    for (let index = 0; index < 3; index += 1) sums[index] += lab[index] * alpha;
    weight += alpha;
    samples += 1;
  }
  return { samples, meanLab: sums.map((sum) => sum / weight) };
}

function silverWhiteStats(raw) {
  let samples = 0;
  let clippedChannelPixels = 0;
  let blueBiasedPixels = 0;
  let blueBiasSum = 0;
  for (let offset = 0; offset < raw.length; offset += 4) {
    if (raw[offset + 3] < 128) continue;
    const red = raw[offset];
    const green = raw[offset + 1];
    const blue = raw[offset + 2];
    const hsv = rgbToHsv(red, green, blue);
    if (hsv.saturation > 0.18 || hsv.value < 0.72) continue;
    const blueBias = blue - (red + green) / 2;
    samples += 1;
    if (red === 255 || green === 255 || blue === 255) clippedChannelPixels += 1;
    if (blueBias > 18) blueBiasedPixels += 1;
    blueBiasSum += blueBias;
  }
  return {
    samples,
    clippedChannelPixels,
    clippedChannelRatio: samples > 0 ? clippedChannelPixels / samples : 0,
    blueBiasedPixels,
    blueBiasedPixelRatio: samples > 0 ? blueBiasedPixels / samples : 0,
    meanBlueBias: samples > 0 ? blueBiasSum / samples : 0,
  };
}

function validateSilverWhiteStats(stats, errors) {
  const ratios = [stats.clippedChannelRatio, stats.blueBiasedPixelRatio, stats.meanBlueBias];
  if (stats.samples === 0) {
    errors.push("silver-white highlight sample set is empty");
    return;
  }
  if (ratios.some((value) => !Number.isFinite(value))) {
    errors.push("silver-white highlight ratios must be finite");
    return;
  }
  if (stats.clippedChannelRatio > 0.18) errors.push("silver-white highlight channel clipping is excessive");
  if (stats.meanBlueBias > 5 || stats.blueBiasedPixelRatio > 0.22) {
    errors.push("silver-white highlights are visibly blue-biased");
  }
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
    const red = raw[offset];
    const green = raw[offset + 1];
    const blue = raw[offset + 2];
    if (isGreenFringe(red, green, blue, raw[offset + 3])) raw[offset + 2] = green;
  }
}

async function decode(filePath) {
  const image = sharp(filePath, { failOn: "error" });
  const metadata = await image.metadata();
  const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { metadata, raw: data, info, bytes: fs.statSync(filePath).size };
}

function describeRaster(filePath, decoded) {
  return {
    file: path.basename(filePath),
    width: decoded.metadata.width,
    height: decoded.metadata.height,
    format: decoded.metadata.format,
    hasAlpha: decoded.metadata.hasAlpha,
    colorSpace: decoded.metadata.space,
    embeddedIcc: Boolean(decoded.metadata.icc && decoded.metadata.icc.length),
    bytes: decoded.bytes,
    sha256: crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex"),
  };
}

function validateRaster(label, decoded, expected, errors) {
  if (decoded.metadata.width !== expected.width || decoded.metadata.height !== expected.height) {
    errors.push(`${label} must be ${expected.width}x${expected.height}, got ${decoded.metadata.width}x${decoded.metadata.height}`);
  }
  if (!decoded.metadata.hasAlpha || decoded.info.channels !== 4) errors.push(`${label} must decode as RGBA`);
  if (decoded.metadata.space !== "srgb") errors.push(`${label} must declare sRGB`);
  if (!decoded.metadata.icc || decoded.metadata.icc.length === 0) errors.push(`${label} must embed an sRGB ICC profile`);
}

function runSelfTest() {
  const zeroSample = silverWhiteStats(Buffer.from([0, 0, 0, 255]));
  const errors = [];
  validateSilverWhiteStats(zeroSample, errors);
  const finite = [zeroSample.clippedChannelRatio, zeroSample.blueBiasedPixelRatio, zeroSample.meanBlueBias]
    .every((value) => Number.isFinite(value));
  const greenSpillDetected = isGreenFringe(20, 190, 80, 96);
  const cyanProtected = !isGreenFringe(20, 190, 215, 96);
  if (!finite || !errors.some((error) => /sample set is empty/.test(error)) || !greenSpillDetected || !cyanProtected) {
    throw new Error("validator self-test failed");
  }
  console.log("PASS validator self-test: zero-sample rejection and green-spill/cyan discrimination");
}

if (SELF_TEST) {
  runSelfTest();
} else {
(async () => {
  const errors = [];
  const warnings = [];
  const app2x = await decode(app2xPath);
  const app1x = await decode(app1xPath);
  validateRaster("app2x", app2x, CONTRACT.app2x, errors);
  validateRaster("fallback1x", app1x, CONTRACT.app1x, errors);

  const frames2x = inspectFrames(app2x.raw, CONTRACT.app2x.width, CONTRACT.app2x, "app2x", errors, warnings);
  const frames1x = inspectFrames(app1x.raw, CONTRACT.app1x.width, CONTRACT.app1x, "fallback1x", errors, warnings);

  const { data: derivedRaw } = await sharp(app2xPath)
    .resize(CONTRACT.app1x.width, CONTRACT.app1x.height, { kernel: sharp.kernel.lanczos3, fit: "fill" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  clearTransparentRgb(derivedRaw);
  neutralizeGreenFringe(derivedRaw);
  let derivedMismatchPixels = 0;
  for (let offset = 0; offset < derivedRaw.length; offset += 4) {
    if (
      derivedRaw[offset] !== app1x.raw[offset]
      || derivedRaw[offset + 1] !== app1x.raw[offset + 1]
      || derivedRaw[offset + 2] !== app1x.raw[offset + 2]
      || derivedRaw[offset + 3] !== app1x.raw[offset + 3]
    ) derivedMismatchPixels += 1;
  }
  if (derivedMismatchPixels > 0) errors.push(`fallback1x differs from direct 2x downsample at ${derivedMismatchPixels} pixels`);

  await sharp(app1xPath)
    .withIccProfile("srgb")
    .webp({ lossless: true, effort: 6, smartSubsample: false })
    .toFile(codexPath);
  const codex = await decode(codexPath);
  validateRaster("codex", codex, CONTRACT.app1x, errors);
  if (codex.bytes > 20 * 1024 * 1024) errors.push("codex WebP exceeds 20 MiB");
  const framesCodex = inspectFrames(codex.raw, CONTRACT.app1x.width, CONTRACT.app1x, "codex", errors, warnings);
  let codexMismatchPixels = 0;
  for (let offset = 0; offset < codex.raw.length; offset += 4) {
    const alphaMatches = codex.raw[offset + 3] === app1x.raw[offset + 3];
    const visibleRgbMatches = codex.raw[offset + 3] === 0 || (
      codex.raw[offset] === app1x.raw[offset]
      && codex.raw[offset + 1] === app1x.raw[offset + 1]
      && codex.raw[offset + 2] === app1x.raw[offset + 2]
    );
    if (!alphaMatches || !visibleRgbMatches) codexMismatchPixels += 1;
  }
  if (codexMismatchPixels > 0) errors.push(`lossless Codex WebP differs visibly from fallback1x at ${codexMismatchPixels} pixels`);

  const master = await decode(masterPath);
  const oldMaster = await decode(oldMasterPath);
  const atlasSaturation = meanSaturation(app2x.raw);
  const masterSaturation = meanSaturation(master.raw);
  if (atlasSaturation < 0.31 || atlasSaturation > 0.35) {
    errors.push(`mean saturation ${atlasSaturation.toFixed(6)} is outside 0.31...0.35`);
  }
  const atlasSkin = skinLab(app2x.raw);
  const oldSkin = skinLab(oldMaster.raw);
  const skinDeltaE76 = Math.hypot(...atlasSkin.meanLab.map((value, index) => value - oldSkin.meanLab[index]));
  if (!Number.isFinite(skinDeltaE76) || skinDeltaE76 >= 4) errors.push(`skin CIE76 DeltaE ${skinDeltaE76.toFixed(4)} must be < 4`);
  const silverWhite = silverWhiteStats(app2x.raw);
  validateSilverWhiteStats(silverWhite, errors);

  const report = {
    ok: errors.length === 0,
    source: path.basename(masterPath),
    frameCounts: CONTRACT.frameCounts,
    app2x: describeRaster(app2xPath, app2x),
    fallback1x: describeRaster(app1xPath, app1x),
    codex: describeRaster(codexPath, codex),
    color: {
      meanSaturation: atlasSaturation,
      sourceMeanSaturation: masterSaturation,
      targetSaturation: [0.31, 0.35],
      selectiveSaturation: { hues: "pink/cyan/purple", factor: 1.3, skinProtected: true },
      skinDeltaE76,
      skinSamples: { atlas: atlasSkin.samples, oldMaster: oldSkin.samples },
      skinMeanLab: { atlas: atlasSkin.meanLab, oldMaster: oldSkin.meanLab },
      silverWhite,
    },
    frames: {
      frameCounts: CONTRACT.frameCounts,
      greenFringePixels: frames2x.greenFringePixels + frames1x.greenFringePixels + framesCodex.greenFringePixels,
      transparentRGBResidue: frames2x.transparentRGBResidue + frames1x.transparentRGBResidue + framesCodex.transparentRGBResidue,
      croppedFrames: frames2x.croppedFrames + frames1x.croppedFrames + framesCodex.croppedFrames,
      maxBaselineDrift2x: frames2x.maxBaselineDrift,
      maxBaselineDrift1x: frames1x.maxBaselineDrift,
      derivedMismatchPixels,
      codexMismatchPixels,
      usedFrames: frames2x.usedFrames,
      unusedFrames: frames2x.unusedFrames,
      codex: {
        greenFringePixels: framesCodex.greenFringePixels,
        transparentRGBResidue: framesCodex.transparentRGBResidue,
        croppedFrames: framesCodex.croppedFrames,
        maxBaselineDrift: framesCodex.maxBaselineDrift,
        usedFrames: framesCodex.usedFrames,
        unusedFrames: framesCodex.unusedFrames,
      },
      app2x: frames2x.details,
      fallback1x: frames1x.details,
    },
    errors,
    warnings,
  };
  fs.writeFileSync(validationPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o644 });
  if (!report.ok) {
    console.error(JSON.stringify(report, null, 2));
    process.exit(1);
  }
  console.log(`PASS app2x=${app2x.metadata.width}x${app2x.metadata.height} app1x=${app1x.metadata.width}x${app1x.metadata.height} webp=${codex.bytes}B saturation=${atlasSaturation.toFixed(6)} skinDeltaE76=${skinDeltaE76.toFixed(4)} greenFringe=0`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
}
