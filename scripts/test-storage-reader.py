#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public storage reader record boundary without reading the session databases or the build.

Record controls change one field of the record and re-pin the reviewed digest in memory, so that only the semantic
check named for each control can reject it; one control keeps the pin. Product controls change one tracked input in
a copy of the files that metadata mode reads; some of them also name the changed file in the record copy, so that
only the semantic recomputation can reject them. Positive controls change only members that the record does not read,
or move the first open item of the dispositions to its resolved form, and must pass.
"""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('storage_reader_record_tests',
                                              ROOT / 'scripts/trust12/verify_storage_reader_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.read_json(ROOT / v.CHECKPOINT_PATH)
v.public_contract(checkpoint, ROOT)
PINNED = v.EXPECTED_EVIDENCE_DIGEST
ERRORS = (RuntimeError, ValueError, KeyError, TypeError, AttributeError, IndexError)
controls, positives = [], ['unchanged-record']


def rejected(name, mutate, expected, keep_pin=False, product=None, check=None):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    v.EXPECTED_EVIDENCE_DIGEST = PINNED if keep_pin else v.payload_digest(candidate)
    try:
        (check or (lambda c: v.public_contract(c, product or ROOT)))(candidate)
    except ERRORS as error:
        if expected not in str(error):
            raise AssertionError(f'{name}: rejected for another reason: {error}')
        controls.append(name)
        return
    finally:
        v.EXPECTED_EVIDENCE_DIGEST = PINNED
    raise AssertionError('storage reader record mutation accepted: ' + name)


def clause_swap(identifier, old, new):
    def mutate(candidate):
        value = candidate['readerClauses'][identifier]
        if isinstance(value, list):
            assert sum(item.count(old) for item in value) == 1, (identifier, old)
            candidate['readerClauses'][identifier] = [item.replace(old, new) for item in value]
        else:
            assert value.count(old) == 1, (identifier, old)
            candidate['readerClauses'][identifier] = value.replace(old, new)
    return mutate


def both(*mutations):
    def mutate(candidate):
        for item in mutations:
            item(candidate)
    return mutate


def row(candidate, field, runtime):
    return next(item for item in candidate['comparison']['rows'] if item['field'] == field and item['runtime'] == runtime)


CONTRACT, BOUNDARY, COVERAGE = 'Checkpoint contract differs', 'Public scope or boundary differs', 'Coverage differs'
CLAUSES, FORMS = 'Reader clauses do not give the pinned readers', 'Recomputed read forms differ'
SLOT_17 = 'then A (psr_slot keccak a 17) else 0)'
SLOT_18 = 'then A (psr_slot keccak a 18) else 0)'
for key in v.NONCLAIM_KEYS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False), 'nonclaims required')
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k), 'nonclaims required')
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-storage-reader-checkpoint-v2'), CONTRACT)
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_STATE_AND_RECEIPT_IDENTITY_CLOSED'), CONTRACT)
rejected('extra-key', lambda c: c.__setitem__('generalExecution', True), CONTRACT)
rejected('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace('agree slot for slot', 'hold the values')),
         BOUNDARY)
rejected('hidden-hash-assumption', lambda c: c.__setitem__('readerBoundary', c['readerBoundary'].replace(
    'is the retained assumption A-KECCAK', 'is proved')), BOUNDARY)
rejected('hidden-key-scope', lambda c: c.__setitem__('readerBoundary', c['readerBoundary'].replace(
    ' Any other key reads as the absent value.', '')), BOUNDARY)
rejected('hidden-registry-step', lambda c: c.__setitem__('conditionBoundary', c['conditionBoundary'].replace(
    'naming them in the certificate registry, ', '')), BOUNDARY)
rejected('hidden-representation-choice', lambda c: c.__setitem__('representationBoundary', c[
    'representationBoundary'].replace('Some readings are representation choices, not storage facts. ', '')), BOUNDARY)
rejected('stronger-condition-claim', lambda c: c.__setitem__('conditionBoundary', c['conditionBoundary'].replace(
    'It does not show that a deployed runtime holds these values in a general execution', 'A deployed runtime holds '
    'these values in every execution')), BOUNDARY)
rejected('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', c['reproductionBoundary'] + ' x'),
         BOUNDARY)
rejected('inflated-agreement', lambda c: c['coverage']['verdicts'].__setitem__('AGREES', 50), COVERAGE)
rejected('derived-columns-short', lambda c: c['coverage']['derivedHookColumns'].__setitem__('agreeing', 14), COVERAGE)
rejected('nonzero-mismatches', lambda c: c['coverage'].__setitem__('mismatches', 1), COVERAGE)
rejected('changed-world-count', lambda c: c['coverage']['recordedWorlds']['hook'].__setitem__('worlds', 15), COVERAGE)
rejected('invalid-artifact-hash', lambda c: c['artifacts'][0].__setitem__('sha256', 'not-a-hash'), 'Artifact inventory')
rejected('changed-artifact-kind', lambda c: c['artifacts'][-1].__setitem__('kind', 'session-database'),
         'Artifact inventory')
rejected('removed-artifact', lambda c: c['artifacts'].pop(), 'Artifact inventory')
rejected('shared-artifact-hash', lambda c: c['artifacts'][1].__setitem__('sha256', c['artifacts'][0]['sha256']),
         'Artifact inventory')
rejected('removed-source', lambda c: c['readerSources'].pop('native-reader'), 'Reader sources differ')
rejected('source-in-other-database', lambda c: c['readerSources']['native-reader'].__setitem__(
    'database', 'session-native-layout'), 'Reader sources differ')
rejected('shared-source-hash', lambda c: c['readerSources']['hook-profile'].__setitem__(
    'sha256', c['readerSources']['partial-profile']['sha256']), 'Reader sources differ')
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64), 'Current verifier differs')
rejected('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'), 'Current verifier differs')
rejected('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'python3 verify.py'),
         'Current verifier differs')
for key in v.IDENTITY_PATHS:
    rejected('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64),
             'Product identity differs')
rejected('changed-formal-members', lambda c: c['formalMembers'].__setitem__('sha256', '0' * 64), 'Formal members differ')
rejected('changed-acceptance', lambda c: c['evidenceFor']['closureAcceptance'].__setitem__(1, 'Reviewed by hand.'),
         'Condition text differs')
rejected('changed-finding', lambda c: c['evidenceFor']['finding'].__setitem__('id', 'open-runtime-only-storage'),
         'Condition text differs')
rejected('changed-helper', clause_swap('helper:pw_map_read', '(pw_mapping_preimage key slot)) else 0)',
                                       '(pw_mapping_preimage key 0)) else 0)'), CLAUSES)
rejected('changed-generation-statement', clause_swap('native:pw3_non_receipt_fields_agree', '(pw2_manifest keccak)',
                                                     '(pw_manifest keccak)'), CLAUSES)
rejected('slot-changed-in-definition-only', clause_swap('shared:psr_state', SLOT_17, SLOT_18), CLAUSES)
rejected('slot-changed-in-reader', both(clause_swap('shared:psr_state', SLOT_17, SLOT_18),
                                        clause_swap('shared:psr_state_fields', SLOT_17, SLOT_18)), FORMS)
rejected('native-slot-changed', both(clause_swap('native:pw_manifest', 'pw_map_read cfg a 7)', 'pw_map_read cfg a 8)'),
                                     clause_swap('native:pw_manifest_selectors', 'pw_map_read cfg a 7)',
                                                 'pw_map_read cfg a 8)')), FORMS)
rejected('token-kind-changed', clause_swap('hook:constants', 'PSR_Token_TREX', 'PSR_Token_Mock'), FORMS)
rejected('struct-member-moved', clause_swap('struct:pw_read_receipt', 'compositional_amount = st (base + 7)',
                                            'compositional_amount = st (base + 8)'), FORMS)
rejected('unparsed-clause', clause_swap('shared:psr_state', 'A 4,', 'A (4 + 0),'), 'unrecognized reader clause')
rejected('changed-read-form', lambda c: c['readerForms']['profiles']['partial']['custody_backing'].__setitem__('slot', 18),
         FORMS)
rejected('changed-verdict', lambda c: row(c, 'authorities', 'ERC3643HookAdapter').__setitem__('verdict', 'AGREES'),
         'Recomputed comparison differs')
rejected('changed-row-slot', lambda c: row(c, 'case_records', 'TrustToken').__setitem__('slot', 15),
         'Recomputed comparison differs')
rejected('changed-absent-value', lambda c: c['absentValues']['bindings']['adapters'].__setitem__('notStored', []),
         'Absent values differ')
rejected('first-item-awaiting', lambda c: c['openItems'][0].__setitem__('disposition', 'AWAITS_FORMAL_READER'),
         'Open item rows differ')
rejected('changed-item-disposition', lambda c: c['openItems'][4].__setitem__('disposition', 'NONCLAIM'),
         'Open item rows differ')
rejected('shrunk-layout-words', lambda c: c['layoutWords']['hook']['14'].remove(2), 'Readers disagree with the crosswalk')
rejected('changed-world-facts', lambda c: c['recordedWorlds']['partial'].__setitem__('fieldFacts', 303),
         'Coverage does not follow from the rows')
rejected('removed-cell', lambda c: c['cellStatements']['native']['FREEZE'].pop(), 'Coverage does not follow from the rows')
rejected('member-layout-mismatch', lambda c: c['memberLayouts'][0].__setitem__('verdict', 'MISMATCH'),
         'Member layout rows differ')
rejected('reviewed-digest-pin', lambda c: row(c, 'dependency_root', 'TrustToken').__setitem__('slot', 23),
         'Reviewed evidence digest differs', keep_pin=True)
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', 'see ' + chr(67) + ':' + chr(47) + 'Users'), 'Private',
         check=privacy)
rejected('home-path', lambda c: c.__setitem__('scope', 'see ' + chr(47) + 'ho' + 'me' + chr(47) + 'user'), 'Private',
         check=privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('scope', 'stage G' + '9'), 'Private', check=privacy)
rejected('lowercase-step-suffix', lambda c: c.__setitem__('scope', 'stage rl' + '20'), 'Private', check=privacy)
rejected('quoted-symbol-escape', lambda c: c['readerClauses'].__setitem__('helper:pw_bits', chr(92) + '<lambda>'),
         'Private', check=privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), 'Private', check=privacy)
rejected('em-dash', lambda c: c.__setitem__('scope', 'a ' + chr(0x2014) + ' b'), 'Private', check=privacy)

# Product controls on a copy of every file that metadata mode reads.
copy = Path(tempfile.mkdtemp(prefix='storage-reader-controls-')).resolve()
try:
    for relative in v.metadata_inputs(ROOT):
        (copy / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, copy / relative)
    v.public_contract(checkpoint, copy)
    positives.append('unchanged-copy')

    def product_change(name, relative, edit, expected=None, rebind=None):
        """Change one copied file; with rebind, the record copy also names the changed file by its new identity."""
        path = copy / relative
        original = path.read_bytes()
        try:
            edit(path)
            if expected is None:
                v.public_contract(checkpoint, copy)
                positives.append(name)
            else:
                def mutate(candidate):
                    if rebind:
                        candidate['productIdentity'][rebind] = v.file_identity(copy, relative)
                rejected(name, mutate, expected, product=copy)
        finally:
            path.write_bytes(original)

    def edit_json(change):
        def edit(path):
            document = json.loads(path.read_text(encoding='utf-8'))
            change(document)
            path.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8', newline='\n')
        return edit

    def append(text):
        return lambda path: path.write_bytes(path.read_bytes() + text.encode('utf-8'))

    def replace(old, new):
        def edit(path):
            text = path.read_text(encoding='utf-8')
            if text.count(old) != 1:
                raise AssertionError('product control anchor not found once: ' + old)
            path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')
        return edit

    def item(document, index):
        return next(entry for entry in document['openItems'] if entry['index'] == index)

    def resolve_first(document):
        first = item(document, 0)
        first.pop('carryOver', None)
        first.update({'disposition': 'RESOLVED_BY_FORMAL_READER', 'record': v.CHECKPOINT_PATH})

    def other_closure(document):
        first = item(document, 0)
        if 'carryOver' in first:
            first['carryOver']['closureEvidence'] = 'a review'
        else:
            first['record'] = 'evidence/trust12/runtime-link/tail-preparation/other-checkpoint-v1.json'

    def field(document, name):
        return next(entry for entry in document['stateFields'] if entry['abstract'] == name)

    product_change('dispositions-unread-member', v.DISPOSITIONS_PATH,
                   edit_json(lambda d: d['storage'][0].__setitem__('reason', d['storage'][0]['reason'] + ' (edited)')))
    product_change('first-item-resolved-form', v.DISPOSITIONS_PATH, edit_json(resolve_first))
    product_change('formal-comment', v.load_tool(ROOT).FORMAL['state'], append('\n(* comment *)\n'))
    product_change('changed-tool', v.IDENTITY_PATHS['tool'], append('\n# edited\n'), 'Product identity differs')
    product_change('changed-crosswalk', v.IDENTITY_PATHS['crosswalk'], append(' '), 'Product identity differs')
    product_change('crosswalk-slot-moved', v.IDENTITY_PATHS['crosswalk'],
                   edit_json(lambda d: field(d, 'custody_backing')['runtimes']['ERC3643HookAdapter']['storage']
                             .__setitem__('slot', 18)), 'Readers disagree with the crosswalk', rebind='crosswalk')
    product_change('crosswalk-type-changed', v.IDENTITY_PATHS['crosswalk'],
                   edit_json(lambda d: field(d, 'dependency_epoch')['runtimes']['TrustToken']['storage']
                             .__setitem__('type', 'uint256')), 'Readers disagree with the crosswalk', rebind='crosswalk')
    product_change('crosswalk-item-text', v.IDENTITY_PATHS['crosswalk'],
                   edit_json(lambda d: d['openItems'].__setitem__(5, d['openItems'][5] + ' (edited)')),
                   'Open item dispositions differ', rebind='crosswalk')
    product_change('first-item-nonclaim', v.DISPOSITIONS_PATH,
                   edit_json(lambda d: item(d, 0).__setitem__('disposition', 'NONCLAIM')),
                   'The first open item does not wait for or name this record')
    product_change('first-item-other-closure', v.DISPOSITIONS_PATH, edit_json(other_closure),
                   'The first open item does not wait for or name this record')
    product_change('changed-item-kind', v.DISPOSITIONS_PATH,
                   edit_json(lambda d: item(d, 3).__setitem__('disposition', 'NONCLAIM')), 'Open item rows differ')
    product_change('carried-item', v.DISPOSITIONS_PATH,
                   edit_json(lambda d: item(d, 6).__setitem__('disposition', 'NEEDS_DECISION')),
                   'still carried')
    product_change('draft-dispositions', v.DISPOSITIONS_PATH, edit_json(lambda d: d.__setitem__('status', 'DRAFT')),
                   'Open item dispositions differ')
    product_change('changed-acceptance-text', v.CONDITIONS_PATH,
                   replace('agrees with the crosswalk.', 'agrees with a review.'), 'Condition text differs')
    product_change('reordered-state-fields', v.load_tool(ROOT).FORMAL['state'],
                   replace('  dependency_root :: trust_hash\n  dependency_epoch :: nat\n',
                           '  dependency_epoch :: nat\n  dependency_root :: trust_hash\n'),
                   'manifest projection order differs')
    product_change('moved-generated-slot', v.load_tool(ROOT).FORMAL['bridge'],
                   replace("(''profile.adapter.custodyBacking'', 17)", "(''profile.adapter.custodyBacking'', 18)"),
                   'Formal members differ')
    product_change('changed-verifier', v.VERIFIER_PATH, append('\n# edited\n'), 'Current verifier differs')
finally:
    shutil.rmtree(copy, ignore_errors=True)
print(json.dumps({'status': 'PASS_PUBLIC_STORAGE_READER', 'positive': len(positives),
                  'negativeControls': len(controls), 'sourcesReread': False}, indent=2))
