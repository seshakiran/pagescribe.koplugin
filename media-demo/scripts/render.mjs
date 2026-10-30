import fs from 'node:fs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {openBrowser,selectComposition,renderStill,renderMedia} from '@remotion/renderer';
const root=process.cwd();
const slugs=['01-write','02-select','03-colors','04-tray','05-dictionary-audio','06-audio-settings','07-together'];
const chrome=process.env.REMOTION_BROWSER_EXECUTABLE||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executable=fs.existsSync(chrome)?chrome:undefined;
const browser=await openBrowser('chrome',{browserExecutable:executable});
try {
 const serveUrl=await bundle({entryPoint:path.join(root,'src/index.tsx'),outDir:path.join(root,'.bundle-stills')});
 fs.mkdirSync(path.join(root,'public/screenshots'),{recursive:true});fs.mkdirSync(path.join(root,'out'),{recursive:true});
 for(let i=0;i<slugs.length;i++){
   const still=await selectComposition({serveUrl,id:'Feature',inputProps:{scene:i},puppeteerInstance:browser});
   await renderStill({serveUrl,composition:still,output:path.join(root,'public/screenshots',`${slugs[i]}.png`),inputProps:{scene:i},imageFormat:'png',puppeteerInstance:browser});
   console.log(`Screenshot ${i+1}/${slugs.length}: ${slugs[i]}`);
 }
 if(!process.env.STILLS_ONLY){
 const videoUrl=await bundle({entryPoint:path.join(root,'src/index.tsx'),outDir:path.join(root,'.bundle')});
 const composition=await selectComposition({serveUrl:videoUrl,id:'Walkthrough',puppeteerInstance:browser});
 let last=-1;
 await renderMedia({serveUrl:videoUrl,composition,codec:'h264',crf:19,pixelFormat:'yuv420p',audioCodec:'aac',audioBitrate:'192k',outputLocation:path.join(root,'out/pagescribe-dictionary-audio-walkthrough.mp4'),puppeteerInstance:browser,concurrency:4,onProgress:({progress})=>{let value=Math.floor(progress*10)*10;if(value!==last){last=value;console.log(`Video ${value}%`);}}});
 console.log('Video rendered.');
 }
}finally{await browser.close({silent:true});}
