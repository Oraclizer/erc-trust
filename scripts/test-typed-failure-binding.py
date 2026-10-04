#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public typed failure binding record boundary without reading the private run records."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('typed_failure_record_tests',
                                              ROOT / 'scripts/trust12/verify_typed_failure_binding_v1.py')
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
    raise AssertionError('typed failure record mutation accepted: ' + name)


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


def row(candidate, profile, index):
    return next(item for item in candidate['probe']['rows'] if item['profile'] == profile and item['index'] == index)


def mutant(candidate, identifier):
    return next(item for item in candidate['mutants'] if item['id'] == identifier)


def flip_word(data, word, byte=31):
    raw = bytearray(bytes.fromhex(data.removeprefix('0x')))
    raw[4 + 32 * word + byte] ^= 1
    return '0x' + raw.hex()


def runtime(candidate, name):
    return candidate['loads']['runtimes'][name]


for key in v.NONCLAIM_KEYS:
    semantic('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    semantic('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
semantic('changed-schema', lambda c: c.__setitem__('schema', 'trust12-typed-failure-binding-checkpoint-v2'))
semantic('changed-status', lambda c: c.__setitem__('status', 'PASS_REGISTERED_CENTRAL_CLOSURE'))
semantic('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('52 typed failure cases', '53 typed failure cases')))
semantic('dropped-site-limit', lambda c: c.__setitem__('layoutBoundary', c['layoutBoundary'].split(' The probe executes')[0]))
semantic('dropped-unbound-words', lambda c: c.__setitem__(
    'layoutBoundary', c['layoutBoundary'].replace(', and the third word of an operational failure is not bound', '')))
semantic('changed-negative-boundary', lambda c: c.__setitem__('negativeBoundary', 'All mutants detected.'))
semantic('widened-load-claim', lambda c: c.__setitem__('loadBoundary', c['loadBoundary'].replace(', not on which path', '')))
semantic('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', 'Full replay.'))
semantic('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
semantic('cases-inflated', lambda c: c['coverage']['cases'].__setitem__('Hook', 16))
semantic('bound-inflated', lambda c: c['coverage'].__setitem__('boundCases', 53))
semantic('controls-inflated', lambda c: c['coverage'].__setitem__('sensitivityControlsDetected',
                                                                 c['coverage']['sensitivityControlsDetected'] + 1))
semantic('loads-inflated', lambda c: c['coverage']['endpointLoads']['Native'].__setitem__('TrustTerminal', 2))
semantic('probe-status', lambda c: c['probe'].__setitem__('status', 'PROBE_BINDING_FAILED'))
semantic('probe-suite-failed', lambda c: c['probe']['suites'].__setitem__(
    'HookTypedFailureProbe.testHookTypedFailureProbe()', 'Failure'))
semantic('probe-code-identity', lambda c: c['probe']['codeIdentity']['Partial'].__setitem__('matches', False))
semantic('row-removed', lambda c: c['probe']['rows'].pop())
semantic('row-duplicated', lambda c: c['probe']['rows'].__setitem__(1, deepcopy(c['probe']['rows'][0])))
semantic('row-index-moved', lambda c: row(c, 'Hook', 101).__setitem__('index', 116))
semantic('row-expected-changed', lambda c: row(c, 'Native', 104).__setitem__('expected', 'TrustOperationalFailure'))
semantic('row-entrypoint-changed', lambda c: row(c, 'Native', 204).__setitem__('entrypoint', 1))
semantic('row-verdict-changed', lambda c: row(c, 'Partial', 109).__setitem__('verdict', 'NOT_BOUND'))
semantic('row-command-word-flipped', lambda c: row(c, 'Partial', 101).__setitem__(
    'returnData', flip_word(row(c, 'Partial', 101)['returnData'], 0)))
semantic('row-authority-word-flipped', lambda c: row(c, 'Hook', 110).__setitem__(
    'returnData', flip_word(row(c, 'Hook', 110)['returnData'], 1)))
semantic('row-reason-unregistered', lambda c: row(c, 'Native', 104).__setitem__(
    'returnData', row(c, 'Native', 104)['returnData'][:-4] + 'ffff'))
semantic('row-extended', lambda c: row(c, 'Hook', 114).__setitem__('returnData', row(c, 'Hook', 114)['returnData'] + '00'))
semantic('row-sender-changed', lambda c: row(c, 'Native', 209).__setitem__('sender', '0x' + '0' * 39 + '1'))
semantic('row-control-hidden', lambda c: row(c, 'Native', 105)['controls'].__setitem__('unregisteredReason', False))
semantic('control-failed', lambda c: row(c, 'Native', 103).__setitem__('ok', False))
semantic('mutant-survived', lambda c: mutant(c, 'NATIVE-OPERATIONAL-SELECTOR').__setitem__('status', 'MUTANT_SURVIVED'))
semantic('mutant-case-bound', lambda c: mutant(c, 'HOOK-TERMINAL-CASE-WORD')['cases'].__setitem__('114', 'BOUND'))
semantic('mutant-case-dropped', lambda c: mutant(c, 'HOOK-UNAUTHORIZED-AUTHORITY-WORD')['cases'].pop('110'))
semantic('mutant-missing-case', lambda c: mutant(c, 'PARTIAL-INVALID-COMMAND-ID-WORD').__setitem__('missingCases', [101]))
semantic('mutant-removed', lambda c: c['mutants'].pop())
semantic('mutants-reordered', lambda c: c['mutants'].reverse())
semantic('mutation-stale-source', lambda c: mutant(c, 'NATIVE-OPERATIONAL-SELECTOR')['mutation'].__setitem__(
    'beforeSha256', '0' * 64))
semantic('mutation-other-change', lambda c: mutant(c, 'HOOK-TERMINAL-CASE-WORD')['mutation'].__setitem__(
    'afterSha256', mutant(c, 'HOOK-UNAUTHORIZED-AUTHORITY-WORD')['mutation']['afterSha256']))
semantic('mutation-other-file', lambda c: mutant(c, 'PARTIAL-INVALID-COMMAND-ID-WORD')['mutation'].__setitem__(
    'file', 'implementation/src/TrustToken.sol'))
semantic('repin-removed', lambda c: mutant(c, 'HOOK-TERMINAL-CASE-WORD')['mutation'].pop('repin'))
semantic('repin-added', lambda c: mutant(c, 'NATIVE-OPERATIONAL-SELECTOR')['mutation'].__setitem__(
    'repin', deepcopy(mutant(c, 'HOOK-TERMINAL-CASE-WORD')['mutation']['repin'])))
semantic('repin-stale-pin', lambda c: mutant(c, 'HOOK-UNAUTHORIZED-AUTHORITY-WORD')['mutation']['repin'].__setitem__(
    'beforePin', '0x' + '0' * 64))
semantic('repin-unchanged-pin', lambda c: mutant(c, 'HOOK-UNAUTHORIZED-AUTHORITY-WORD')['mutation']['repin'].__setitem__(
    'afterPin', mutant(c, 'HOOK-UNAUTHORIZED-AUTHORITY-WORD')['mutation']['repin']['beforePin']))
semantic('load-offset-dropped', lambda c: runtime(c, 'TrustToken')['typedFailureSelectorLoads']['TrustReplay']['push4'].pop())
semantic('load-count-changed', lambda c: runtime(c, 'ERC3643HookAdapter')['loadCounts'].__setitem__('TrustTerminal', 9))
semantic('runtime-hash-changed', lambda c: runtime(c, 'ERC3643HookFactory').__setitem__('runtimeSha256', '0' * 64))
semantic('scanned-artifact-changed', lambda c: runtime(c, 'ProfileGovernor').__setitem__('artifactSha256', 'a' * 64))
semantic('load-criterion-failed', lambda c: c['loads']['criteria'].__setitem__('recorded-loads-equal-the-recomputed-loads', 'FAIL'))
semantic('endpoint-load-missing', lambda c: c['loads']['endpointLoads']['Hook'].__setitem__('TrustReplay', 0))
semantic('optimizer-runs-changed', lambda c: c['loads']['build']['settings']['optimizer'].__setitem__('runs', 200))
semantic('compiler-changed', lambda c: c['loads']['build'].__setitem__('compiler', '0.8.30+commit.73712a01'))
for key in sorted(v.IDENTITY_PATHS):
    semantic('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64))
semantic('removed-artifact', lambda c: c['artifacts'].pop())
semantic('reordered-artifacts', lambda c: c['artifacts'].reverse())
semantic('changed-artifact-kind', lambda c: c['artifacts'][0].__setitem__('kind', 'forge-report'))
semantic('empty-artifact', lambda c: c['artifacts'][0].__setitem__('bytes', 0))
semantic('invalid-artifact-hash', lambda c: c['artifacts'][1].__setitem__('sha256', 'not-a-hash'))
semantic('extra-artifact-key', lambda c: c['artifacts'][1].__setitem__('path', 'receipt.json'))
semantic('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
semantic('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
semantic('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'true'))
rejected('reviewed-digest-pin', lambda c: row(c, 'Native', 101).__setitem__('reason', 4))
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('loadBoundary', c['loadBoundary'] + ' G' + '7'), privacy)
rejected('internal-coordinate-suffix', lambda c: c.__setitem__('scope', c['scope'] + ' probe-g' + '66-v1'), privacy)
rejected('linux-path', lambda c: c.__setitem__('scope', c['scope'] + ' /mn' + 't/c'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c.__setitem__('negativeBoundary', c['negativeBoundary'] + ' a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_TYPED_FAILURE_RECORD', 'positive': 1, 'negativeControls': len(controls),
                  'payloadsReread': True, 'foundryRerun': False}, indent=2))
