#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public certificate registry record boundary without reading the private registry or evidence."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('certificate_registry_record_tests',
                                              ROOT / 'scripts/trust12/verify_certificate_registry_v1.py')
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
    except (RuntimeError, ValueError, KeyError, TypeError, AttributeError):
        controls.append(name)
        return
    raise AssertionError('certificate registry record mutation accepted: ' + name)


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


def row(candidate, key):
    return next(item for item in candidate['certificates'] if item['key'] == key)


def hook(candidate):
    return candidate['runtimeIdentity']['Hook']


for key in v.NONCLAIM_KEYS:
    semantic('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    semantic('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
semantic('changed-schema', lambda c: c.__setitem__('schema', 'trust12-certificate-registry-checkpoint-v2'))
semantic('changed-status', lambda c: c.__setitem__('status', 'PASS_REGISTERED_CENTRAL_CLOSURE'))
semantic('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('Native 16', 'Native 17')))
semantic('dropped-deployment-assumption', lambda c: c.__setitem__(
    'identityBoundary', c['identityBoundary'].replace('the assumption A-DEPLOYMENT', 'closed')))
semantic('dropped-consumer-limit', lambda c: c.__setitem__(
    'consumerBoundary', c['consumerBoundary'].split(' The registry compares')[0]))
semantic('changed-acceptance-boundary', lambda c: c.__setitem__(
    'acceptanceBoundary', c['acceptanceBoundary'].replace('read, not reproved', 'reproved')))
semantic('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', 'Full replay.'))
semantic('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
semantic('removed-runtime-identity', lambda c: c.pop('runtimeIdentity'))
semantic('bound-cells-changed', lambda c: c['coverage'].__setitem__('boundCells', 26))
semantic('code-matches-inflated', lambda c: c['coverage'].__setitem__('executedCodeMatches', 97))
semantic('worlds-inflated', lambda c: c['coverage'].__setitem__('recordedWorlds', 110))
semantic('export-only-hidden', lambda c: c['coverage'].__setitem__('worldsNamedOnlyByKoreExports', 0))
semantic('sessions-changed', lambda c: c['coverage'].__setitem__('kernelSessionsNamingWorlds', 26))
semantic('stored-graph-inflated', lambda c: c['coverage']['acceptanceMethods'].__setitem__('STORED_PROOF_GRAPH', 3))
semantic('incomplete-check', lambda c: c['coverage']['checks'].__setitem__('recorded-worlds-consumed', 'INCOMPLETE'))
semantic('removed-row', lambda c: c['certificates'].pop())
semantic('duplicate-row', lambda c: c['certificates'].__setitem__(1, deepcopy(c['certificates'][0])))
semantic('reordered-rows', lambda c: c['certificates'].reverse())
semantic('uncatalogued-request', lambda c: row(c, 'Native/MALFORMED/empty-calldata').__setitem__(
    'key', 'Native/MALFORMED/uncatalogued-request'))
semantic('changed-form', lambda c: row(c, 'Partial/SEIZE/applied').__setitem__('form', 'COMPOUND_BOUNDARY'))
semantic('graph-acceptance-dropped', lambda c: row(c, 'Native/LIQUIDATE/applied').__setitem__(
    'acceptance', 'RECORDED_FIELDS'))
semantic('graph-acceptance-moved', lambda c: row(c, 'Hook/LIQUIDATE/applied').__setitem__(
    'acceptance', 'STORED_PROOF_GRAPH'))
semantic('no-kernel-consumer', lambda c: row(c, 'Hook/RELEASE/not-applied').__setitem__('kernelStageInputs', 0))
semantic('export-only-moved', lambda c: (row(c, 'Native/FREEZE/not-applied').__setitem__('exportOnlyWorlds', 0),
                                         row(c, 'Native/FREEZE/applied').__setitem__('exportOnlyWorlds', 1)))
semantic('export-only-everywhere', lambda c: row(c, 'Native/FREEZE/not-applied').__setitem__(
    'exportOnlyWorlds', row(c, 'Native/FREEZE/not-applied')['worlds']))
semantic('executed-code-mismatch', lambda c: row(c, 'Hook/SEIZE/applied').__setitem__('executedCode', 'MISMATCH'))
semantic('invalid-code-hash', lambda c: row(c, 'Hook/SEIZE/applied').__setitem__('executedCodeSha256', 'not-a-hash'))
semantic('extra-row-key', lambda c: row(c, 'Hook/SEIZE/applied').__setitem__('proofId', 'p'))
semantic('factory-in-world', lambda c: hook(c)['deploymentOnly']['ERC3643HookFactory'].__setitem__(
    'accountsInRecordedWorlds', 1))
semantic('factory-executed', lambda c: hook(c)['executed'].__setitem__(
    'ERC3643HookFactory', hook(c)['deploymentOnly'].pop('ERC3643HookFactory')))
semantic('factory-reason-changed', lambda c: hook(c)['deploymentOnly']['ERC3643HookFactory'].__setitem__(
    'reason', 'Not needed.'))
semantic('governor-dropped', lambda c: hook(c)['executed'].pop('ERC3643HookGovernor'))
semantic('template-changed', lambda c: c['runtimeIdentity']['Native']['executed']['TrustToken'].__setitem__(
    'templateSha256', '0' * 64))
semantic('external-assumption-dropped', lambda c: c['retainedAssumptions'].pop('A-EXTERNAL'))
semantic('deployment-assumption-changed', lambda c: c['retainedAssumptions'].__setitem__('A-DEPLOYMENT', 'Bound.'))
for key in sorted(v.IDENTITY_PATHS):
    semantic('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64))
semantic('removed-artifact', lambda c: c['artifacts'].pop())
semantic('reordered-artifacts', lambda c: c['artifacts'].reverse())
semantic('changed-artifact-kind', lambda c: c['artifacts'][0].__setitem__('kind', 'locators'))
semantic('empty-artifact', lambda c: c['artifacts'][0].__setitem__('bytes', 0))
semantic('invalid-artifact-hash', lambda c: c['artifacts'][1].__setitem__('sha256', 'not-a-hash'))
semantic('extra-artifact-key', lambda c: c['artifacts'][1].__setitem__('path', 'registry.json'))
semantic('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
semantic('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
semantic('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'true'))
rejected('reviewed-digest-pin', lambda c: row(c, 'Native/SEIZE/applied').__setitem__(
    'executedCodeSha256', 'a' * 64))
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('consumerBoundary', c['consumerBoundary'] + ' G' + '7'), privacy)
rejected('internal-coordinate-suffix', lambda c: c.__setitem__('scope', c['scope'] + ' cells-g' + '66-v1'), privacy)
rejected('internal-coordinate-underscore', lambda c: c.__setitem__('scope', c['scope'] + ' Cell_G' + '50'), privacy)
rejected('linux-path', lambda c: c.__setitem__('scope', c['scope'] + ' /mn' + 't/c'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c['retainedAssumptions'].__setitem__('A-EXTERNAL', 'a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_CERTIFICATE_REGISTRY_RECORD', 'positive': 1,
                  'negativeControls': len(controls), 'registryRecomputed': False, 'proverRerun': False}, indent=2))
