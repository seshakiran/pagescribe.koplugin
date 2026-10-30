import fs from 'node:fs';import path from 'node:path';import {execFileSync}from'node:child_process';
const root=process.cwd(),repo=path.resolve(root,'..');
for(const p of ['public/fonts','public/ui','public/audio','public/screenshots'])fs.mkdirSync(path.join(root,p),{recursive:true});
for(const w of ['400','600','700'])fs.copyFileSync(`node_modules/@fontsource/inter/files/inter-latin-${w}-normal.woff2`,`public/fonts/inter-latin-${w}-normal.woff2`);
fs.copyFileSync('node_modules/@fontsource/caveat/files/caveat-latin-400-normal.woff2','public/fonts/caveat-latin-400-normal.woff2');
fs.copyFileSync('node_modules/@fontsource/inter/LICENSE','public/fonts/INTER-LICENSE.txt');fs.copyFileSync('node_modules/@fontsource/caveat/LICENSE','public/fonts/CAVEAT-LICENSE.txt');
for(const state of ['pen','marker','read','launcher'])execFileSync('lua',['media-demo/scripts/render-ui.lua','color',state],{cwd:repo});
execFileSync('lua',['media-demo/scripts/render-ui.lua','mono','pen'],{cwd:repo});
if(process.env.AUDIO_REPO)execFileSync('lua',['media-demo/scripts/audio-ui.lua',process.env.AUDIO_REPO],{cwd:repo});
const a=fs.readFileSync('public/fonts/inter-latin-400-normal.woff2').toString('base64'),b=fs.readFileSync('public/fonts/inter-latin-700-normal.woff2').toString('base64');
for(const file of fs.readdirSync('public/ui')){let svg=fs.readFileSync('public/ui/'+file,'utf8');svg=svg.replace(/(<svg[^>]*>)/,`$1<style>@font-face{font-family:Inter;src:url(data:font/woff2;base64,${a});font-weight:400}@font-face{font-family:Inter;src:url(data:font/woff2;base64,${b});font-weight:700}</style>`);fs.writeFileSync('public/ui/'+file,svg);}
console.log('Lua-derived UI assets regenerated.');
