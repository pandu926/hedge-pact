import {chromium} from '@playwright/test';
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:1440,height:960}});await page.goto('http://127.0.0.1:4173',{waitUntil:'networkidle'});await page.waitForTimeout(1200);
await page.screenshot({path:'../video/public/overview.png'});await page.evaluate(()=>scrollTo(0,550));await page.screenshot({path:'../video/public/incident.png'});await page.evaluate(()=>scrollTo(0,0));
for(const [label,file] of [['Your strategy','strategy'],['Activity & proof','proof'],['Scenario lab','lab']]){await page.getByRole('button',{name:label,exact:false}).first().click();await page.waitForTimeout(1800);if(file==='strategy')await page.evaluate(()=>scrollTo(0,300));await page.screenshot({path:`../video/public/${file}.png`,clip:{x:255,y:100,width:1160,height:520}});await page.evaluate(()=>scrollTo(0,0));}
await browser.close();
