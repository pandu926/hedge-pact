"""Run the real testnet vertical slice and save public receipts. No operator hedge quantities."""
import json,time
from chain import *
m=json.loads((ROOT/'deployments/manifest.json').read_text());a=wallet();base=Sender('base',a);uni=Sender('unichain',a);sf=m['base']['SourceFactory'];df=m['unichain']['SpotFactory']
proofPath=ROOT/'evidence/public-run.json';proof=json.loads(proofPath.read_text()) if proofPath.exists() else {'status':'RUNNING','transactions':[]}
def note(net,r,label):
 if not any(x['hash']==r['transactionHash'] for x in proof['transactions']):proof['transactions'].append({'network':net,'hash':r['transactionHash'],'label':label,'block':int(r['blockNumber'],16)})
 save(proofPath,proof)
def call(net,sender,label,to,sig,types=(),args=(),**kw):
 r=sender.invoke("v3-"+label,to,sig,types,args,**kw);note(net,r,label);return r
def waitFor(label,predicate,seconds=55):
 end=time.time()+seconds
 while time.time()<end:
  try:
   v=predicate()
   if v:return v
  except Exception:pass
  time.sleep(1)
 raise TimeoutError(label)
if not m['demo'].get('source'):
 r=call('base',base,'demo-create',sf,'create()');topic='0x'+keccak(text='SourceRegistered(bytes32,address,address,uint64)').hex()
 l=next(x for x in r['logs'] if x['address'].lower()==sf.lower() and x['topics'][0]==topic);id=l['topics'][1];source,expiry=decode(['address','uint64'],bytes.fromhex(l['data'][2:]));nonce=read('base',sf,'nonces(address)',('address',),(a.address,))[0]-1
 m['demo']={'id':id,'source':source,'expiry':expiry,'nonce':nonce};save(ROOT/'deployments/manifest.json',m)
d=m['demo'];source=d['source'];id=bytes.fromhex(d['id'][2:]);proof['source']=source;proof['id']=d['id'];save(proofPath,proof)
call('base',base,'demo-seed',sf,'seed(bytes32)',('bytes32',),(id,),value=10**13)
call('base',base,'demo-execute-seed',sf,'executeSeed(bytes32)',('bytes32',),(id,),gas=12000000)
call('base',base,'demo-open',sf,'openShort(bytes32)',('bytes32',),(id,),value=10**13)
r=call('base',base,'demo-execute-open',sf,'execute(bytes32)',('bytes32',),(id,),gas=12000000)
q=read('base',source,'shortTokens()',block=r['blockNumber'])[0];assert q==100*10**18,('native short not open',q)
proof['before']='100';save(proofPath,proof)
r=call('unichain',uni,'demo-create-spot',df,'create(uint256,address,uint64)',('uint256','address','uint64'),(d['nonce'],source,d['expiry']),value=10**14)
vault=read('unichain',df,'vaults(bytes32)',('bytes32',),(id,),out=('address',),block=r['blockNumber'])[0];d['vault']=vault;proof['vault']=vault;save(ROOT/'deployments/manifest.json',m)
waitFor('Reactive registration handshake',lambda:read('unichain',vault,'source()',out=('address',))[0].lower()==source.lower())
call('base',base,'demo-arm',sf,'arm(bytes32)',('bytes32',),(id,))
waitFor('first armed observation',lambda:read('unichain',vault,'everArmed()',out=('bool',))[0])
call('unichain',uni,'demo-spot-context',vault,'setReference(uint256)',('uint256',),(2500*10**18,))
r=call('base',base,'demo-native-adl',sf,'adl(bytes32,uint256)',('bytes32','uint256'),(id,200000*10**30),gas=14000000)
assert read('base',source,'shortTokens()',block=r['blockNumber'])[0]==60*10**18
proof['after']='60';save(proofPath,proof)
waitFor('actual spot settles to 60 ETH',lambda:read('unichain',vault,'balances()',out=('uint256','uint256'))[0]==60*10**18)
spot,usd=read('unichain',vault,'balances()',out=('uint256','uint256'));proof['sold']=str((100*10**18-spot)//10**18);proof['received']=str(usd/10**6)
# Gather actual proxy callbacks and coordinator decision/ack logs in bounded pages.
def logs(net,address,start,end):
 result=[]
 for begin in range(start,end+1,500):result+=rpc(net,'eth_getLogs',[{'address':address,'fromBlock':hex(begin),'toBlock':hex(min(begin+499,end))}])
 return result
latest=int(rpc('unichain','eth_blockNumber',[]),16);vlogs=logs('unichain',vault,int(r['blockNumber'],16) if False else m['unichain']['block'],latest)
for l in vlogs:
 h=l['transactionHash']
 if not any(x['hash']==h for x in proof['transactions']):proof['transactions'].append({'network':'unichain','hash':h,'label':'Reactive callback / spot vault event','block':int(l['blockNumber'],16)})
rlatest=int(rpc('lasna','eth_blockNumber',[]),16);rlogs=logs('lasna',m['lasna']['Coordinator'],m['lasna']['block'],rlatest)
ack='0x'+keccak(text='ReceiptAccepted(bytes32,uint64,uint256,uint256,bool)').hex()
waitFor('Reactive acknowledgement',lambda:any(x['topics'][0]==ack and x['topics'][1]==d['id'] and decode(['uint256','uint256','bool'],bytes.fromhex(x['data'][2:]))==(60*10**18,60*10**18,False) for x in logs('lasna',m['lasna']['Coordinator'],m['lasna']['block'],int(rpc('lasna','eth_blockNumber',[]),16))))
rlogs=logs('lasna',m['lasna']['Coordinator'],m['lasna']['block'],int(rpc('lasna','eth_blockNumber',[]),16))
for l in rlogs:
 if len(l['topics'])>1 and l['topics'][1]==d['id'] and not any(x['hash']==l['transactionHash'] for x in proof['transactions']):proof['transactions'].append({'network':'lasna','hash':l['transactionHash'],'label':'Reactive decision / receipt','block':int(l['blockNumber'],16)})
proof.update(status='VERIFIED',note='Actual native GMX short: 100 → 60 ETH. Actual spot: 100 → 60 ETH. Synthetic tokens; authenticated Reactive callbacks and acknowledgement. No latency or profit claim.')
proof['sourceReceipt']=r;proof['spotLogs']=vlogs;proof['reactiveLogs']=rlogs;save(proofPath,proof)
public={k:v for k,v in proof.items() if k not in ['sourceReceipt','spotLogs','reactiveLogs']};save(ROOT/'app/public/proof.json',public);save(ROOT/'app/src/manifest.json',m)
print(json.dumps(public,indent=2))
