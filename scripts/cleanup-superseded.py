from chain import *
m=json.loads((ROOT/'deployments/manifest.json').read_text());a=wallet();s=Sender('base',a)
receipts=[]
for version in [1,2]:
 old=json.loads((ROOT/f'deployments/attempt-{version}.json').read_text())
 for role in ['CONTROLLER','MARKET_KEEPER','ORDER_KEEPER','ADL_KEEPER','DEPOSIT_KEEPER']:
  r=s.invoke(f'revoke-attempt{version}-{role}',m['base']['RoleStore'],'revokeRole(address,bytes32)',['address','bytes32'],[old['base']['SourceFactory'],keccak(encode(['string'],[role]))]);receipts.append({'network':'base','hash':r['transactionHash'],'factory':old['base']['SourceFactory'],'roleRevoked':role})
save(ROOT/'evidence/superseded-role-revocations.json',receipts)
