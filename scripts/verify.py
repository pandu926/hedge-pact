"""Re-read public receipts and verify amounts, sequences, callbacks and token movements."""
from chain import *
m=json.loads((ROOT/'deployments/manifest.json').read_text());p=json.loads((ROOT/'evidence/public-run.json').read_text());v=m['demo']['vault'];c=m['lasna']['Coordinator'];id=bytes.fromhex(m['demo']['id'][2:]);source=p['sourceReceipt'];adl=source['transactionHash']
assert int(source['status'],16)==1
obstopic='0x'+keccak(text='ObservationPublished(bytes32,uint64,bytes)').hex()
observations=[]
for l in source['logs']:
 if l['address'].lower()==m['base']['SourceFactory'].lower() and l['topics'][0]==obstopic:
  raw=decode(['bytes'],bytes.fromhex(l['data'][2:]))[0];obs=decode(['(bytes32,uint64,uint64,uint64,uint256,uint256,uint256,uint64,bool)'],raw)[0];assert obs[0]==id and obs[4]==60*10**18;observations.append(obs)
assert len(observations)>=2,'native callback plus post-execution snapshot required'
settledTopic='0x'+keccak(text='Settled(bytes32,uint64,uint256,uint256,uint256,uint256,uint8,bool)').hex()
asset=read('unichain',v,'asset()',out=['address'])[0];stable=read('unichain',v,'stable()',out=['address'])[0];pool=read('unichain',v,'pool()',out=['address'])[0];transfer='0x'+keccak(text='Transfer(address,address,uint256)').hex();sold=received=0;settlements=[]
for l in p['spotLogs']:
 if l['topics'][0]!=settledTopic:continue
 q,out,spot,target,mode,retry=decode(['uint256','uint256','uint256','uint256','uint8','bool'],bytes.fromhex(l['data'][2:]));
 if q==0:continue
 assert q<=25*10**18 and target==60*10**18
 r=rpc('unichain','eth_getTransactionReceipt',[l['transactionHash']]);tx=rpc('unichain','eth_getTransactionByHash',[l['transactionHash']]);assert int(r['status'],16)==1
 assert tx['to'].lower() in [v.lower(),'0x775c9b990ade401060b78d0e98684eef8d2466c1']
 moves=[x for x in r['logs'] if x['topics'][0]==transfer]
 assert any(x['address'].lower()==asset.lower() and int(x['topics'][1],16)==int(v,16) and int(x['topics'][2],16)==int(pool,16) and int(x['data'],16)==q for x in moves)
 assert any(x['address'].lower()==stable.lower() and int(x['topics'][1],16)==int(pool,16) and int(x['topics'][2],16)==int(v,16) and int(x['data'],16)==out for x in moves)
 sold+=q;received+=out;settlements.append({'hash':l['transactionHash'],'soldWei':q,'receivedUnits':out,'actualSpotWei':spot,'sequence':int(l['topics'][2],16),'nativeFrom':tx['from'],'nativeTo':tx['to']})
assert sold==40*10**18 and received==99660227478
ackTopic='0x'+keccak(text='ReceiptAccepted(bytes32,uint64,uint256,uint256,bool)').hex();decisionTopic='0x'+keccak(text='DecisionRequested(bytes32,uint64,address,uint256,uint256)').hex();acks=[];decisions=[]
for l in p['reactiveLogs']:
 if len(l['topics'])<2 or bytes.fromhex(l['topics'][1][2:])!=id:continue
 if l['topics'][0]==decisionTopic:
  vault,target,sourceHash=decode(['address','uint256','uint256'],bytes.fromhex(l['data'][2:]));
  if sourceHash==int(adl,16):assert target==60*10**18 and vault.lower()==v.lower();decisions.append(l['transactionHash'])
 if l['topics'][0]==ackTopic and decode(['uint256','uint256','bool'],bytes.fromhex(l['data'][2:]))==(60*10**18,60*10**18,False):acks.append(l['transactionHash'])
assert decisions and acks
report={'status':'PASS','environment':'PUBLIC_TESTNET','sourceNativeAdl':adl,'nativeObservationCount':len(observations),'reactiveDecisions':list(dict.fromkeys(decisions)),'spotSettlements':settlements,'finalAcknowledgements':acks,'spotSoldWei':sold,'syntheticUsdReceivedUnits':received,'sourceChain':84532,'destinationChain':1301,'coordinatorChain':5318007,'latencyAdvantageClaimed':False,'historicalLossAvoidedClaimed':False};save(ROOT/'evidence/verified-hops.json',report)
# Verify runtime deployment sizes and record hashes; immutables are preserved on-chain.
codes={}
for net in NETS:
 for name,address in m[net].items():
  if name=='block':continue
  code=bytes.fromhex(rpc(net,'eth_getCode',[address,'latest'])[2:]);assert code and len(code)<=24576;codes[net+':'+name]={'address':address,'runtimeBytes':len(code),'keccak':'0x'+keccak(code).hex()}
save(ROOT/'evidence/code-hashes.json',codes)
print(json.dumps(report,indent=2))
