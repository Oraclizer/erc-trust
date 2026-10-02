#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise model checkpoint integrity without claiming private proof replay."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/trust12'))
spec=importlib.util.spec_from_file_location('model_source_reception_controls',ROOT/'scripts/trust12/verify_model_source_reception_v1.py')
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
    raise AssertionError('public model checkpoint mutation accepted: '+name)


for claim in v.NONCLAIMS:
    rejected('false-promotion-'+claim,lambda c,key=claim:c['claims'].__setitem__(key,True))
for claim in v.CONFIRMED:
    rejected('removed-confirmation-'+claim,lambda c,key=claim:c['confirmed'].__setitem__(key,False))
rejected('deleted-model-source',lambda c:c['productModels'].pop())
rejected('changed-current-model',lambda c:c['productModels'][0].__setitem__('sha256','0'*64))
rejected('deleted-model-root',lambda c:c['productModels'][0]['explicitRoots'].pop())
rejected('model-domain-narrowing',lambda c:c['coverage'].__setitem__('productTheories',1))
rejected('deleted-kernel-stage',lambda c:c['kernelStages'].pop())
rejected('duplicate-kernel-stage',lambda c:c['kernelStages'].__setitem__(1,deepcopy(c['kernelStages'][0])))
rejected('deleted-required-root',lambda c:c['kernelStages'][-1]['roots'].pop())
rejected('changed-model-root-contract',lambda c:c['kernelStages'][-1]['explicitModelRoots'].pop())
rejected('changed-model-namespace',lambda c:c['kernelStages'][0]['importedSources'][0].__setitem__('logicalName','Wrong.Model'))
rejected('changed-parent-lineage',lambda c:c['kernelStages'][-1].__setitem__('parent','Unrelated_Parent'))
rejected('deleted-source-guard',lambda c:c['kernelStages'][-1]['markers'].pop())
rejected('deleted-model-artifact',lambda c:c['artifacts'].pop())
rejected('duplicate-model-artifact',lambda c:c['artifacts'].__setitem__(1,deepcopy(c['artifacts'][0])))
rejected('changed-saved-source',lambda c:c['artifacts'][0].__setitem__('sha256','0'*64))
rejected('changed-saved-output-size',lambda c:c['artifacts'][6].__setitem__('bytes',1))
rejected('changed-verifier-reference',lambda c:c['rehashVerifier'].__setitem__('sha256','0'*64))
rejected('private-metadata',lambda c:c.__setitem__('scope',c['scope']+' '+('C:'+'/U'+'sers/private/model.thy')))
print(v.json.dumps({'status':'PASS_PUBLIC_MODEL_SOURCE_RECEPTION_CONTROLS','positive':1,
                    'negativeControls':len(controls),'savedArtifactsVerified':False,
                    'freshKernelReplay':False},indent=2))
