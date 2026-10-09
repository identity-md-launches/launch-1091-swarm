// Read-only live branding/metadata inspection; never connects a wallet.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const { chromium } = await import(process.env.SWARM_PLAYWRIGHT_MODULE ?? '/opt/imd-tools/playwright-mcp/node_modules/playwright/index.mjs');
const browser=await chromium.launch({executablePath:process.env.SWARM_CHROMIUM ?? '/opt/imd-tools/ms-playwright/chromium_headless_shell-1246/chrome-headless-shell-linux64/chrome-headless-shell',headless:true,args:['--no-sandbox']});
try{
 await mkdir('artifacts/evidence',{recursive:true});
 const page=await browser.newPage({viewport:{width:1366,height:900}});
 const response=await page.goto('https://swarm.sites.imd.fun/',{waitUntil:'networkidle'});
 const headers=await response.allHeaders();
 const evidence={checkedAt:new Date().toISOString(),url:page.url(),httpStatus:response.status(),hostCid:headers['x-ipfs-cid'],title:await page.title()};
 evidence.metadata=await page.evaluate(()=>({canonical:document.querySelector('link[rel="canonical"]')?.getAttribute('href')??null,ogUrl:document.querySelector('meta[property="og:url"]')?.getAttribute('content')??null,ogImage:document.querySelector('meta[property="og:image"]')?.getAttribute('content')??null,headerLogo:document.querySelector('header .brand-logo').getAttribute('src'),manifest:document.querySelector('link[rel="manifest"]').getAttribute('href')}));
 await page.locator('#direction').selectOption('sell');
 evidence.sell={symbol:await page.locator('#pay-symbol').textContent(),logo:await page.locator('#pay-icon').getAttribute('src'),visible:await page.locator('#pay-icon').isVisible()};
 await page.locator('#direction').selectOption('buy');
 evidence.buy={symbol:await page.locator('#receive-symbol').textContent(),logo:await page.locator('#receive-icon').getAttribute('src'),visible:await page.locator('#receive-icon').isVisible()};
 assert.equal(evidence.sell.symbol,'SWARM');assert.equal(evidence.buy.symbol,'SWARM');assert(evidence.sell.visible&&evidence.buy.visible);
 evidence.assets={};
 for(const name of ['logo.svg','logo.png']){
  const r=await page.request.get('https://swarm.sites.imd.fun/assets/'+name);const body=await r.body();const local=await readFile('assets/'+name);
  evidence.assets[name]={httpStatus:r.status(),sha256:createHash('sha256').update(body).digest('hex'),bytes:body.length,equalsLocal:body.equals(local)};assert(body.equals(local));
 }
 evidence.manifest=await (await page.request.get('https://swarm.sites.imd.fun/manifest.webmanifest')).json();
 evidence.tokenList=await (await page.request.get('https://swarm.sites.imd.fun/swarm.tokenlist.json')).json();
 await page.screenshot({path:'artifacts/evidence/live-desktop.webp',type:'webp',quality:70});
 await writeFile('artifacts/evidence/live-browser.json',JSON.stringify(evidence,null,2)+'\n');console.log(JSON.stringify(evidence,null,2));
}finally{await browser.close()}
