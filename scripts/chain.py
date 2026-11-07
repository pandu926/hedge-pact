"""Testnet-only durable transaction sender. Keys stay in the encrypted operator keystore."""
import json,time,os
from pathlib import Path
import requests
from eth_account import Account
from eth_abi import encode,decode
from eth_utils import keccak,to_checksum_address
ROOT=Path(__file__).resolve().parents[1]
NETS={'base':(84532,'https://base-sepolia-rpc.publicnode.com'),'unichain':(1301,'https://sepolia.unichain.org'),'lasna':(5318007,'https://lasna-rpc.rnk.dev/')}
session=requests.Session()
def save(path,data):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);temp=path.with_suffix('.tmp');temp.write_text(json.dumps(data,indent=2));temp.replace(path)
def rpc(net,method,params):
 for i in range(6):
  try:
   r=session.post(NETS[net][1],json={'jsonrpc':'2.0','id':1,'method':method,'params':params},timeout=15);r.raise_for_status();d=r.json()
   if 'error' in d:raise RuntimeError(str(d['error']))
   return d['result']
  except Exception:
   if i==5:raise
   time.sleep(.4*(i+1))
def calldata(sig,types=(),args=()):return '0x'+(keccak(text=sig)[:4]+encode(types,args)).hex()
def read(net,to,sig,types=(),args=(),out=('uint256',),block='latest'):
 raw=rpc(net,'eth_call',[{'to':to,'data':calldata(sig,types,args)},block]);return decode(out,bytes.fromhex(raw[2:]))
def wallet():
 directory=Path(os.environ.get('HEDGE_PACT_KEYSTORE_DIR','/root/.config/routelock/pilot-wallet'))
 return Account.from_key(Account.decrypt(json.loads((directory/'pilot-deployer').read_text()),(directory/'keystore.password').read_text().strip()))
def artifact(file,name):return json.loads((ROOT/f'contracts/out/{file}.sol/{name}.json').read_text())
class Sender:
 def __init__(self,net,account):
  self.net=net;self.account=account
  observed=[int(rpc(net,'eth_getTransactionCount',[account.address,b]),16) for b in ['pending','latest']]
  for p in (ROOT/'deployments/signed').glob(net+'-*.json'):
   if p.name.endswith('.receipt.json'):continue
   tx=json.loads(p.read_text()).get('transaction',{})
   if tx.get('chainId')==NETS[net][0]:observed.append(tx['nonce']+1)
  self.nonce=max(observed)
 def send(self,label,to=None,data='0x',value=0,gas=None):
  directory=ROOT/'deployments/signed';directory.mkdir(exist_ok=True);directory.chmod(0o700);p=directory/f'{self.net}-{label}.json';rp=directory/f'{self.net}-{label}.receipt.json'
  if p.exists():
   signed=json.loads(p.read_text());tx=signed['transaction'];assert tx.get('to','').lower()==(to or '').lower() and tx['data']==data and tx['value']==value,'intent changed'
   if rp.exists():r=json.loads(rp.read_text());assert int(r['status'],16)==1,(label,r['transactionHash']);return r
  else:
   price=int(rpc(self.net,'eth_gasPrice',[]),16);tx={'chainId':NETS[self.net][0],'nonce':self.nonce,'value':value,'data':data,'maxFeePerGas':price*2,'maxPriorityFeePerGas':min(price//10,10**9)}
   if to:tx['to']=to_checksum_address(to)
   if gas is None:gas=int(rpc(self.net,'eth_estimateGas',[{k:hex(v) if isinstance(v,int) else v for k,v in {**tx,'from':self.account.address}.items()}]),16)*13//10+20000
   tx['gas']=gas;s=self.account.sign_transaction(tx);signed={'hash':'0x'+s.hash.hex(),'raw':'0x'+s.raw_transaction.hex(),'transaction':tx};save(p,signed);p.chmod(0o600);self.nonce+=1
  try:rpc(self.net,'eth_sendRawTransaction',[signed['raw']])
  except Exception:
   if not rpc(self.net,'eth_getTransactionByHash',[signed['hash']]):raise
  end=time.time()+90
  while time.time()<end:
   r=rpc(self.net,'eth_getTransactionReceipt',[signed['hash']])
   if r:
    save(rp,r);assert int(r['status'],16)==1,(label,signed['hash']);print(self.net,label,signed['hash'],flush=True);return r
   time.sleep(.5)
  raise TimeoutError(signed['hash'])
 def invoke(self,label,to,sig,types=(),args=(),**kw):return self.send(label,to,calldata(sig,types,args),**kw)
 def deploy(self,label,file,name,types=(),args=(),**kw):return self.send(label,data=artifact(file,name)['bytecode']['object']+encode(types,args).hex(),**kw)
