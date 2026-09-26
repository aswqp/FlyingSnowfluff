const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const test = require('node:test');
const sharp = require('sharp');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const directory = process.env.SNOWFLUFF_SKIN_DIR || path.join(root, 'Resources/CodexPet');
const counts = [6,8,8,4,5,8,6,6,6];
const hash = b => crypto.createHash('sha256').update(b).digest('hex');

test('installed skin is exported from the approved lively artwork, not the old atlas', async () => {
  const metadata = JSON.parse(fs.readFileSync(path.join(directory, 'pet.json')));
  const atlas = await sharp(path.join(directory, metadata.spritesheetPath)).ensureAlpha().raw().toBuffer();
  const cell = Buffer.alloc(192*208*4);
  for(let y=0;y<208;y++) atlas.copy(cell,y*192*4,y*1536*4,(y*1536+192)*4);
  const expected = await sharp(path.join(root,'Resources/v3/neutral.png')).resize(192,208).ensureAlpha().raw().toBuffer();
  // Compare silhouette overlap, independent of CoreAnimation color conversion.
  let intersection=0,union=0;
  for(let i=3;i<cell.length;i+=4){
    const a=cell[i]>80,b=expected[i]>80;
    if(a&&b)intersection++;if(a||b)union++;
  }
  assert.ok(intersection/union>.94, `new neutral silhouette overlap ${intersection/union}; old skin is still installed`);
});

test('compatibility atlas keeps dimensions, alpha, sRGB and exact populated cells', async () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory,'pet.json')));
  assert.equal(manifest.id,'flying-snowfluff-aemeath');
  assert.ok([undefined,1].includes(manifest.spriteVersionNumber),'do not silently migrate the existing v1 skin');
  const file=path.join(directory,manifest.spritesheetPath);
  const meta=await sharp(file).metadata();
  assert.equal(meta.width,1536);assert.equal(meta.height,1872);
  assert.equal(meta.hasAlpha,true);assert.ok(meta.icc?.length);
  assert.ok(fs.statSync(file).size<=20*1024*1024);
  const rgba=await sharp(file).ensureAlpha().raw().toBuffer();
  for(let r=0;r<9;r++){
    const hashes=new Set();
    for(let c=0;c<8;c++){
      const cell=Buffer.alloc(192*208*4);
      for(let y=0;y<208;y++)rgba.copy(cell,y*192*4,((r*208+y)*1536+c*192)*4,((r*208+y)*1536+(c+1)*192)*4);
      const used=c<counts[r];let pixels=0,edge=0;
      for(let y=0;y<208;y++)for(let x=0;x<192;x++){
        const i=(y*192+x)*4;
        if(cell[i+3]===0)assert.equal(cell[i]+cell[i+1]+cell[i+2],0,'hidden RGB residue');
        if(cell[i+3]>0)pixels++;
        if(cell[i+3]>20&&(x<2||x>189||y<2||y>205))edge++;
        assert.ok(!(cell[i+3]>0&&cell[i+1]>175&&cell[i]<75&&cell[i+2]<75),'green chroma remnants');
      }
      assert.equal(pixels>0,used,`population ${r},${c}`);
      assert.equal(edge,0,`clipping ${r},${c}`);
      if(used)hashes.add(hash(cell));
    }
    assert.ok(hashes.size>=3,`row ${r} is visually static`);
  }
});
