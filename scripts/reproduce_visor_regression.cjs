// Negative-control fixture: old coordinates against resized art must fail.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../Resources/v3');
const fixture=fs.mkdtempSync('/private/tmp/snowfluff-bad-visor-');
for(const file of fs.readdirSync(root).filter(f=>f.endsWith('.png')))fs.copyFileSync(path.join(root,file),path.join(fixture,file));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'motion.json')));
manifest.rig={scale:1,offsetX:0,offsetY:0};
fs.writeFileSync(path.join(fixture,'motion.json'),JSON.stringify(manifest));
const result=cp.spawnSync('/private/tmp/snowfluff-app-tests/LivelyRenderingHarness',[path.resolve(root,'../App/spritesheet@2x.png')],{env:{...process.env,SNOWFLUFF_MOTION_DIR:fixture},encoding:'utf8'});
if(result.status===0 || !result.stderr.includes('outside the original visor'))throw Error('negative control failed to reproduce forehead overlay: '+result.stdout+result.stderr);
console.log('PASS: old-coordinate negative control reproduces extra forehead visor and is rejected');
console.log('Isolated evidence retained at '+fixture);
