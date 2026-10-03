#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public original-binding-meaning boundary without claiming saved replay."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/trust12'))
spec=importlib.util.spec_from_file_location('binding_meaning_tests',ROOT/'scripts/trust12/verify_original_binding_meaning_v1.py')
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
    except (RuntimeError,ValueError,KeyError,TypeError):
        controls.append(name)
        return
    raise AssertionError('original-binding-meaning mutation accepted: '+name)


for key in v.NONCLAIMS:
    rejected('false-promotion-'+key,lambda c,k=key:c['claims'].__setitem__(k,True))
for key in v.CONFIRMED:
    rejected('removed-confirmation-'+key,lambda c,k=key:c['confirmed'].__setitem__(k,False))
rejected('deleted-stage',lambda c:c['kernelStages'].pop())
rejected('duplicate-stage',lambda c:c['kernelStages'].__setitem__(1,deepcopy(c['kernelStages'][0])))
rejected('deleted-root',lambda c:c['kernelStages'][-1]['roots'].pop())
rejected('duplicate-root',lambda c:c['kernelStages'][-1]['roots'].__setitem__(1,c['kernelStages'][-1]['roots'][0]))
rejected('coverage-narrowing',lambda c:c['coverage'].__setitem__('explicitRoots',1))
rejected('changed-parent',lambda c:c['kernelStages'][-1].__setitem__('parent','Unrelated_Parent'))
rejected('changed-guard',lambda c:c['kernelStages'][-1].__setitem__('marker','PASS_UNRELATED'))
rejected('changed-scope',lambda c:c['kernelStages'][-1]['scope'].__setitem__('generalCredit',True))
rejected('removed-hierarchy-receipt',lambda c:c['kernelStages'][-1].__setitem__('hierarchyTransportRequired',False))
rejected('removed-artifact',lambda c:c['artifacts'].pop())
rejected('duplicate-artifact',lambda c:c['artifacts'].__setitem__(1,deepcopy(c['artifacts'][0])))
rejected('changed-source-identity',lambda c:c['artifacts'][0].__setitem__('sha256','0'*64))
rejected('changed-artifact-size',lambda c:c['artifacts'][6].__setitem__('bytes',1))
rejected('changed-verifier',lambda c:c['rehashVerifier'].__setitem__('sha256','0'*64))
rejected('changed-product-model',lambda c:c['productIdentity']['retrieveModel'].__setitem__('sha256','0'*64))
rejected('private-metadata',lambda c:c.__setitem__('scope',c['scope']+' '+chr(67)+':'+chr(47)+'Users'+chr(47)+'private'))
print(v.json.dumps({'status':'PASS_PUBLIC_ORIGINAL_BINDING_MEANING','positive':1,
                    'negativeControls':len(controls),'savedArtifactsVerified':False,
                    'freshKernelReplay':False},indent=2))
