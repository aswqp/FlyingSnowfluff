// Standard macOS icon sizes derived from the approved character, no new art.
const sharp=require('sharp');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const output=path.join(root,'Resources/App/AppIcon.iconset');
fs.mkdirSync(output,{recursive:true});
(async()=>{
  const cropped=await sharp(path.join(root,'Resources/v3/neutral.png')).trim().png().toBuffer();
  for(const size of [16,32,128,256,512])for(const scale of [1,2]){
    const dim=size*scale;
    await sharp(cropped).resize(dim,dim,{fit:'contain',background:'#00000000',kernel:'nearest'})
      .withIccProfile('srgb').png().toFile(path.join(output,`icon_${size}x${size}${scale===2?'@2x':''}.png`));
  }
  console.log(output);
})().catch(e=>{console.error(e);process.exit(1)});
