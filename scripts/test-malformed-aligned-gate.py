#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public aligned malformed-gate boundary without claiming saved replay."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/trust12'))
spec = importlib.util.spec_from_file_location('malformed_aligned_gate_tests', ROOT / 'scripts/trust12/verify_malformed_aligned_gate_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.read_json(ROOT / v.CHECKPOINT_PATH)
v.metadata_only(checkpoint, ROOT)
controls = []


def rejected(name, mutate, check=None):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    try:
        (check or (lambda c: v.metadata_only(c, ROOT)))(candidate)
    except (RuntimeError, ValueError, KeyError, TypeError, AttributeError):
        controls.append(name)
        return
    raise AssertionError('aligned malformed-gate mutation accepted: ' + name)


for key in sorted(v.NONCLAIM_KEYS):
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-malformed-aligned-gate-checkpoint-v2'))
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_GENERAL_RUNTIME_LINK'))
rejected('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('Native 16', 'Native 17')))
rejected('changed-control-boundary', lambda c: c.__setitem__('controlBoundary', c['controlBoundary'][:-1]))
rejected('changed-model-boundary', lambda c: c.__setitem__('modelBoundary', 'No assumptions.'))
rejected('aligned-gate-inflation', lambda c: c['coverage']['alignedGateHolds'].__setitem__('hook', 14))
rejected('original-gate-inflation', lambda c: c['coverage']['originalGateHolds'].__setitem__('native', 16))
rejected('typed-impossibility-dropped', lambda c: c['coverage']['originalGateImpossibleTypedOutput'].__setitem__('partial', 0))
rejected('root-count-changed', lambda c: c['coverage']['explicitRoots'].__setitem__('native-aligned', 1))
rejected('run-order-changed', lambda c: c['kernelRuns'].reverse())
rejected('session-removed', lambda c: c['kernelSessions'].pop())
rejected('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
rejected('removed-artifact', lambda c: c['artifacts'].pop())
rejected('duplicate-artifact', lambda c: c['artifacts'].__setitem__(1, deepcopy(c['artifacts'][0])))
rejected('changed-artifact-kind', lambda c: c['artifacts'][0].__setitem__('kind', 'isabelle-source'))
rejected('invalid-artifact-hash', lambda c: c['artifacts'][0].__setitem__('sha256', 'not-a-hash'))
rejected('empty-artifact', lambda c: c['artifacts'][0].__setitem__('bytes', 0))
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
rejected('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'true'))
for key in sorted(v.IDENTITY_PATHS):
    rejected('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64))
rejected('valid-hash-artifact-swap', lambda c: c['artifacts'][0].__setitem__('sha256', 'a' * 64))
rejected('changed-artifact-bytes', lambda c: c['artifacts'][0].__setitem__('bytes', c['artifacts'][0]['bytes'] + 1))
rejected('emptied-run-sessions', lambda c: c['kernelRuns'][0].__setitem__('sessions', []))
rejected('changed-prior-result', lambda c: c['kernelRuns'][0].__setitem__('priorResult', 'hook-prior-build'))
rejected('extra-run-claim', lambda c: c['kernelRuns'][0].__setitem__('generalRuntimeLinkDischarged', True))
rejected('changed-session-roots', lambda c: c['kernelSessions'][0].__setitem__('explicitRoots', 1))
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('modelBoundary', c['modelBoundary'] + ' G' + '7'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('controlBoundary', c['controlBoundary'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c['kernelSessions'][0].__setitem__('note', 'a ' + chr(0x2014) + ' b'), privacy)
print(v.json.dumps({'status': 'PASS_PUBLIC_MALFORMED_ALIGNED_GATE', 'positive': 1,
                    'negativeControls': len(controls), 'savedArtifactsVerified': False,
                    'freshKernelReplay': False}, indent=2))
