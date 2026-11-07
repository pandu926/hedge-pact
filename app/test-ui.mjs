import {chromium} from '@playwright/test';
import fs from 'node:fs';
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,args:['--no-sandbox']});
const results=[];
for(const [name,viewport] of [['desktop',{width:1440,height:1100}],['mobile',{width:390,height:844}]]){
 const page=await browser.newPage({viewport});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:4173',{waitUntil:'networkidle'});await page.screenshot({path:`../evidence/ui-${name}.png`,fullPage:true});
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);if(overflow)throw Error(`${name} horizontal overflow`);
 for(const label of ['Your strategy','Scenario lab','Activity & proof']){if(name==='mobile')await page.getByRole('button',{name:'Open navigation'}).click();await page.getByRole('button',{name:label,exact:false}).first().click();await page.waitForTimeout(200);if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error(`${name} ${label} overflow`);}
 if(errors.length)throw Error(errors.join('\n'));results.push({viewport:name,status:'PASS',runtimeErrors:errors.length});await page.close();
}
fs.writeFileSync('../evidence/browser-tests.json',JSON.stringify(results,null,2));await browser.close();
