#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public Native supply-direction negative boundary without claiming saved replay."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/trust12'))
spec=importlib.util.spec_from_file_location('native_supply_direction_tests',
                                            ROOT/'scripts/trust12/verify_native_supply_direction_negative_v1.py')
v=importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint=v.saved.read_json(ROOT/v.CHECKPOINT)
v.public_contract(checkpoint,ROOT)
controls=[]


def rejected(name,mutate):
    candidate=deepcopy(checkpoint)
    mutate(candidate)
    try:
        v.public_contract(candidate,ROOT)
    except (RuntimeError,ValueError,KeyError,TypeError,AttributeError,IndexError):
        controls.append(name)
        return
    raise AssertionError('native supply-direction mutation accepted: '+name)


def token(candidate,branch,value):
    predicate=candidate['branches'][branch]['branchConstraint']['args'][1]
    index=1 if branch==0 else 0
    predicate['args'][index]['token']=value


for key in v.NONCLAIMS:
    rejected('false-promotion-'+key,lambda c,k=key:c['claims'].__setitem__(k,True))
for key in v.CONFIRMED:
    rejected('removed-confirmation-'+key,lambda c,k=key:c['confirmed'].__setitem__(k,False))
rejected('deleted-above-supply-branch',lambda c:c['branches'].pop())
rejected('deleted-at-most-supply-branch',lambda c:c['branches'].pop(0))
rejected('swapped-branches',lambda c:c['branches'].reverse())
rejected('duplicated-branch',lambda c:c['branches'].__setitem__(0,deepcopy(c['branches'][1])))
rejected('narrowed-predicate',lambda c:c['branches'][1].__setitem__('predicate','SUPPLY + 1 < first'))
rejected('shifted-supply-bound',lambda c:token(c,1,'1000000000000000000000001'))
rejected('weakened-operator',lambda c:c['branches'][1]['branchConstraint']['args'][1]['label'].__setitem__('name','_<=Int_'))
rejected('narrowed-domain',lambda c:c.__setitem__('inputDomain',c['inputDomain']+' and first <= supply'))
rejected('hidden-supply-assumption',lambda c:c.__setitem__('notAssumed',''))
rejected('changed-property',lambda c:c.__setitem__('property','Only the first branch'))
rejected('coverage-narrowing',lambda c:c['coverage'].__setitem__('coversDeclaredScope',False))
rejected('mutant-transaction-promotion',lambda c:c['coverage'].__setitem__('wholeMutantTransactionProved',True))
rejected('changed-guard-target',lambda c:c['guard'].__setitem__('originalDestination',11515))
rejected('changed-source-mutation',lambda c:c['guard']['sourceMutation'].__setitem__('new','true'))
rejected('changed-original-rules',lambda c:c['branches'][1].__setitem__('originalRules',['EVM.jumpi.false','EVM.pc.inc']))
rejected('shortened-join',lambda c:c['branches'][0]['joinRules'].pop())
rejected('changed-removed-pc',lambda c:c['branches'][1].__setitem__('removedPostPc',11739))
rejected('changed-cut-depth',lambda c:c['branches'][1].__setitem__('cutDepth',244))
rejected('surviving-compiled-mutant',lambda c:c['compiledGuardOnlyPair']['mutant'].__setitem__('originalConsumer','Success'))
rejected('changed-visible-floor',lambda c:c['compiledGuardOnlyPair']['mutant'].__setitem__('visibleFrozenFloor','1'))
rejected('unbound-compiled-source',lambda c:c['compiledGuardOnlyPair'].__setitem__('normalSourceIsProductSource',False))
rejected('removed-artifact',lambda c:c['artifacts'].pop())
rejected('duplicate-artifact',lambda c:c['artifacts'].__setitem__(1,deepcopy(c['artifacts'][0])))
rejected('changed-state-identity',lambda c:c['artifacts'][1].__setitem__('sha256','0'*64))
rejected('changed-artifact-size',lambda c:c['artifacts'][2].__setitem__('bytes',-1))
rejected('changed-verifier',lambda c:c['rehashVerifier'].__setitem__('sha256','0'*64))
rejected('changed-product-source',lambda c:c['productIdentity']['nativeSource'].__setitem__('sha256','0'*64))
rejected('private-metadata',lambda c:c.__setitem__('scope',c['scope']+' '+chr(67)+':'+chr(47)+'Users'+chr(47)+'private'))
print(v.json.dumps({'status':'PASS_PUBLIC_NATIVE_SUPPLY_DIRECTION_NEGATIVE','positive':1,
                    'negativeControls':len(controls),'savedArtifactsVerified':False,
                    'freshExecution':False},indent=2))
