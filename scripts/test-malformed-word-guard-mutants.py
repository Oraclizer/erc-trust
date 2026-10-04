#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public bounded word guard mutant record boundary without rerunning Foundry or reading receipts."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('malformed_word_guard_mutant_tests',
                                              ROOT / 'scripts/trust12/verify_malformed_word_guard_mutants_v1.py')
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
    raise AssertionError('bounded word guard mutant record mutation accepted: ' + name)


def mutant(candidate, identifier):
    return next(row for row in candidate['mutants'] if row['id'] == identifier)


def first(candidate, identifier):
    return mutant(candidate, identifier)['familyWitnesses'][0]


for key in v.NONCLAIMS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-malformed-word-guard-mutants-checkpoint-v2'))
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_MALFORMED_BRANCH_CLOSED'))
for key in ('scope', 'decoderBoundary', 'witnessBoundary', 'catalogBoundary', 'equivalenceBoundary'):
    rejected('changed-' + key, lambda c, k=key: c.__setitem__(k, c[k] + ' Every check is proved.'))
rejected('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
rejected('removed-mutant', lambda c: c['mutants'].pop())
rejected('reordered-mutants', lambda c: c['mutants'].reverse())
rejected('duplicate-mutant', lambda c: c['mutants'].__setitem__(1, deepcopy(c['mutants'][0])))
rejected('survived-mutant', lambda c: mutant(c, 'UINT64-WIDTH').__setitem__('status', 'MUTANT_SURVIVED'))
rejected('equivalent-called-detected', lambda c: mutant(c, 'REVERSAL-KIND-BOUND').__setitem__('status', 'MUTANT_DETECTED'))
rejected('detected-called-equivalent', lambda c: mutant(c, 'ACTION-KIND-BOUND').__setitem__('expectedVerdict', 'EQUIVALENT'))
rejected('changed-target', lambda c: mutant(c, 'ADDRESS-WIDTH').__setitem__('target', 'uint64'))
rejected('dropped-profile', lambda c: mutant(c, 'UINT48-WIDTH')['profiles'].pop())
rejected('changed-fault', lambda c: mutant(c, 'UINT48-WIDTH').__setitem__('fault', 'Accept any time'))
rejected('stale-source-before', lambda c: mutant(c, 'ADDRESS-WIDTH')['mutation']['files'][0].__setitem__(
    'beforeSha256', '0' * 64))
rejected('other-rewrite-after', lambda c: mutant(c, 'UINT64-WIDTH')['mutation']['files'][0].__setitem__(
    'afterSha256', mutant(c, 'ADDRESS-WIDTH')['mutation']['files'][0]['afterSha256']))
rejected('fewer-rewritten-reads', lambda c: mutant(c, 'ADDRESS-WIDTH')['mutation']['files'][0]['reads'].__setitem__(
    'ActionRequest.subject', 1))
rejected('dropped-memory-copy', lambda c: mutant(c, 'UINT48-WIDTH')['mutation']['files'][0].__setitem__('memoryCopies', 0))
rejected('dropped-file', lambda c: mutant(c, 'UINT48-WIDTH')['mutation']['files'].pop())
rejected('changed-enum-width', lambda c: mutant(c, 'ACTION-KIND-BOUND')['mutation']['files'][0].__setitem__(
    'membersAfter', 128))
rejected('removed-repin', lambda c: mutant(c, 'ACTION-KIND-BOUND').__setitem__('repin', None))
rejected('stale-factory-pin', lambda c: mutant(c, 'ADDRESS-WIDTH')['repin'].__setitem__('beforePin', '0x' + '0' * 64))
rejected('unchanged-factory-pin', lambda c: mutant(c, 'ADDRESS-WIDTH')['repin'].__setitem__(
    'afterPin', mutant(c, 'ADDRESS-WIDTH')['repin']['beforePin']))
rejected('changed-repin-reason', lambda c: mutant(c, 'UINT64-WIDTH')['repin'].__setitem__('reason', 'any reason'))
rejected('quiet-detected-witness', lambda c: first(c, 'ADDRESS-WIDTH').update(
    outcome='untyped-empty-revert', logs=0, committedWrites=0, externalAccesses=0))
rejected('quiet-kind-width-witness', lambda c: first(c, 'REVERSAL-KIND-WIDTH').update(
    outcome='other-revert', logs=0, committedWrites=0, externalAccesses=0))
rejected('kind-width-called-equivalent', lambda c: mutant(c, 'REVERSAL-KIND-WIDTH').__setitem__(
    'expectedVerdict', 'EQUIVALENT'))
rejected('kind-width-target-is-range', lambda c: mutant(c, 'ACTION-KIND-WIDTH').__setitem__('target', 'ActionKind'))
rejected('kind-width-other-field', lambda c: first(c, 'ACTION-KIND-WIDTH').__setitem__('field', 'reversal'))
rejected('noisy-equivalent-witness', lambda c: first(c, 'REVERSAL-KIND-BOUND').__setitem__('logs', 1))
rejected('other-equivalent-failure', lambda c: first(c, 'REVERSAL-KIND-BOUND').__setitem__('reason', 6))
rejected('dropped-family-witness', lambda c: mutant(c, 'UINT64-WIDTH')['familyWitnesses'].pop())
rejected('foreign-family-witness', lambda c: mutant(c, 'UINT48-WIDTH')['familyWitnesses'].__setitem__(
    0, deepcopy(first(c, 'UINT64-WIDTH'))))
rejected('boolean-count', lambda c: first(c, 'ACTION-KIND-BOUND').__setitem__('logs', True))
rejected('noisy-other-witness', lambda c: mutant(c, 'ADDRESS-WIDTH')['otherWitnesses'].__setitem__(
    'quiet', mutant(c, 'ADDRESS-WIDTH')['otherWitnesses']['quiet'] - 1))
rejected('failed-control', lambda c: mutant(c, 'ACTION-KIND-BOUND')['controls'].__setitem__('accepted', 3))
rejected('foreign-catalog-recipe', lambda c: mutant(c, 'ADDRESS-WIDTH')['catalogFamilyRecipes']['deviating'].append(
    'native-006'))
rejected('recipe-in-both-lists', lambda c: mutant(c, 'UINT48-WIDTH')['catalogFamilyRecipes']['quiet'].extend(
    mutant(c, 'UINT48-WIDTH')['catalogFamilyRecipes']['deviating'][:1] or ['native-000']))
rejected('zero-elapsed', lambda c: mutant(c, 'UINT48-WIDTH')['forgeElapsedSeconds'].__setitem__('wordGuardProbe', 0))
rejected('invalid-receipt-hash', lambda c: mutant(c, 'UINT48-WIDTH').__setitem__('receiptSha256', 'not-a-hash'))
rejected('baseline-success', lambda c: c['baseline']['outcomes'].__setitem__('success', 1))
rejected('baseline-noisy', lambda c: c['baseline'].__setitem__('quietFailures', c['baseline']['quietFailures'] - 1))
rejected('baseline-control-failed', lambda c: c['baseline']['controls'].__setitem__('accepted', 0))
rejected('baseline-catalog-control-missed', lambda c: c['baseline']['catalog']['summary'].__setitem__(
    'Native/well-formed-control/CONTROL_DETECTED', c['baseline']['catalog']['summary'][
        'Native/well-formed-control/CONTROL_DETECTED'] - 1))
rejected('baseline-catalog-recipe-noisy', lambda c: c['baseline']['catalog']['summary'].update({
    'Hook/length/CONFORMS': c['baseline']['catalog']['summary']['Hook/length/CONFORMS'] - 1,
    'Hook/length/DEVIATES': 1}))
rejected('baseline-catalog-fewer-recipes', lambda c: c['baseline']['catalog'].__setitem__(
    'recipes', c['baseline']['catalog']['recipes'] - 1))
rejected('baseline-fewer-witnesses', lambda c: c['baseline']['witnesses'].__setitem__(
    'Hook', c['baseline']['witnesses']['Hook'] - 1))
for key in ('catalog', 'mutantList'):
    rejected('changed-product-' + key, lambda c, k=key: c['product'][k].__setitem__('sha256', '0' * 64))
rejected('changed-runner', lambda c: c['product']['runners'][2].__setitem__('sha256', '0' * 64))
rejected('removed-runner', lambda c: c['product']['runners'].pop())
rejected('changed-probe-source', lambda c: c['product']['probeSources'][-1].__setitem__('sha256', '0' * 64))
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
rejected('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
privacy = v.privacy_boundary
rejected('private-path', lambda c: mutant(c, 'UINT64-WIDTH').__setitem__(
    'fault', 'Accept ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: mutant(c, 'UINT64-WIDTH').__setitem__('fault', 'Accept G' + '7'), privacy)
rejected('lowercase-step-suffix', lambda c: mutant(c, 'UINT64-WIDTH').__setitem__('fault', 'Accept fv' + '12'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: c.__setitem__('scope', 'a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_MALFORMED_WORD_GUARD_MUTANTS', 'positive': 1,
                  'negativeControls': len(controls), 'foundryRerun': False}, indent=2))
