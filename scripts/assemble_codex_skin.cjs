const fs=require('node:fs'),path=require('node:path'),sharp=require('sharp');
const [frames,output]=process.argv.slice(2);
if(!frames||!output)throw new Error('usage: assemble_codex_skin.cjs exported-frames output-directory');
const counts=[6,8,8,4,5,8,6,6,6];
const states=['idle','running-right','running-left','waving','jumping','failed','waiting','running','review'];
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const layers=[];
  for(let r=0;r<9;r++)for(let c=0;c<counts[r];c++){
    const file=path.join(frames,`${r}-${c}.png`),meta=await sharp(file).metadata();
    if(meta.width!==384||meta.height!==416||!meta.hasAlpha)throw new Error(`bad native frame ${file}`);
    // Match the pixel-art renderer's nearest minification; Lanczos produces
    // RGB ringing in alpha=1 pixels around saturated cyan edges.
    const input=await sharp(file).resize(192,208,{kernel:'nearest'}).withIccProfile('srgb').png().toBuffer();
    const frameDir=path.join(path.dirname(output),'frames-1x',states[r]);
    fs.mkdirSync(frameDir,{recursive:true});
    fs.writeFileSync(path.join(frameDir,`${String(c).padStart(2,'0')}.png`),input);
    layers.push({input,left:c*192,top:r*208});
  }
  const raw=await sharp({create:{width:1536,height:1872,channels:4,background:{r:0,g:0,b:0,alpha:0}}})
    .composite(layers).ensureAlpha().raw().toBuffer();
  for(let i=0;i<raw.length;i+=4)if(raw[i+3]===0)raw.fill(0,i,i+3);
  // Lossless WebP still changes RGB under alpha=0 unless exact=True is used.
  // Use encode_codex_skin.py after this clean PNG stage, preserving ICC too.
  await sharp(raw,{raw:{width:1536,height:1872,channels:4}}).withIccProfile('srgb')
    .png().toFile(path.join(output,'spritesheet-lively-1.4.1.png'));
  console.log('PASS: existing v1 compatibility atlas assembled from native 2x frames');
})().catch(error=>{console.error(error);process.exit(1)});
