#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise public checkpoint integrity without claiming private proof replay."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/trust12'))
spec = importlib.util.spec_from_file_location('full_source_admission_controls', ROOT / 'scripts/trust12/verify_full_source_admission_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.saved.read_json(ROOT / v.CHECKPOINT)
v.public_contract(checkpoint, ROOT)
controls = []


def rejected(name, mutate):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    try:
        v.public_contract(candidate, ROOT)
    except (RuntimeError, ValueError, KeyError, TypeError):
        controls.append(name)
        return
    raise AssertionError('public checkpoint mutation accepted: ' + name)


for claim in v.NONCLAIMS:
    rejected('false-promotion-' + claim, lambda c, key=claim: c['claims'].__setitem__(key, True))
for claim in v.CONFIRMED:
    rejected('removed-confirmation-' + claim, lambda c, key=claim: c['confirmed'].__setitem__(key, False))
rejected('source-domain-narrowing', lambda c: c['coverage'].__setitem__('sourceVariables', 2))
rejected('deleted-kernel-stage', lambda c: c['kernelStages'].pop())
rejected('deleted-required-root', lambda c: c['kernelStages'][-1]['roots'].pop())
rejected('changed-source-artifact', lambda c: c['artifacts'][0].__setitem__('sha256', '0' * 64))
rejected('changed-native-ceiling', lambda c: c['nativeQueries'][1].__setitem__('ceilingResult', 'Top'))
rejected('assumed-definedness', lambda c: c['nativeQueries'][0].__setitem__('assumeDefined', True))
rejected('failed-attempt-credit', lambda c: c['repairProvenance'].__setitem__('failedKernelCreditInherited', True))
rejected('changed-verifier-reference', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
print(v.json.dumps({'status': 'PASS_PUBLIC_CAPTURED_SOURCE_CONTROLS', 'positive': 1,
                    'negativeControls': len(controls), 'savedArtifactsVerified': False,
                    'freshKernelReplay': False}, indent=2))
