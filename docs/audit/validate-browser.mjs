// Foreground production-export browser validation; no wallet transaction is broadcast.
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SWARM_PLAYWRIGHT_MODULE ?? '/opt/imd-tools/playwright-mcp/node_modules/playwright/index.mjs');
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, extname } from 'node:path';
const root=resolve('dist');
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.json':'application/json','.webmanifest':'application/manifest+json','.md':'text/markdown'};
const server=createServer(async(req,res)=>{try{let path=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(!path.startsWith('/preview/')){res.writeHead(404);res.end();return;}if(path.endsWith('/'))path+='index.html';const file=resolve(root,path.slice('/preview/'.length));if(!file.startsWith(root+'/'))throw Error('Path');res.setHeader('content-type',types[extname(file)]??'application/octet-stream');res.end(await readFile(file));}catch{res.writeHead(404);res.end('Not found');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/preview/`;
const browser=await chromium.launch({executablePath:process.env.SWARM_CHROMIUM ?? '/opt/imd-tools/ms-playwright/chromium_headless_shell-1246/chrome-headless-shell-linux64/chrome-headless-shell',headless:true,args:['--no-sandbox']});
await mkdir('artifacts/evidence',{recursive:true});
await mkdir('test/scratch/downloads',{recursive:true});
const results={url,views:[],errors:[],failedRequests:[],checks:[]};
try{
 const context=await browser.newContext({viewport:{width:1440,height:1000},permissions:['clipboard-read','clipboard-write']});
 const page=await context.newPage();
 page.on('pageerror',e=>results.errors.push(e.message));page.on('console',msg=>{if(msg.type()==='error')results.errors.push(msg.text());});
 page.on('requestfailed',req=>results.failedRequests.push({url:req.url(),error:req.failure()?.errorText}));
 await page.goto(url,{waitUntil:'networkidle'});
 await page.waitForFunction(()=>document.querySelector('#data-status').textContent.startsWith('Live on Ethereum'),{},{timeout:30000});
 results.checks.push({name:'Live Ethereum reads and exact runtime-code checks',result:await page.locator('#data-status').textContent()});
 await page.keyboard.press('Tab');
 assert.equal(await page.evaluate(()=>document.activeElement.className),'skip-link');
 await page.screenshot({path:'artifacts/evidence/keyboard-focus.webp',type:'webp',quality:70});
 await page.keyboard.press('Enter');assert.equal(await page.evaluate(()=>document.activeElement.id),'main');
 const tabStops=[];for(let i=0;i<18;i++){await page.keyboard.press('Tab');tabStops.push(await page.evaluate(()=>({tag:document.activeElement.tagName,id:document.activeElement.id,text:document.activeElement.textContent.trim().slice(0,70)})));}
 results.checks.push({name:'Keyboard skip and Tab traversal',result:'Skip link focuses main; native controls and record links reachable',tabStops});
 await page.evaluate(()=>{document.activeElement.blur();scrollTo(0,0)});

 for(const width of [1440,820,576,375,320]){
  await page.setViewportSize({width,height:1000});
  const view=await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll('main *,header *,footer *')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&(r.right>innerWidth+1||r.left< -1)}).map(e=>({tag:e.tagName,id:e.id,class:e.className})),brokenImages:[...document.images].filter(i=>!i.complete||i.naturalWidth===0).map(i=>i.src)}));results.views.push(view);assert.equal(view.scrollWidth,width);assert.deepEqual(view.overflow,[]);assert.deepEqual(view.brokenImages,[]);
  if([1440,375,320].includes(width))await page.screenshot({path:`artifacts/evidence/site-${width}.webp`,fullPage:width===1440,type:'webp',quality:70});
 }
 await page.setViewportSize({width:375,height:1000});
 await page.locator('.section-nav a[href="#launch-report"]').click();
 await page.screenshot({path:'artifacts/evidence/report-mobile.webp',type:'webp',quality:70});
 await page.setViewportSize({width:1440,height:1000});
 await page.locator('.section-nav a[href="#launch-report"]').click();
 await page.screenshot({path:'artifacts/evidence/report-desktop.webp',type:'webp',quality:70});
 results.checks.push({name:'Report navigation',hash:new URL(page.url()).hash});
 await page.locator('#copy-address').click();await page.waitForFunction(()=>document.querySelector('#copy-status').textContent.length>0);
 results.checks.push({name:'Copy address',status:await page.locator('#copy-status').textContent(),clipboard:await page.evaluate(()=>navigator.clipboard.readText())});
 for(const [selector,file] of [['a[download][href="./SWARM_DRAFT_CONTRACT_REPORT.md"]','SWARM_DRAFT_CONTRACT_REPORT.md'],['a[download][href="./swarm.listing-draft.json"]','swarm.listing-draft.json'],['a[download="SWARM-logo-512.png"]','SWARM-logo-512.png']]){
  const pending=page.waitForEvent('download');await page.locator(selector).click();const download=await pending;await download.saveAs('test/scratch/downloads/'+file);
  const expected=file==='SWARM-logo-512.png'?'assets/logo.png':file==='swarm.listing-draft.json'?'docs/audit/swarm.listing-draft.json':file;
  const bytes=await readFile('test/scratch/downloads/'+file);assert.deepEqual(bytes,await readFile(expected));
  results.checks.push({name:'Download '+file,filename:download.suggestedFilename(),failure:await download.failure(),bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
 }
 await page.locator('summary').focus();await page.keyboard.press('Enter');results.checks.push({name:'Keyboard disclosure',open:await page.locator('details').getAttribute('open')!==null});await page.screenshot({path:'artifacts/evidence/disclosure-focus.webp',type:'webp',quality:70});
 await page.locator('#direction').selectOption('sell');results.checks.push({name:'Sell selector',pay:await page.locator('#pay-symbol').textContent(),logo:await page.locator('#pay-icon').isVisible(),contract:await page.locator('#pay-token').getAttribute('data-contract')});
 await page.locator('#direction').selectOption('buy');results.checks.push({name:'Buy selector',receive:await page.locator('#receive-symbol').textContent(),logo:await page.locator('#receive-icon').isVisible()});
 await page.locator('#amount').fill('-1');await page.locator('#review').click();results.checks.push({name:'Invalid amount before wallet request',invalid:await page.locator('#amount').getAttribute('aria-invalid'),error:await page.locator('#amount-error').textContent(),focus:await page.evaluate(()=>document.activeElement.id)});
 await page.locator('#amount').fill('0.01');await page.locator('#review').click();results.checks.push({name:'Missing wallet recovery',status:await page.locator('#swap-status').textContent()});
 await page.emulateMedia({reducedMotion:'reduce'});results.checks.push({name:'Reduced motion',durations:await page.locator('.download-button').evaluate(e=>getComputedStyle(e).transitionDuration)});
 results.contrast=await page.evaluate(()=>{
  const luminance=c=>{const values=c.match(/[\d.]+/g).slice(0,3).map(Number).map(v=>v/255).map(v=>v<=0.04045?v/12.92:((v+0.055)/1.055)**2.4);return values[0]*0.2126+values[1]*0.7152+values[2]*0.0722;};
  return ['.record-card h3','.record-card > p','.record-card dt','.record-card .text-link','.download-button','.draft-label'].map(sel=>{const e=document.querySelector(sel);const fg=getComputedStyle(e).color;let p=e,bg;while(p){bg=getComputedStyle(p).backgroundColor;if(bg!=='rgba(0, 0, 0, 0)')break;p=p.parentElement;}const a=luminance(fg),b=luminance(bg);return {selector:sel,foreground:fg,background:bg,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};});
 });
 // Text enlargement is distinct from browser-native zoom.
 await page.setViewportSize({width:820,height:1000});await page.addStyleTag({content:':root{font-size:200%}'});
 results.checks.push({name:'200% root text enlargement at 820px',width:await page.evaluate(()=>document.documentElement.scrollWidth),overflow:await page.evaluate(()=>[...document.querySelectorAll('main *,header *')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&(r.right>innerWidth+1||r.left< -1)}).map(e=>({tag:e.tagName,id:e.id,class:e.className})))});
 await page.screenshot({path:'artifacts/evidence/text-enlargement.webp',fullPage:true,type:'webp',quality:70});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),820);
 await context.close();
 await runFixtures(browser,url,results);
 assert.deepEqual(results.errors,[]);assert.deepEqual(results.failedRequests,[]);
}finally{await browser.close();await new Promise(r=>server.close(r));await writeFile('artifacts/evidence/browser-review.json',JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify(results,null,2));}

async function runFixtures(browser,url,results){
 const snapshot=JSON.parse(await readFile('docs/audit/evidence/chain-snapshot.json','utf8'));
 const recorded=new Map(snapshot.requests.map((q,i)=>[q.method+JSON.stringify(q.params),snapshot.responses.find(r=>r.id===q.id)]));
 const word=n=>'0x'+BigInt(n).toString(16).padStart(64,'0');
 async function setup(mode='ok'){
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  let currentMode=mode;
  await context.route('https://ethereum-rpc.publicnode.com/**',async route=>{
   const q=route.request().postDataJSON();let result;
   if(currentMode==='offline')return route.fulfill({status:503,body:'Unavailable'});
   if(q.method==='eth_chainId')result=currentMode==='wrong-chain'?'0x2105':'0x1';
   else if(q.method==='eth_blockNumber')result=snapshot.blockTag;
   else if(q.method==='eth_getBalance')result='0xde0b6b3a7640000';
   else if(q.method==='eth_getTransactionReceipt')result={status:currentMode==='reverted'?'0x0':'0x1'};
   else if(q.method==='eth_getCode'&&currentMode==='wrong-code')result='0x1234';
   else if(q.method==='eth_call'&&q.params[0].data.startsWith('0x70a08231'))result=word(10n**24n);
   else if(q.method==='eth_call'&&q.params[0].data.startsWith('0xdd62ed3e'))result=word(0);
   else {
    const r=recorded.get(q.method+JSON.stringify(q.params));
    assert(r,'Unrecognized fixture request '+JSON.stringify(q));result=r.result;
   }
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({jsonrpc:'2.0',id:q.id,result})});
  });
  const page=await context.newPage();
  await page.addInitScript(()=>{
   const account='0x1111111111111111111111111111111111111111'; // Test fixture only.
   const handlers={};
   window.fixture={calls:[],reject:false,chain:'0x1',emit:name=>handlers[name]?.()};
   window.ethereum={on:(name,fn)=>{handlers[name]=fn},request:async({method,params})=>{
    window.fixture.calls.push({method,params});
    if(window.fixture.reject&&(method==='eth_requestAccounts'||method==='eth_sendTransaction'))throw Object.assign(new Error('Rejected'),{code:4001});
    if(method==='eth_requestAccounts'||method==='eth_accounts')return [account];
    if(method==='eth_chainId')return window.fixture.chain;
    if(method==='wallet_switchEthereumChain'){window.fixture.chain='0x1';return null;}
    if(method==='eth_call')return '0x'+(1000n*10n**18n).toString(16).padStart(64,'0');
    if(method==='eth_estimateGas')return '0x30d40';
    if(method==='eth_sendTransaction')return '0x'+'ab'.repeat(32);
    throw new Error('Unrecognized wallet fixture request '+method);
   }};
  });
  await page.goto(url,{waitUntil:'networkidle'});
  return {context,page,setMode:value=>{currentMode=value}};
 }
 const f=await setup();const p=f.page;
 await p.locator('#amount').fill('0.01');await p.locator('#review').click();
 await p.waitForFunction(()=>!document.querySelector('#execute').hidden);
 assert.equal(await p.locator('#quote').textContent(),'1,000 SWARM');
 assert.equal(await p.locator('#minimum').textContent(),'995 SWARM');
 assert.equal(await p.evaluate(()=>window.fixture.calls.filter(x=>x.method==='eth_sendTransaction').length),0);
 results.checks.push({name:'Fixture buy review',result:'1,000 SWARM quote, 995 minimum at 0.5%, no send before confirmation'});
 await p.locator('#slippage').selectOption('100');assert.equal(await p.locator('#execute').isVisible(),false);
 await p.locator('#review').click();await p.waitForFunction(()=>!document.querySelector('#execute').hidden);
 assert.equal(await p.locator('#minimum').textContent(),'990 SWARM');
 await p.evaluate(()=>window.fixture.emit('accountsChanged'));assert.equal(await p.locator('#execute').isVisible(),false);
 results.checks.push({name:'Fixture slippage/account change',result:'Quote invalidated; minimum recomputed at 1%'});
 await p.locator('#review').click();await p.waitForFunction(()=>!document.querySelector('#execute').hidden);
 await p.clock.install();await p.clock.fastForward(31_001);
 await p.waitForFunction(()=>document.querySelector('#execute').hidden);
 assert.match(await p.locator('#swap-status').textContent(),/expired/);
 results.checks.push({name:'Fixture quote expiry',result:'Invalidated after 31 seconds of virtual time; no real wait'});
 await p.locator('#review').click();await p.waitForFunction(()=>!document.querySelector('#execute').hidden);
 await p.locator('#execute').click();await p.waitForFunction(()=>document.querySelector('#swap-status').textContent.includes('Swap confirmed'));
 let sends=await p.evaluate(()=>window.fixture.calls.filter(x=>x.method==='eth_sendTransaction'));
 assert.equal(sends.length,1);assert.equal(sends[0].params[0].to,'0x4bc05bda38e6e4a6158b5eeb825208c1f2380360');assert.equal(sends[0].params[0].value,'0x2386f26fc10000');
 results.checks.push({name:'Fixture buy confirmation',result:'Correct adapter, 0.01 ETH value, receipt success displayed; mocked provider only'});
 await p.locator('#direction').selectOption('sell');await p.locator('#amount').fill('100');await p.locator('#review').click();await p.waitForFunction(()=>!document.querySelector('#execute').hidden);
 sends=await p.evaluate(()=>window.fixture.calls.filter(x=>x.method==='eth_sendTransaction'));
 const approval=sends[1].params[0];assert.equal(approval.to,'0xd2aef07b4a807062c1c9f01713def52172548eca');assert(approval.data.startsWith('0x095ea7b3'));assert.equal(BigInt('0x'+approval.data.slice(-64)),100n*10n**18n);
 assert.equal(sends.length,2);
 results.checks.push({name:'Fixture sell review',result:'Exact 100 SWARM approval, confirmed receipt, quote ready; no sell sent before confirmation'});
 await p.evaluate(()=>{window.fixture.reject=true});await p.locator('#execute').click();await p.waitForFunction(()=>document.querySelector('#swap-status').textContent.includes('cancelled'));
 assert.equal(await p.locator('#execute').isVisible(),false);
 results.checks.push({name:'Fixture wallet rejection',result:'Cancellation message; stale quote cleared'});
 await f.context.close();
 for(const mode of ['offline','wrong-code','wrong-chain']){
  const f=await setup(mode);await f.page.waitForFunction(()=>!document.querySelector('#retry').hidden);
  assert.equal(await f.page.locator('#review').isDisabled(),true);
  const initial=await f.page.locator('#data-status').textContent();f.setMode('ok');await f.page.locator('#retry').click();
  await f.page.waitForFunction(()=>!document.querySelector('#review').disabled);
  results.checks.push({name:'Fixture '+mode+' and retry',result:'Trading disabled, then recovered',initial});
  await f.context.close();
 }
 const f2=await setup();await f2.page.evaluate(()=>{Object.defineProperty(navigator,'clipboard',{value:{writeText:async()=>{throw new Error('Permission denied')}},configurable:true})});
 await f2.page.locator('#copy-address').click();await f2.page.waitForFunction(()=>document.querySelector('#copy-status').textContent.includes('Select and copy'));
 results.checks.push({name:'Fixture clipboard denied',result:'Manual-copy fallback visible'});await f2.context.close();
}
