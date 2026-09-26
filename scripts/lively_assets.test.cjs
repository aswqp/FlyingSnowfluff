const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '../Resources/v3');
const width = 384;
const height = 416;
const rigParts = ['body', 'wingLeft', 'wingRight', 'hairLeft', 'hairRight'];
const requiredClips = [
  'idle', 'lookLeft', 'lookRight', 'flyRight', 'flyLeft',
  'wave', 'shy', 'tilt', 'adjustVisor', 'nap', 'sway', 'peek',
  'working', 'waiting', 'failed', 'celebrate', 'focused',
];

async function decode(file) {
  const image = sharp(file, { failOn: 'error' });
  const metadata = await image.metadata();
  const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { metadata, data, info };
}

function inspectPixels(data) {
  let visible = 0;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  let greenFringe = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const [red, green, blue, alpha] = data.subarray(offset, offset + 4);
      if (alpha === 0) continue;
      visible += 1;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
      const pureKey = green > 175 && red < 75 && blue < 75;
      const spill = alpha < 240 && green >= 100 && green - red >= 40 && green - blue >= 40;
      if (pureKey || spill) greenFringe += 1;
    }
  }
  return { visible, minX, minY, maxX, maxY, greenFringe };
}

test('motion manifest names existing PNG frames with reasonable timing', () => {
  const manifestPath = path.join(root, 'motion.json');
  assert.ok(fs.existsSync(manifestPath), 'motion.json is missing');
  const manifest = JSON.parse(fs.readFileSync(manifestPath));
  assert.equal(manifest.version, 1);
  assert.equal(manifest.width, width);
  assert.equal(manifest.height, height);
  assert.deepEqual(Object.keys(manifest.clips).sort(), requiredClips.sort(), 'clip set changed unexpectedly');

  for (const [name, clip] of Object.entries(manifest.clips)) {
    assert.ok(Array.isArray(clip.frames) && clip.frames.length > 0, `${name} has no frames`);
    assert.equal(clip.durations.length, clip.frames.length, `${name} frame/duration count mismatch`);
    for (const frame of clip.frames) {
      assert.match(frame, /^[A-Za-z][A-Za-z0-9-]*$/, `${name} has unsafe frame name`);
      assert.ok(fs.existsSync(path.join(root, `${frame}.png`)), `${name} references missing ${frame}.png`);
    }
    for (const duration of clip.durations) {
      assert.ok(Number.isFinite(duration) && duration >= 0.05 && duration <= 10, `${name} has unreasonable duration ${duration}`);
    }
    const total = clip.durations.reduce((sum, duration) => sum + duration, 0);
    assert.ok(total >= 0.1 && total <= 30, `${name} total duration ${total} is unreasonable`);
    assert.equal(typeof clip.loop, 'boolean', `${name} loop must be boolean`);
    assert.equal(clip.anchor.length, 2, `${name} anchor must be a point`);
    assert.ok(clip.anchor.every((value) => Number.isFinite(value) && value >= 0 && value <= 1), `${name} anchor outside unit bounds`);
    assert.ok(Number.isFinite(clip.interruptAfter) && clip.interruptAfter >= 0 && clip.interruptAfter <= total, `${name} interruptAfter outside clip`);
  }
});

test('every root motion PNG is RGBA sRGB, populated, fringe-free, and safely inset', async () => {
  const names = fs.readdirSync(root).filter((name) => name.endsWith('.png')).sort();
  assert.ok(names.length >= 29, `expected the complete motion set, found ${names.length}`);
  for (const name of names) {
    const decoded = await decode(path.join(root, name));
    assert.equal(decoded.metadata.format, 'png', `${name} format`);
    assert.equal(decoded.metadata.width, width, `${name} width`);
    assert.equal(decoded.metadata.height, height, `${name} height`);
    assert.equal(decoded.metadata.hasAlpha, true, `${name} alpha`);
    assert.equal(decoded.metadata.space, 'srgb', `${name} color space`);
    assert.ok(decoded.metadata.icc?.length > 0, `${name} must embed an sRGB ICC profile`);
    assert.equal(decoded.info.channels, 4, `${name} must decode as RGBA`);

    const pixels = inspectPixels(decoded.data);
    assert.ok(pixels.visible >= 100, `${name} is empty or nearly empty`);
    assert.equal(pixels.greenFringe, 0, `${name} contains green-key fringe pixels`);
    assert.ok(pixels.minX >= 2, `${name} is too close to the left edge`);
    assert.ok(pixels.minY >= 2, `${name} is too close to the top edge`);
    assert.ok(pixels.maxX <= width - 3, `${name} is too close to the right edge`);
    assert.ok(pixels.maxY <= height - 3, `${name} is too close to the bottom edge`);
  }
});

test('neutral rig reconstructs the canonical pose with same-color seam overlap', async () => {
  const neutral = await decode(path.join(root, 'neutral.png'));
  const parts = await Promise.all(rigParts.map((part) => decode(path.join(root, `neutral-${part}.png`))));
  const composed = Buffer.alloc(neutral.data.length);

  for (let offset = 0; offset < composed.length; offset += 4) {
    const contributors = parts.filter(({ data }) => data[offset + 3] > 0);
    for (const contributor of contributors) {
      assert.equal(
        Buffer.compare(contributor.data.subarray(offset, offset + 4), neutral.data.subarray(offset, offset + 4)),
        0,
        `neutral rig overlap changed canonical RGBA at pixel ${offset / 4}`,
      );
    }
    if (contributors.length > 0) contributors.at(-1).data.copy(composed, offset, offset, offset + 4);
  }

  assert.equal(Buffer.compare(composed, neutral.data), 0, 'neutral rig composition differs from neutral.png');

  const body = parts[0].data;
  for (let index = 1; index < parts.length; index += 1) {
    const moving = parts[index].data;
    let overlap = 0;
    for (let offset = 0; offset < body.length; offset += 4) {
      if (body[offset + 3] > 28 && moving[offset + 3] > 28) overlap += 1;
    }
    assert.ok(
      overlap >= 300 && overlap <= 700,
      `${rigParts[index]} needs 300-700 same-color seam pixels, found ${overlap}`,
    );
  }
});
