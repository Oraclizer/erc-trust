#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public call frame record boundary without reading the private proof graphs or the saved report."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('malformed_call_trace_tests',
                                              ROOT / 'scripts/trust12/verify_malformed_call_trace_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.read_json(ROOT / v.CHECKPOINT_PATH)
v.public_contract(checkpoint, ROOT)
controls = []


def rejected(name, mutate, check=None):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    try:
        (check or (lambda c: v.public_contract(c, ROOT)))(candidate)
    except (RuntimeError, ValueError, KeyError, TypeError, AttributeError):
        controls.append(name)
        return
    raise AssertionError('call frame record mutation accepted: ' + name)


def row(candidate, key):
    return next(item for item in candidate['certificates'] if item['key'] == key)


NATIVE = 'Native/MALFORMED/action-dirty-address'
PARTIAL = 'Partial/MALFORMED/action-nonzero-value'
HOOK = 'Hook/MALFORMED/reversal-enum-out-of-range'

for key in v.NONCLAIM_KEYS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-malformed-call-trace-checkpoint-v2'))
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_MALFORMED_BRANCH_CLOSED'))
rejected('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('enters no call frame', 'makes no call')))
rejected('weakened-graph-boundary', lambda c: c.__setitem__('graphBoundary', c['graphBoundary'].replace(
    ' is part of the assumption A-KEVM-TOOLCHAIN', ' is established')))
rejected('weakened-stage-boundary', lambda c: c.__setitem__('stageBoundary', c['stageBoundary'].replace(
    'still take', 'no longer take')))
rejected('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', c['reproductionBoundary'] + ' x'))
rejected('extra-key', lambda c: c.__setitem__('kernelDerived', True))
rejected('removed-row', lambda c: c['certificates'].pop())
rejected('reordered-rows', lambda c: c['certificates'].reverse())
rejected('duplicate-row', lambda c: c['certificates'].__setitem__(1, deepcopy(c['certificates'][0])))
rejected('foreign-key', lambda c: row(c, NATIVE).__setitem__('key', 'Native/MALFORMED/action-dirty-word'))
rejected('frame-in-segment', lambda c: row(c, NATIVE).__setitem__('framesEnteredInSegment', 1))
rejected('no-witness-frame', lambda c: row(c, HOOK).__setitem__('framesEnteredByEndpointOutsideSegment', 0))
rejected('nonempty-supplied-list', lambda c: row(c, PARTIAL).__setitem__('suppliedCallList', 'SUPPLIED'))
rejected('deeper-endpoint-frame', lambda c: row(c, PARTIAL).__setitem__('endpointCallDepth', 2))
rejected('one-node-segment', lambda c: row(c, NATIVE).__setitem__('segmentNodes', 1))
rejected('boolean-node-count', lambda c: row(c, NATIVE).__setitem__('segmentNodes', True))
rejected('invalid-graph-hash', lambda c: row(c, HOOK).__setitem__('kcfgSha256', 'not-a-hash'))
rejected('shared-graph-hash', lambda c: row(c, HOOK).__setitem__('kcfgSha256', row(c, NATIVE)['kcfgSha256']))
rejected('extra-row-key', lambda c: row(c, NATIVE).__setitem__('calls', []))
rejected('inflated-coverage', lambda c: c['coverage']['segmentNodes'].__setitem__('Native', 97))
rejected('changed-witness-coverage', lambda c: c['coverage']['framesEnteredByEndpointOutsideSegments'].__setitem__(
    'Partial', [7]))
rejected('changed-stage-count', lambda c: c['coverage']['stageExternalCallListsWritten'].__setitem__('Hook', 20))
rejected('changed-stage-source', lambda c: c['stageSources']['Partial'].__setitem__('sha256', '0' * 64))
rejected('changed-stage-role', lambda c: c['stageSources']['Hook'].__setitem__('role', 'hook-value-source'))
for key in v.IDENTITY_PATHS:
    rejected('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64))
rejected('removed-product-identity', lambda c: c['productIdentity'].pop('traceTool'))
rejected('changed-artifact-hash', lambda c: c['artifacts'][0].__setitem__('sha256', 'not-a-hash'))
rejected('changed-artifact-kind', lambda c: c['artifacts'][0].__setitem__('kind', 'registry'))
rejected('removed-artifact', lambda c: c['artifacts'].pop())
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
rejected('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
rejected('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'python3 verify.py'))
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', 'see ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('home-path', lambda c: c.__setitem__('scope', 'see ' + chr(47) + 'ho' + 'me' + chr(47) + 'user'), privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('scope', 'stage G' + '7'), privacy)
rejected('lowercase-step-suffix', lambda c: c.__setitem__('scope', 'stage rl' + '20'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c.__setitem__('scope', 'a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_MALFORMED_CALL_TRACE', 'positive': 1,
                  'negativeControls': len(controls), 'proverRerun': False}, indent=2))
