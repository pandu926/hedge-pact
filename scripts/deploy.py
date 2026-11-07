"""Deploy pinned GMX dependency DAG and Hedge Pact. Every network is a testnet.
Default is preflight. Use --engine or --app only after reviewing the saved preflight.
"""
import json,sys
from chain import *
f=json.loads((ROOT/'gmx/fixture.json').read_text());ds=f['deployments'];reverse={v['address'].lower():k for k,v in ds.items()};needed={}
def leaves(v):
 if isinstance(v,dict):return [x for a in v.values() for x in leaves(a)]
 if isinstance(v,list):return [x for a in v for x in leaves(a)]
 return [v]
def walk(n):
 if n in needed:return
 needed[n]=ds[n]
 for a in leaves(ds[n].get('args',[])+list(ds[n].get('libraries',{}).values())):
  if isinstance(a,str) and a.lower() in reverse:walk(reverse[a.lower()])
for n in ['OrderHandler','AdlHandler','DepositHandler','MarketFactory','Reader']:walk(n)
a=wallet();manifestPath=ROOT/'deployments/manifest.json';m=json.loads(manifestPath.read_text()) if manifestPath.exists() else {'status':'deploying','base':{},'unichain':{},'lasna':{},'demo':{}}
if len(sys.argv)==1:
 gas=sum(int(v['receipt']['gasUsed']) for v in needed.values())
 prices={n:int(rpc(n,'eth_gasPrice',[]),16) for n in NETS};balances={n:int(rpc(n,'eth_getBalance',[a.address,'latest']),16) for n in NETS}
 report={'wallet':a.address,'engineContracts':len(needed),'localConstructorGas':gas,'budgetsWei':{'base':int(.02e18),'unichain':int(.01e18),'lasna':int(3e18)},'balancesWei':balances,'gasPrices':prices,'forecastWei':{'base':gas*prices['base']*4+int(.003e18),'unichain':int(.001e18),'lasna':int(2.9e18)},'runtimeSizesValid':all(len(v['deployedBytecode'][2:])//2<=24576 for v in needed.values())}
 report['PASS']=report['runtimeSizesValid'] and all(report['forecastWei'][n]<=min(balances[n],report['budgetsWei'][n]) for n in NETS);save(ROOT/'evidence/preflight.json',report);print(json.dumps(report,indent=2));sys.exit(0 if report['PASS'] else 1)
assert json.loads((ROOT/'evidence/preflight.json').read_text())['PASS']
sender=Sender('base',a);mapped={ds[n]['address'].lower():v for n,v in m['base'].items() if n in ds};operatorLocal='0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266';mapped[operatorLocal]=a.address
def remap(v):
 if isinstance(v,str):return mapped.get(v.lower(),v)
 if isinstance(v,list):return [remap(x) for x in v]
 if isinstance(v,dict) and v.get('type')=='BigNumber':return int(v['hex'],16)
 if isinstance(v,dict):return [remap(x) for x in v.values()]
 return v
def abiType(x):
 if x["type"].startswith("tuple"):return "("+",".join(abiType(c) for c in x["components"])+")"+x["type"][5:]
 return x["type"]
def deployEngine(n):
 if n in m['base']:return m['base'][n]
 d=needed[n]
 for val in leaves(d.get('args',[])+list(d.get('libraries',{}).values())):
  if isinstance(val,str) and val.lower() in reverse:deployEngine(reverse[val.lower()])
 bytecode=d['bytecode'].lower()
 for old,new in mapped.items():bytecode=bytecode.replace(old[2:],new[2:].lower())
 args=remap(d.get('args',[]));constructor=next((x for x in d['abi'] if x['type']=='constructor'),{'inputs':[]});types=[abiType(x) for x in constructor['inputs']]
 r=sender.send('gmx-'+n,data=bytecode+encode(types,args).hex());m['base'][n]=r['contractAddress'];mapped[d['address'].lower()]=r['contractAddress'];save(manifestPath,m);return r['contractAddress']
if '--engine' in sys.argv:
 for n in list(needed):deployEngine(n)
 if 'WrappedNative' not in m['base']:
  r=sender.deploy('WrappedNative','WrappedNative','WrappedNative');m['base']['WrappedNative']=r['contractAddress'];save(manifestPath,m)
 mapped[ds['WETH']['address'].lower()]=m['base']['WrappedNative']
 controller='0x'+keccak(encode(['string'],['CONTROLLER'])).hex()
 sender.invoke('operator-controller',m['base']['RoleStore'],'grantRole(address,bytes32)',('address','bytes32'),(a.address,bytes.fromhex(controller[2:])))
 for i,g in enumerate(f['globals']):
  if g['name'] in ['NONCE','CHAINLINK_PAYMENT_TOKEN']:continue
  v=g['value'];t=g['type'];v=int(v) if t=='uint256' else remap(v)
  setter={'uint256':'setUint','address':'setAddress','bool':'setBool'}[t]
  sender.invoke('global-'+g['name'],m['base']['DataStore'],f'{setter}(bytes32,{t})',('bytes32',t),(bytes.fromhex(g['key'][2:]),v))
 for i,role in enumerate(f['roles']):
  member=role['member'].lower()
  if member not in mapped:continue
  sender.invoke('role-'+str(i),m['base']['RoleStore'],'grantRole(address,bytes32)',('address','bytes32'),(mapped[member],bytes.fromhex(role['role'][2:])))
 sender.invoke('referral-handler',m['base']['ReferralStorage'],'setHandler(address,bool)',('address','bool'),(m['base']['OrderHandler'],True))
if '--app' in sys.argv:
 assert (ROOT/'evidence/factory-gmx.json').exists(),'Full GMX integration must pass first'
 engine=tuple(m['base'][n] for n in ['DataStore','Reader','OrderHandler','OrderVault','DepositHandler','DepositVault','AdlHandler','MarketFactory','Oracle','WrappedNative','DecreaseOrderExecutor'])
 if 'SourceFactory' not in m['base']:
  r=sender.deploy('app3-SourceFactory','Source','SourceFactory',('('+','.join(['address']*11)+')',),(engine,));m['base']['SourceFactory']=r['contractAddress'];m['base']['block']=int(r['blockNumber'],16);save(manifestPath,m)
 for role in ['CONTROLLER','MARKET_KEEPER','ORDER_KEEPER','ADL_KEEPER','DEPOSIT_KEEPER']:
  sender.invoke('app3-source-role-'+role,m['base']['RoleStore'],'grantRole(address,bytes32)',('address','bytes32'),(m['base']['SourceFactory'],keccak(encode(['string'],[role]))))
 lasna=Sender('lasna',a)
 if 'Coordinator' not in m['lasna']:
  r=lasna.deploy('app3-Coordinator','Coordinator','Coordinator',value=int(2.0e18));m['lasna']={'Coordinator':r['contractAddress'],'block':int(r['blockNumber'],16)};save(manifestPath,m)
 uni=Sender('unichain',a)
 if 'SpotFactory' not in m['unichain']:
  r=uni.deploy('app3-SpotFactory','Spot','SpotFactory',('address','address'),('0x775c9B990ADe401060B78D0e98684eEf8d2466C1',m['lasna']['Coordinator']));m['unichain']={'SpotFactory':r['contractAddress'],'block':int(r['blockNumber'],16)};save(manifestPath,m)
 sender.invoke('app3-set-coordinator',m['base']['SourceFactory'],'setCoordinator(address)',('address',),(m['lasna']['Coordinator'],))
 lasna.invoke('app3-configure',m['lasna']['Coordinator'],'configure(address,address)',('address','address'),(m['base']['SourceFactory'],m['unichain']['SpotFactory']))
 m['status']='deployed';save(manifestPath,m);save(ROOT/'app/src/manifest.json',m)
