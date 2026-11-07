import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
names={'SourceFactory':'Source','SourceAccount':'Source','SandboxPrices':'Source','SpotFactory':'Spot','SpotVault':'Spot','Coordinator':'Coordinator'}
(root/'app/src/abis.json').write_text(json.dumps({name:json.loads((root/f'contracts/out/{file}.sol/{name}.json').read_text())['abi'] for name,file in names.items()},indent=2))
