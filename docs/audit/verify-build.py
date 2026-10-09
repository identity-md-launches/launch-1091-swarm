#!/usr/bin/env python3
"""After forge build --offline and verify-launch.py, compare local artifacts with pinned evidence.
Canonical ABI hashing here means recursively sorted JSON object keys, preserved array
order, no whitespace, UTF-8, followed by Ethereum keccak256 (cast keccak).
"""
from pathlib import Path
import json, subprocess

def keccak(value):
    return subprocess.check_output(['cast','keccak',value],text=True).strip()

def main():
    snapshot=Path('artifacts/evidence/chain-snapshot.json')
    if not snapshot.exists(): snapshot=Path('docs/audit/evidence/chain-snapshot.json')
    values=json.loads(snapshot.read_text())['values']
    proof={}
    Path('artifacts/evidence').mkdir(parents=True,exist_ok=True)
    Path('docs/abi').mkdir(parents=True,exist_ok=True)
    Path('artifacts/verification').mkdir(parents=True,exist_ok=True)
    pins=[('Swarm','token','256e5c5caeb272a253f1a3b0a1aef5dd46f75db9194f26b92d52605ee3ef00fc','9f34b3913bdf902fcc6c9face93d70b711813af2354fcdad42575c98bbcf94a2'),('SwarmSwap','swap','0a01dd50e61ea61d9e164bb4056b7299b152fa0d6e4cd2816581dc8a4eb109f9','3ecac95e2705bed7bb7318c5aade6bd99509ecd8fbc2b72223dccd3a5289a5b8')]
    for name,key,abi_pin,creation_pin in pins:
        artifact=json.loads(Path(f'out/{name}.sol/{name}.json').read_text())
        sourcify=json.loads(Path(f'docs/audit/evidence/sourcify-{key}.body').read_text())
        abi=artifact['abi']
        ah=keccak(json.dumps(abi,sort_keys=True,separators=(',',':'),ensure_ascii=False))
        creation=keccak(artifact['bytecode']['object'])
        compiled=bytes.fromhex(artifact['deployedBytecode']['object'].removeprefix('0x'))
        chain=bytes.fromhex(values[key+'Code']['result'][2:]); masked=bytearray(chain)
        immutable_values={}
        for ident,refs in artifact['deployedBytecode']['immutableReferences'].items():
            extracted=[]
            for ref in refs:
                start=ref['start'];end=start+ref['length']
                extracted.append('0x'+chain[start:end].hex()); masked[start:end]=bytes(ref['length'])
            assert len(set(extracted))==1, 'inconsistent immutable references'
            immutable_values[ident]=extracted[0]
        expected_immutables = [values[k]['result'] for k in (['factory','poolManager','launchNumber'] if name=='Swarm' else ['swapToken','swapManager'])]
        assert sorted(immutable_values.values())==sorted(expected_immutables), 'runtime immutables do not match getters'
        proof[name]={'abiCanonicalKeccak':ah,'pinnedAbiHash':'0x'+abi_pin,'abiMatches':ah=='0x'+abi_pin,'creationCodeKeccak':creation,'creationCodeMatchesPin':creation=='0x'+creation_pin,'runtimeCodeKeccak':keccak(values[key+'Code']['result']),'runtimeBytes':len(chain),'runtimeMatchesLocalExcludingImmutables':bytes(masked)==compiled,'immutableValues':immutable_values,'immutableValuesMatchGetters':True,'sourcifyMatch':sourcify.get('match')}
        if sourcify.get('match'):
            proof[name].update({'runtimeMatchesSourcify':values[key+'Code']['result'].lower()==sourcify['runtimeBytecode']['onchainBytecode'].lower(),'localAbiOrderMatchesSourcify':abi==sourcify['abi'],'localAbiEntriesMatchSourcify':{json.dumps(x,sort_keys=True) for x in abi}=={json.dumps(x,sort_keys=True) for x in sourcify['abi']},'sourceMatches':{p:Path(p).read_text()==record['content'] for p,record in sourcify['sources'].items() if Path(p).is_file()},'sourcifyCreationMatch':sourcify['creationMatch'],'sourcifyRuntimeMatch':sourcify['runtimeMatch'],'compiler':sourcify['compilation'],'constructorArguments':sourcify['creationBytecode']['transformationValues']['constructorArguments'],'verifiedAt':sourcify['verifiedAt']})
            Path(f'artifacts/verification/{name}.standard-input.json').write_text(json.dumps(sourcify['stdJsonInput'],indent=2)+'\n')
        Path(f'docs/abi/{name}.json').write_text(json.dumps(abi,indent=2)+'\n')
    Path('artifacts/evidence/verification.json').write_text(json.dumps(proof,indent=2)+'\n')
    print(json.dumps(proof,indent=2))
    for row in proof.values():
        assert row['abiMatches'] and row['creationCodeMatchesPin'] and row['runtimeMatchesLocalExcludingImmutables'], 'verification mismatch'

if __name__=='__main__': main()
