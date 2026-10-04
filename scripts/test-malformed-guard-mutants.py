#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public length-guard mutant record boundary without rerunning Foundry or reading saved receipts."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('malformed_guard_mutant_tests',
                                              ROOT / 'scripts/trust12/verify_malformed_guard_mutants_v1.py')
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
    raise AssertionError('length-guard mutant record mutation accepted: ' + name)


def mutant(candidate, identifier):
    return next(row for row in candidate['mutants'] if row['id'] == identifier)


def other_variant(candidate):
    effect = mutant(candidate, 'PARTIAL-ACTION-LENGTH')['effects'][0]
    effect['variant'] = 'one-word-long' if effect['variant'] != 'one-word-long' else 'one-byte-long'


for key in v.NONCLAIMS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False))
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k))
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-malformed-guard-mutants-checkpoint-v2'))
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_MALFORMED_BRANCH_CLOSED'))
rejected('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('quietly', 'safely')))
rejected('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True))
rejected('removed-mutant', lambda c: c['mutants'].pop())
rejected('reordered-mutants', lambda c: c['mutants'].reverse())
rejected('duplicate-mutant', lambda c: c['mutants'].__setitem__(1, deepcopy(c['mutants'][0])))
rejected('survived-mutant', lambda c: mutant(c, 'PARTIAL-ACTION-LENGTH').__setitem__('status', 'MUTANT_SURVIVED'))
rejected('changed-profile', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').__setitem__('profile', 'Partial'))
rejected('dropped-entrypoint', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['entrypoints'].pop())
rejected('changed-fault', lambda c: mutant(c, 'NATIVE-REVERSAL-LENGTH').__setitem__('fault', 'Accept any reversal'))
rejected('changed-mutation-file', lambda c: mutant(c, 'PARTIAL-REVERSAL-LENGTH')['mutation'].__setitem__(
    'file', 'implementation/src/TrustToken.sol'))
rejected('stale-source-before', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['mutation'].__setitem__('beforeSha256', '0' * 64))
rejected('other-mutation-after', lambda c: mutant(c, 'HOOK-REVERSAL-LENGTH')['mutation'].__setitem__(
    'afterSha256', mutant(c, 'HOOK-ACTION-LENGTH')['mutation']['afterSha256']))
rejected('changed-occurrences', lambda c: mutant(c, 'PARTIAL-ACTION-LENGTH')['mutation'].__setitem__('occurrences', 2))
rejected('empty-deviating-recipes', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['deviatingLengthRecipes'].__setitem__(
    'executeERC7943Action', []))
rejected('missing-deviating-endpoint', lambda c: mutant(c, 'NATIVE-REVERSAL-LENGTH')['deviatingLengthRecipes'].pop(
    'executeERC7943Reversal'))
rejected('foreign-deviating-recipe', lambda c: mutant(c, 'PARTIAL-ACTION-LENGTH')['deviatingLengthRecipes'].__setitem__(
    'executeRegulatoryAction', list(mutant(c, 'HOOK-ACTION-LENGTH')['deviatingLengthRecipes']['executeRegulatoryAction'])))
rejected('emptied-effects', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').__setitem__('effects', []))
rejected('dropped-effect', lambda c: mutant(c, 'NATIVE-REVERSAL-LENGTH')['effects'].pop())
rejected('reverted-effect', lambda c: mutant(c, 'PARTIAL-REVERSAL-LENGTH')['effects'][0].__setitem__('outcome', 'revert'))
rejected('silent-effect', lambda c: mutant(c, 'HOOK-REVERSAL-LENGTH')['effects'][0].__setitem__('logs', 0))
rejected('no-write-effect', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['effects'][0].__setitem__('committedWrites', 0))
rejected('no-external-effect', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['effects'][0].__setitem__('externalAccesses', 0))
rejected('boolean-count', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['effects'][0].__setitem__('logs', True))
rejected('inflated-logs', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH')['effects'][0].__setitem__(
    'logs', mutant(c, 'NATIVE-ACTION-LENGTH')['effects'][0]['logs'] + 7))
rejected('changed-variant', other_variant)
rejected('invalid-receipt-hash', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').__setitem__('receiptSha256', 'not-a-hash'))
rejected('replaced-receipt-hash', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').__setitem__('receiptSha256', 'b' * 64))
rejected('zero-elapsed', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').__setitem__('forgeElapsedSeconds', 0))
rejected('changed-elapsed', lambda c: mutant(c, 'PARTIAL-ACTION-LENGTH').__setitem__(
    'forgeElapsedSeconds', mutant(c, 'PARTIAL-ACTION-LENGTH')['forgeElapsedSeconds'] + 1))
rejected('removed-hook-repin', lambda c: mutant(c, 'HOOK-ACTION-LENGTH').pop('repin'))
rejected('added-native-repin', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH').__setitem__(
    'repin', deepcopy(mutant(c, 'HOOK-ACTION-LENGTH')['repin'])))
rejected('stale-factory-pin', lambda c: mutant(c, 'HOOK-REVERSAL-LENGTH')['repin'].__setitem__('beforePin', '0x' + '0' * 64))
rejected('unchanged-factory-pin', lambda c: mutant(c, 'HOOK-REVERSAL-LENGTH')['repin'].__setitem__(
    'afterPin', mutant(c, 'HOOK-REVERSAL-LENGTH')['repin']['beforePin']))
rejected('changed-after-pin', lambda c: mutant(c, 'HOOK-ACTION-LENGTH')['repin'].__setitem__('afterPin', '0x' + 'c' * 64))
rejected('changed-repin-reason', lambda c: mutant(c, 'HOOK-ACTION-LENGTH')['repin'].__setitem__('reason', 'any reason'))
for key in ('catalog', 'mutantList', 'baselineProbe'):
    rejected('changed-product-' + key, lambda c, k=key: c['product'][k].__setitem__('sha256', '0' * 64))
rejected('removed-baseline', lambda c: c['product'].pop('baselineProbe'))
rejected('changed-runner', lambda c: c['product']['runners'][1].__setitem__('sha256', '0' * 64))
rejected('removed-runner', lambda c: c['product']['runners'].pop())
rejected('changed-probe-source', lambda c: c['product']['probeSources'][0].__setitem__('sha256', '0' * 64))
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64))
rejected('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'))
privacy = v.privacy_boundary
rejected('private-path', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH').__setitem__(
    'fault', 'Accept ' + chr(67) + ':' + chr(47) + 'Users'), privacy)
rejected('internal-coordinate', lambda c: mutant(c, 'NATIVE-ACTION-LENGTH').__setitem__('fault', 'Accept G' + '7'), privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), privacy)
rejected('em-dash', lambda c: mutant(c, 'HOOK-ACTION-LENGTH')['repin'].__setitem__('reason', 'a ' + chr(0x2014) + ' b'), privacy)
print(json.dumps({'status': 'PASS_PUBLIC_MALFORMED_GUARD_MUTANTS', 'positive': 1,
                  'negativeControls': len(controls), 'foundryRerun': False}, indent=2))
