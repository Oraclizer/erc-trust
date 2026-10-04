#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public route inventory record boundary without reading the private run records."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('route_inventory_record_tests', ROOT / 'scripts/trust12/verify_route_inventory_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.read_json(ROOT / v.CHECKPOINT_PATH)
v.metadata_only(checkpoint, ROOT)
controls = []


def rejected(name, mutate, check=None):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    try:
        (check or (lambda c: v.public_contract(c, ROOT)))(candidate)
    except (RuntimeError, ValueError, KeyError, TypeError, AttributeError, StopIteration):
        controls.append(name)
        return
    raise AssertionError('route inventory record mutation accepted: ' + name)


def pinned(mutate):
    """Apply a change and pin the digest of the changed record, so that a semantic check must reject it."""
    def apply(candidate):
        mutate(candidate)
        v.EXPECTED_EVIDENCE_DIGEST = v.payload_digest(candidate)
    return apply


def semantic(name, mutate):
    reviewed = v.EXPECTED_EVIDENCE_DIGEST
    try:
        rejected(name, pinned(mutate))
    finally:
        v.EXPECTED_EVIDENCE_DIGEST = reviewed


def route(candidate, runtime, signature):
    return next(item for item in candidate['routes'] if item['runtime'] == runtime and item['signature'] == signature)


def disposition(candidate, name):
    return next(item for item in candidate['dispositions'] if item['route'] == name)


def run_test(candidate, test):
    return next(item for item in candidate['dispositionRun']['tests'] if item['test'] == test)


APPROVE = 'TrustToken.approve(address,uint256)'
HOOK_SEAL = 'ERC3643HookAdapter.activateSeal((address,uint256,bool)[])'
for key in v.NONCLAIM_KEYS:
    semantic('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    semantic('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
semantic('changed-schema', lambda c: c.__setitem__('schema', 'trust12-route-inventory-checkpoint-v2'))
semantic('changed-status', lambda c: c.__setitem__('status', 'PASS_REGISTERED_CENTRAL_CLOSURE'))
semantic('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('108 selectors', '109 selectors')))
semantic('dropped-compiler-assumption', lambda c: c.__setitem__(
    'classBoundary', c['classBoundary'].replace(' (A-COMPILER)', '')))
semantic('dropped-execution-limit', lambda c: c.__setitem__(
    'dispositionBoundary', c['dispositionBoundary'].split(' A test executes one deployment')[0]))
semantic('widened-probe-claim', lambda c: c.__setitem__(
    'unmatchedBoundary', c['unmatchedBoundary'].replace(', not on a probe', ', and on the probe')))
semantic('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', 'Full replay.'))
semantic('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
semantic('removed-inputs', lambda c: c.pop('inputs'))
semantic('selectors-inflated', lambda c: c['coverage'].__setitem__('selectors', 109))
semantic('open-disposition-hidden', lambda c: c['coverage']['dispositionStates'].__setitem__('OUTSIDE_DISPOSITION_OPEN', 1))
semantic('decision-only-hidden', lambda c: c['coverage'].__setitem__('justifiedOnlyByDecision', 0))
semantic('failed-criterion', lambda c: c['criteria'].__setitem__('unknown-selectors-revert-empty-on-every-endpoint', 'FAIL'))
semantic('removed-route', lambda c: c['routes'].pop())
semantic('reordered-routes', lambda c: c['routes'].reverse())
semantic('reclassified-route', lambda c: route(c, 'ERC3643HookFactory', 'deploy(bytes,address,bytes32,address,uint256,address[])')
         .__setitem__('class', 'Route_Governance'))
semantic('domain-widened', lambda c: route(c, 'ERC3643HookAdapter', 'resynchroniseFrozen(address)')
         .__setitem__('disposition', 'IN_RUNTIME_LINK_DOMAIN'))
semantic('class-source-moved', lambda c: route(c, 'ERC3643HookGovernor', 'sealFresh()')
         .__setitem__('classSource', 'formal bridge route table'))
semantic('removed-disposition', lambda c: c['dispositions'].pop())
semantic('justification-swapped', lambda c: disposition(c, APPROVE).__setitem__('justifiedBy', ['NAT-XFER-01']))
semantic('execution-dropped', lambda c: disposition(c, HOOK_SEAL).__setitem__('executedBy', []))
semantic('execution-moved-to-suite', lambda c: disposition(c, HOOK_SEAL)['executedBy'][0].__setitem__(
    'run', 'recorded-foundry-suite'))
semantic('failed-test-recorded', lambda c: run_test(c, 'testHookActivateSealNeverSucceeds()').__setitem__('status', 'Failure'))
semantic('removed-test-recorded', lambda c: c['dispositionRun']['tests'].pop())
semantic('run-status-failed', lambda c: c['dispositionRun'].__setitem__('status', 'ROUTE_DISPOSITION_TESTS_FAILED'))
semantic('other-test-bytes', lambda c: c['dispositionRun']['sources'].__setitem__(
    next(iter(c['dispositionRun']['sources'])), '0' * 64))
semantic('other-implementation-root', lambda c: c['dispositionRun'].__setitem__('implementationRootSha256', '0' * 64))
semantic('probe-row-not-empty', lambda c: c['unmatchedSelectors']['rows'][0]['observed'].__setitem__('returnBytes', 4))
semantic('probe-row-with-log', lambda c: c['unmatchedSelectors']['rows'][1]['observed'].__setitem__('logs', 1))
semantic('probe-row-removed', lambda c: c['unmatchedSelectors']['rows'].pop())
semantic('probe-receipt-status', lambda c: c['unmatchedSelectors'].__setitem__('receiptStatus', 'PROBE_HARNESS_FAILED'))
semantic('probe-root-changed', lambda c: c['unmatchedSelectors'].__setitem__('probeInputsRoot', '0' * 64))
semantic('other-probe-receipt', lambda c: next(item for item in c['artifacts'] if item['id'] == 'malformed-probe-receipt')
         .__setitem__('sha256', '0' * 64))
semantic('changed-input-hash', lambda c: c['inputs'][0].__setitem__('sha256', '0' * 64))
semantic('removed-input', lambda c: c['inputs'].pop())
semantic('removed-artifact', lambda c: c['artifacts'].pop())
semantic('reordered-artifacts', lambda c: c['artifacts'].reverse())
semantic('changed-artifact-kind', lambda c: c['artifacts'][0].__setitem__('kind', 'probe-receipt'))
semantic('empty-artifact', lambda c: c['artifacts'][0].__setitem__('bytes', 0))
semantic('invalid-artifact-hash', lambda c: c['artifacts'][1].__setitem__('sha256', 'not-a-hash'))
semantic('extra-artifact-key', lambda c: c['artifacts'][1].__setitem__('path', 'receipt.json'))
semantic('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
semantic('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
semantic('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'true'))
rejected('reviewed-digest-pin', lambda c: route(c, 'TrustToken', 'approve(address,uint256)').__setitem__('kind', 'EXACT_USE_ROUTE'))
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('classBoundary', c['classBoundary'] + ' G' + '7'), privacy)
rejected('internal-coordinate-suffix', lambda c: c.__setitem__('scope', c['scope'] + ' routes-g' + '66-v1'), privacy)
rejected('linux-path', lambda c: c.__setitem__('scope', c['scope'] + ' /mn' + 't/c'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c.__setitem__('dispositionBoundary', c['dispositionBoundary'] + ' a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_ROUTE_INVENTORY_RECORD', 'positive': 1, 'negativeControls': len(controls),
                  'inventoryRebuilt': True, 'foundryRerun': False}, indent=2))
