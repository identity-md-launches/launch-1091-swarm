#!/usr/bin/env python3
"""Read-only, pinned Ethereum evidence. Python 3, curl and Foundry cast required.
Run from repository root: python3 docs/audit/verify-launch.py
All output is stored under artifacts/. No wallet or credential is used.
"""
from pathlib import Path
import argparse, datetime, json, subprocess

TOKEN = '0xd2aef07b4a807062c1c9f01713def52172548eca'
SWAP = '0x4bc05bda38e6e4a6158b5eeb825208c1f2380360'
HOOK = '0x784ff9a3ac5d88a30bfff6f7f2a270161fbe6000'
MANAGER = '0x000000000004444c5dc75cb358380d2e3de08a90'
DISTRIBUTOR = '0x32c3afc39b0d5f30a94a13272bef548259b509c2'
TX = '0xcdbb09627e10374f92eb9ce9c82dd6805692e7edc5d949d5d816585f25008ebc'

def cast(*args):
    return subprocess.check_output(['cast', *args], text=True).strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rpc', choices=['https://ethereum-rpc.publicnode.com', 'https://eth.drpc.org'], default='https://ethereum-rpc.publicnode.com')
    parser.add_argument('--block', type=int, default=26156668)
    parser.add_argument('--output', default='artifacts/evidence/chain-snapshot.json')
    args = parser.parse_args()
    output = Path(args.output)
    if not output.resolve().is_relative_to(Path('artifacts').resolve()):
        parser.error('output must be inside artifacts/')
    block = hex(args.block)
    requests = []
    labels = []
    def add(label, method, params):
        labels.append(label)
        requests.append(dict(jsonrpc='2.0', id=len(requests)+1, method=method, params=params))
    def call(label, target, signature, *values):
        add(label, 'eth_call', [dict(to=target, data=cast('calldata', signature, *values)), block])
    add('chainId', 'eth_chainId', [])
    add('block', 'eth_getBlockByNumber', [block, False])
    add('deploymentReceipt', 'eth_getTransactionReceipt', [TX])
    for label,addr in [('token',TOKEN),('swap',SWAP),('guard',HOOK),('poolManager',MANAGER),('distributor',DISTRIBUTOR)]:
        add(label+'Code','eth_getCode',[addr, block])
    for signature in ['name()(string)','symbol()(string)','decimals()(uint8)','totalSupply()(uint256)','INITIAL_SUPPLY()(uint256)','totalBurned()(uint256)','factory()(address)','poolManager()(address)','launchNumber()(uint64)','DEAD()(address)']:
        call(signature.split('(')[0],TOKEN,signature)
    call('deadBalance',TOKEN,'balanceOf(address)(uint256)','0x000000000000000000000000000000000000dEaD')
    call('swapToken',SWAP,'token()(address)')
    call('swapManager',SWAP,'manager()(address)')
    call('poolState',SWAP,'poolState(uint24,int24,address)(uint160,int24,uint24,uint24)','12500','60',HOOK)
    add('ownerCall','eth_call',[dict(to=TOKEN,data=cast('calldata','owner()')),block])
    responses=[]
    for start in range(0,len(requests),3):
        process = subprocess.run(['curl','--silent','--show-error','--fail-with-body','--max-time','45',args.rpc,'-H','content-type: application/json','--data-binary','@-'],input=json.dumps(requests[start:start+3]),text=True,capture_output=True)
        if process.returncode:
            output.parent.mkdir(parents=True,exist_ok=True)
            output.write_text(json.dumps({'rpc':args.rpc,'blockNumber':args.block,'error':process.stderr,'response':process.stdout,'failedRequests':requests[start:start+3]},indent=2)+'\n')
            raise RuntimeError('RPC request failed; response saved to '+str(output))
        responses.extend(json.loads(process.stdout))
    by_id={r['id']:r for r in responses}
    result={'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'rpc':args.rpc,'blockNumber':args.block,'blockTag':block,'requests':requests,'responses':responses,'values':{label:by_id[i+1] for i,label in enumerate(labels)}}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n')
    assert result['values']['chainId'].get('result')=='0x1', 'Wrong chain'
    assert result['values']['block'].get('result'), 'Pinned block unavailable'
    for k,v in result['values'].items():
        if k.endswith('Code'):print(k, len(v.get('result','0x'))//2-1,'bytes')
        elif k in ('block','deploymentReceipt'): print(k, {f:v.get('result',{}).get(f) for f in ['hash','timestamp','blockNumber','status']})
        elif k not in ('name','symbol'):print(k, v.get('error',v.get('result')))
    print('Saved',output)

if __name__=='__main__': main()
