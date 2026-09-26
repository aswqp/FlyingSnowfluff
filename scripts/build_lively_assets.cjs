// Deterministic extraction/registration of ImageGen artwork; does not invent poses.
const sharp = require('sharp');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../Resources/v3');
const W=384,H=416;
// Match the installed v2 neutral's visible 291 px height and foot baseline,
// not only its 384x416 canvas. Keep the new pose's proportions intact.
const rig={scale:291/345,offsetX:W*(1-291/345)/2,offsetY:393-396*(291/345)};

async function extract(file, names) {
  const {data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const {width:w,height:h}=info;
  const mask=new Uint8Array(w*h);
  for(let i=0;i<w*h;i++) {
    const o=i*4,r=data[o],g=data[o+1],b=data[o+2];
    const key=g>115 && g>r*1.35 && g>b*1.32 && g-Math.max(r,b)>45;
    if(key) data.fill(0,o,o+4);
    else { mask[i]=data[o+3]>28?1:0; if(g>Math.max(r,b)+12) data[o+1]=Math.max(r,b); }
  }
  // Full-resolution connected components avoid slicing wings at nominal cell edges.
  const queue=new Int32Array(w*h), found=[];
  for(let n=0;n<mask.length;n++) {
    if(mask[n]!==1)continue;
    let head=0,tail=1;queue[0]=n;mask[n]=2;
    let minX=w,minY=h,maxX=0,maxY=0;
    while(head<tail) {
      const i=queue[head++],x=i%w,y=Math.floor(i/w);
      minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
      for(const j of [x?i-1:-1,x<w-1?i+1:-1,y?i-w:-1,y<h-1?i+w:-1]) {
        if(j>=0&&mask[j]===1){mask[j]=2;queue[tail++]=j;}
      }
    }
    if(tail>1200)found.push({x:minX,y:minY,w:maxX-minX+1,h:maxY-minY+1,area:tail});
  }
  if(found.length!==names.length)throw Error(`${file}: ${found.length} components, expected ${names.length}`);
  found.sort((a,b)=>a.y-b.y);
  const cols=3;
  const ordered=[];
  for(let i=0;i<found.length;i+=cols)ordered.push(...found.slice(i,i+cols).sort((a,b)=>a.x-b.x));
  // One scale for the entire coherent source, including compressed flight poses.
  const scale=Math.min(...ordered.map(b=>Math.min((W-36)/b.w,(H-42)/b.h)));
  const outputs=[];
  for(let i=0;i<names.length;i++) {
    const b=ordered[i];
    // Source flight frames are foreshortened AND drawn smaller. Register by
    // observed head scale, not equal whole-body height (which stretches flight).
    const adjustment=names[i].includes('-right') && ['takeoff','cruise','land'].some(n=>names[i].startsWith(n)) ? 1.17 :
      names[i].startsWith('gaze-') ? 1.035 : 1;
    const poseScale=Math.min(scale*adjustment,(W-24)/b.w,(H-36)/b.h);
    const cw=Math.round(b.w*poseScale*rig.scale),ch=Math.round(b.h*poseScale*rig.scale);
    const pose=await sharp(data,{raw:{width:w,height:h,channels:4}}).extract({left:b.x,top:b.y,width:b.w,height:b.h})
      .resize(cw,ch,{kernel:'nearest'}).png().toBuffer();
    const left=Math.round((W-cw)/2),top=H-23-ch;
    const out=path.join(root,`${names[i]}.png`);
    await sharp({create:{width:W,height:H,channels:4,background:'#00000000'}}).composite([{input:pose,left,top}]).withIccProfile('srgb').png().toFile(out);
    outputs.push({name:names[i],source:b,destination:{x:left,y:top,w:cw,h:ch},scale:poseScale});
  }
  return outputs;
}

async function main(){
  const foundation=['neutral','smile','blink','gaze-left','gaze-front','gaze-right','takeoff-right','cruise-right','land-right'];
  let registration=await extract(path.join(root,'sources/foundation-green.png'),foundation);
  for(const n of ['takeoff','cruise','land'])await sharp(path.join(root,`${n}-right.png`)).flop().withIccProfile('srgb').png().toFile(path.join(root,`${n}-left.png`));
  const neutral=await sharp(path.join(root,'neutral.png')).ensureAlpha().raw().toBuffer();
  const parts={body:Buffer.from(neutral),wingLeft:Buffer.alloc(neutral.length),wingRight:Buffer.alloc(neutral.length),hairLeft:Buffer.alloc(neutral.length),hairRight:Buffer.alloc(neutral.length)};
  // Rotating perfectly abutting, hard-alpha rectangles exposes their straight
  // crop boundaries for a frame or two. Retain eight canonical source pixels
  // beneath every moving cut edge. The overlapping RGBA is byte-identical at
  // rest and provides a hidden underlap at the 0.7-1.0 degree sway extrema.
  const seamOverlap=8/rig.scale;
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){
    const rx=(x-rig.offsetX)/rig.scale,ry=(y-rig.offsetY)/rig.scale;
    let part=null,nearSeam=false;
    if(ry>=282&&ry<367&&rx<124){
      part='wingLeft';nearSeam=124-rx<=seamOverlap||Math.min(ry-282,367-ry)<=seamOverlap;
    } else if(ry>=282&&ry<367&&rx>=260){
      part='wingRight';nearSeam=rx-260<=seamOverlap||Math.min(ry-282,367-ry)<=seamOverlap;
    } else if(ry>=242&&ry<282&&rx>=95&&rx<141){
      part='hairLeft';nearSeam=Math.min(rx-95,141-rx,ry-242,282-ry)<=seamOverlap;
    } else if(ry>=242&&ry<282&&rx>=243&&rx<289){
      part='hairRight';nearSeam=Math.min(rx-243,289-rx,ry-242,282-ry)<=seamOverlap;
    }
    if(part){
      const i=(y*W+x)*4;
      neutral.copy(parts[part],i,i,i+4);
      if(!nearSeam)parts.body.fill(0,i,i+4);
    }
  }
  for(const [name,raw]of Object.entries(parts))await sharp(raw,{raw:{width:W,height:H,channels:4}}).withIccProfile('srgb').png().toFile(path.join(root,`neutral-${name}.png`));
  const clip=(frames,durations,loop=true,interruptAfter=0)=>({frames,durations,loop,anchor:[0.5,0.95],interruptAfter});
  const clips={
    idle:clip(['neutral'],[6]),
    lookLeft:clip(['gaze-front','gaze-left'],[.12,1.2]),
    lookRight:clip(['gaze-front','gaze-right'],[.12,1.2]),
    flyRight:clip(['takeoff-right','cruise-right','land-right'],[.6,2.4,.8],false,.2),
    flyLeft:clip(['takeoff-left','cruise-left','land-left'],[.6,2.4,.8],false,.2)
  };
  const actions=path.join(root,'sources/actions-green.png');
  if(fs.existsSync(actions)){
    const names=['wave','shy','tilt','adjustVisor','nap','sway','peek','working','waiting','failed','celebrate','focused'];
    registration.push(...await extract(actions,names));
    for(const name of names)clips[name]=clip(['neutral',name,name,'neutral'],[.15,.7,.8,.2],false,.25);
    clips.nap=clip(['nap'],[3.6],false,.2);
    // User preferred a relaxed long-lived companion pose over raised paws.
    // Reuse the approved neutral rig; keep real Codex state separate from art.
    clips.working=clip(['neutral'],[3]);
    clips.waiting=clip(['waiting'],[2]);
    clips.failed=clip(['failed','focused'],[.5,1.5]);
    clips.celebrate=clip(['celebrate','smile'],[.65,.8]);
  }
  fs.writeFileSync(path.join(root,'motion.json'),JSON.stringify({version:1,width:W,height:H,rig,clips},null,2));
  fs.writeFileSync(path.join(root,'qa/registration.json'),JSON.stringify(registration,null,2));
  // Normal-size review sheet on alternating dark/light backgrounds.
  const tiles=[];
  for(let i=0;i<registration.length;i++){
    const bg=i%2?'#edf3f8':'#182330';
    const previewName=registration[i].name==='working' ? clips.working.frames[0] : registration[i].name;
    const tile=await sharp({create:{width:192,height:208,channels:4,background:bg}})
      .composite([{input:await sharp(path.join(root,previewName+'.png')).resize(192,208,{kernel:'nearest'}).png().toBuffer()}]).png().toBuffer();
    tiles.push({input:tile,left:(i%3)*192,top:Math.floor(i/3)*208});
  }
  await sharp({create:{width:576,height:Math.ceil(registration.length/3)*208,channels:4,background:'#182330'}}).composite(tiles).png().toFile(path.join(root,'qa/contact-sheet.png'));
  console.log(`Extracted ${registration.length} registered poses; ${Object.keys(clips).length} clips`);
}
main().catch(e=>{console.error(e);process.exit(1);});
