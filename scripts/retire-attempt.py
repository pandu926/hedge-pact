from chain import *
m=json.loads((ROOT/'deployments/manifest.json').read_text());d=m['demo'];a=wallet();base=Sender('base',a);lasna=Sender('lasna',a);uni=Sender('unichain',a)
r=lasna.invoke('retire-attempt2b',m['lasna']['Coordinator'],'retire()');lasna.invoke('refund-attempt2',m['lasna']['Coordinator'],'withdrawRetired()')
base.invoke('close-attempt2',m['base']['SourceFactory'],'closeShort(bytes32)',['bytes32'],[bytes.fromhex(d['id'][2:])],value=10**13)
base.invoke('execute-close-attempt2',m['base']['SourceFactory'],'execute(bytes32)',['bytes32'],[bytes.fromhex(d['id'][2:])],gas=12000000)
assert read('base',d['source'],'shortTokens()')[0]==0
uni.invoke('retire-vault-attempt2',d['vault'],'emergencyRetire()')
p=ROOT/'evidence/public-run.json';old=json.loads(p.read_text());old['status']='FAILED_REGISTRATION_CLOCK_SKEW';old['note']='Source registration arrived with a source-chain timestamp ahead of Lasna. Added a 60-second registration clock-skew tolerance.';save(ROOT/'evidence/attempt-2.json',old)
save(ROOT/'deployments/attempt-2.json',m)
for n in ['SourceFactory','block']:m['base'].pop(n,None)
m['lasna']={};m['unichain']={};m['demo']={};m['status']='deploying';save(ROOT/'deployments/manifest.json',m)
save(p,{'status':'RUNNING','transactions':[]})
