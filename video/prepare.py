import asyncio,json,subprocess,re,wave,math,struct
from pathlib import Path
import edge_tts,requests
R=Path(__file__).parent;P=R/'public'
scenes=[
 ('A hedge is a relationship.','Keep both sides of the pact.',"A hedge is a relationship between two positions. If auto deleveraging closes your profitable short, the spot leg on another chain can remain exposed. This is Hedge Pact.",'overview.png'),
 ('Inspired by a real failure class.','Hyperliquid · xyz:SKHYNIX',"The SK Hynix incident on Hyperliquid motivates this failure class. We do not claim to prevent its historical losses. Our implementation uses the full pinned GMX engine in an isolated testnet sandbox.",'incident.png'),
 ('The short is the source of truth.','Native GMX. Actual remaining quantity.',"Each user gets an isolated market and source account on Base Sepolia. Native GMX A D L reduces a one hundred Ether short to sixty. The callback reads the actual remaining position, rather than accepting an operator supplied quantity.",'strategy.png'),
 ('A decision crosses the chain boundary.','Observe → validate → settle → acknowledge.',"Reactive authenticates the observation and sends a guarded decision to Unichain Sepolia. The spot vault sells actual synthetic tokens in bounded chunks. Settlement receipts return the resulting balance and any remaining work.",'proof.png'),
 ('Safety means having more than one answer.','Hold. Retry. Quarantine. Recover.',"An unsafe or stale reference holds trading. A failed swap preserves the actual balance. Retries stop after their budget. Recovery needs three healthy observations over thirty seconds, plus approval for the current incident.",'lab.png'),
 ('Coordination you can inspect.','Keep both sides of the pact.',"We do not claim to beat a fast keeper. Earlier paired testing found the keeper faster in all ninety eight completed pairs. Our thesis is cross chain policy and verifiable settlement. Inspect the public receipts, tests, and source. Keep both sides of the pact.",'proof.png')]
async def main():
 data=[]
 for i,(title,sub,text,img) in enumerate(scenes):
  file=P/f'voice-{i}.mp3'
  if not file.exists():await asyncio.wait_for(edge_tts.Communicate(text,voice='en-US-AndrewNeural',rate='+8%').save(str(file)),timeout=45)
  seconds=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(file)]))+.8
  data.append({'title':title,'sub':sub,'text':text,'image':img,'voice':file.name,'seconds':seconds})
 (R/'src/scenes.json').write_text(json.dumps(data,indent=2))
asyncio.run(main())
css=requests.get('https://fonts.googleapis.com/css2?family=Manrope:wght@500;700&display=swap',headers={'User-Agent':'Mozilla/5.0'},timeout=15).text
urls=re.findall(r'url\((https[^)]+)\)',css)
if urls:(P/'display.woff2').write_bytes(requests.get(urls[-1],timeout=15).content)
# A quiet deterministic pulse and transition click, beneath the narration.
rate=22050
with wave.open(str(P/'hit.wav'),'wb') as f:
 f.setparams((1,2,rate,0,'NONE','not compressed'))
 f.writeframes(b''.join(struct.pack('<h',int(1500*math.sin(2*math.pi*(120-70*n/rate)*n/rate)*math.exp(-n/rate*14))) for n in range(rate//2)))
