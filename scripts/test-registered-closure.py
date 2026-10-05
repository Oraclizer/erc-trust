#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the registered central closure record without changing the tracked files.

Record controls change one member of the closure record and re-pin the reviewed digest in memory, so that only the
check named for each control can reject it; one control keeps the pin. Role, ledger and product controls change one
file in a copy of the files that the verifier reads. Positive controls, among them a change to a member of a cited
record that no named field reads, must pass.
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
spec = importlib.util.spec_from_file_location('registered_closure_record_tests',
                                              ROOT / 'scripts/trust12/verify_registered_closure_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
CLOSURE = v.read_json(ROOT / v.CLOSURE_PATH)
CLOSURE_SHA256 = v.digest(ROOT / v.CLOSURE_PATH)
v.verify(ROOT)
PINNED = v.EXPECTED_EVIDENCE_DIGEST
CONDITIONS = v.read_json(ROOT / v.CONDITIONS_PATH)
controls, positives = [], ['unchanged-record']
REG = 'evidence/trust12/runtime-link/tail-preparation/certificate-registry-checkpoint-v1.json'
TRACE = 'evidence/trust12/runtime-link/malformed/call-trace-checkpoint-v1.json'
ROUTE = 'evidence/trust12/runtime-link/tail-preparation/route-inventory-checkpoint-v1.json'
UNGATED = 'evidence/trust12/runtime-link/malformed/native-relation-checkpoint-v1.json'
PREPARED = 'evidence/trust12/runtime-link/tail-preparation/code-identity-v1.json'


def rejected(name, mutate, expected, keep_pin=False, product=None):
    candidate = deepcopy(CLOSURE)
    mutate(candidate)
    v.EXPECTED_EVIDENCE_DIGEST = PINNED if keep_pin else v.payload_digest(candidate)
    try:
        v.verify_record(candidate, product or ROOT, CLOSURE_SHA256)
    except v.ERRORS as error:
        if expected not in str(error):
            raise AssertionError(f'{name}: rejected for another reason: {error}')
        controls.append(name)
        return
    finally:
        v.EXPECTED_EVIDENCE_DIGEST = PINNED
    raise AssertionError('registered closure record mutation accepted: ' + name)


def accepted(name, candidate, product):
    v.EXPECTED_EVIDENCE_DIGEST = v.payload_digest(candidate)
    try:
        v.verify_record(candidate, product, CLOSURE_SHA256)
    finally:
        v.EXPECTED_EVIDENCE_DIGEST = PINNED
    positives.append(name)


def first_condition_with(path):
    return next(cid for cid, items in CLOSURE['conditionEvidence'].items() if any(i['path'] == path for i in items))


def evidence_ref(product, path):
    return {'path': path, 'sha256': v.digest(product / path)}


def support_of(candidate, cid, index=0):
    return candidate['acceptance'][cid][index]['support']


DISCHARGED = CLOSURE['dischargedConditions']
FIRST = DISCHARGED[0]
CONTRACT, BOUNDARY = 'Closure contract differs', 'Public scope or boundary differs'
for key in v.NONCLAIM_KEYS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False), 'nonclaims required')
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k), 'nonclaims required')
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-registered-central-closure-v2'), CONTRACT)
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_TRUST12_COMPLETE'), CONTRACT)
rejected('extra-key', lambda c: c.__setitem__('assuranceDischarged', True), CONTRACT)
for key in ('scope', 'executionBoundary', 'evidenceBoundary', 'assumptionBoundary', 'reproductionBoundary'):
    rejected('changed-' + key, lambda c, k=key: c.__setitem__(k, c[k] + ' Every execution is covered.'), BOUNDARY)
rejected('assurance-claimed', lambda c: c['assurance'].__setitem__('status', 'PASS'), 'claims the independent assurance')
rejected('fixture-marker', lambda c: c['finalInputs'].__setitem__('fixtureOnly', True), 'fixture marker')
rejected('private-path', lambda c: c['conditionNotes'].__setitem__(FIRST, 'see ' + chr(67) + ':' + chr(92) + 'Users'),
         'Private')
rejected('home-path', lambda c: c['conditionNotes'].__setitem__(FIRST, 'see ' + chr(47) + 'ho' + 'me' + chr(47) + 'x'),
         'Private')
rejected('user-directory-path', lambda c: c['conditionNotes'].__setitem__(FIRST, 'see ' + chr(47) + 'Us' + 'ers' + chr(47)
                                                                          + 'x'), 'Private')
rejected('internal-coordinate', lambda c: c['conditionNotes'].__setitem__(FIRST, 'stage G' + '9'), 'Private')
rejected('lowercase-step', lambda c: c['conditionNotes'].__setitem__(FIRST, 'step rl' + '20'), 'Private')
rejected('em-dash', lambda c: c['conditionNotes'].__setitem__(FIRST, 'a ' + chr(0x2014) + ' b'), 'Private')
rejected('non-english', lambda c: c['conditionNotes'].__setitem__(FIRST, 'a ' + chr(0xAC00)), 'Private')
rejected('reviewed-digest-pin', lambda c: c['conditionNotes'].__setitem__(FIRST, c['conditionNotes'][FIRST] + ' Changed.'),
         'Reviewed evidence digest differs', keep_pin=True)
rejected('conditions-source-hash', lambda c: c['conditionsSource'].__setitem__('sha256', '0' * 64),
         'Conditions source differs')
rejected('dropped-condition', lambda c: c['dischargedConditions'].pop(), 'Discharged conditions differ')
rejected('claimed-assurance-condition', lambda c: c['dischargedConditions'].append(v.ASSURANCE_ID),
         'Discharged conditions differ')
rejected('reordered-conditions', lambda c: c['dischargedConditions'].reverse(), 'Discharged conditions differ')
for key in ('conditionEvidence', 'acceptance', 'conditionSupport', 'conditionNotes'):
    rejected('missing-condition-key-' + key, lambda c, k=key: c[k].pop(DISCHARGED[-1]), 'Condition keys differ')
rejected('empty-condition-evidence', lambda c: c['conditionEvidence'].__setitem__(FIRST, []), 'no cited evidence')
rejected('repeated-condition-evidence', lambda c: c['conditionEvidence'][FIRST].append(dict(c['conditionEvidence'][FIRST][0])),
         'Cited evidence repeats')
rejected('stale-condition-evidence', lambda c: c['conditionEvidence'][FIRST][0].__setitem__('sha256', '0' * 64),
         'differs from the current file')
rejected('evidence-outside-evidence-tree', lambda c: c['conditionEvidence'][FIRST].append(evidence_ref(ROOT, v.ABI_PATH)),
         'not a checkpoint record in the evidence tree')
rejected('ungated-evidence', lambda c: c['conditionEvidence'][FIRST].append(evidence_ref(ROOT, UNGATED)),
         'no verifier that the required gate runs')
rejected('non-passing-evidence', lambda c: c['conditionEvidence'][FIRST].append(evidence_ref(ROOT, PREPARED)),
         'not a passing record')
ROUTE_CONDITION = first_condition_with(ROUTE)
rejected('idle-evidence', lambda c: c['conditionEvidence'][ROUTE_CONDITION].append(evidence_ref(ROOT, TRACE)),
         'named by no criterion or clause')
rejected('edited-criterion', lambda c: c['acceptance'][FIRST][0].__setitem__('criterion', c['acceptance'][FIRST][0][
    'criterion'] + ' Shown by review.'), 'Acceptance criteria differ')
rejected('dropped-criterion', lambda c: c['acceptance'][FIRST].pop(), 'Acceptance criteria differ')
rejected('empty-support', lambda c: c['acceptance'][FIRST][0].__setitem__('support', []), 'No named field')
rejected('support-outside-evidence', lambda c: support_of(c, ROUTE_CONDITION).append(
    {'path': TRACE, 'pointer': '/status', 'expected': v.read_json(ROOT / TRACE)['status']}),
         'not in the cited evidence')
rejected('missing-field', lambda c: support_of(c, FIRST)[0].__setitem__('pointer', '/criteria/never-recorded'),
         'Named field is missing')
rejected('changed-expected-value', lambda c: support_of(c, FIRST)[0].__setitem__('expected', 'FAIL'), 'Named field differs')
rejected('filter-without-match', lambda c: support_of(c, FIRST)[0].__setitem__('pointer', '/mutants[id=NO-SUCH-MUTANT]/status'),
         'Pointer')
rejected('limits-not-text', lambda c: c['acceptance'][FIRST][0].__setitem__('limits', None), 'Acceptance entry form differs')
rejected('extra-acceptance-member', lambda c: c['acceptance'][FIRST][0].__setitem__('proved', True),
         'Acceptance entry form differs')
rejected('clause-not-quoted', lambda c: c['conditionSupport'].__setitem__(ROUTE_CONDITION, [
    {'clause': 'every execution of every runtime is covered', 'support': deepcopy(support_of(c, ROUTE_CONDITION))}]),
         'not quoted from the condition')
rejected('note-not-text', lambda c: c['conditionNotes'].__setitem__(FIRST, ['a list']), 'Condition note differs')
FINDING = CONDITIONS['findings'][0]['id']
rejected('blocking-finding-nonclaim', lambda c: c['findingDispositions'].__setitem__(FINDING, {
    'kind': 'NONCLAIM', 'detail': 'Declared out of scope', 'decisionNeeded': c['findingDispositions'][FINDING][
        'decisionNeeded'], 'evidence': [], 'support': []}), 'must be resolved')
rejected('resolved-finding-without-evidence', lambda c: c['findingDispositions'][FINDING].__setitem__('evidence', []),
         'no cited evidence')
rejected('finding-text-changed', lambda c: c['findingDispositions'][FINDING].__setitem__('decisionNeeded', 'Nothing.'),
         'Finding text differs')
rejected('finding-detail-empty', lambda c: c['findingDispositions'][FINDING].__setitem__('detail', ' '),
         'Finding disposition is incomplete')
rejected('finding-free-text', lambda c: c['findingDispositions'].__setitem__(FINDING, 'Resolved by review'),
         'Finding disposition is incomplete')
rejected('finding-dropped', lambda c: c['findingDispositions'].pop(FINDING), 'Finding dispositions differ')
rejected('finding-unknown-kind', lambda c: c['findingDispositions'][FINDING].__setitem__('kind', 'WAIVED'),
         'Finding disposition is incomplete')
rejected('finding-field-changed', lambda c: c['findingDispositions'][FINDING]['support'][0].__setitem__('expected', -1),
         'Named field differs')
for assumption in v.BASE_ASSUMPTIONS:
    def drop(c, a=assumption):
        c['retainedAssumptions'].remove(a)
        c['assumptionStatements'].pop(a)
    rejected('dropped-assumption-' + assumption, drop, 'Retained assumptions differ: missing ' + assumption)
rejected('repeated-assumption', lambda c: c['retainedAssumptions'].append(c['retainedAssumptions'][0]),
         'Retained assumptions differ')
rejected('statement-keys', lambda c: c['assumptionStatements'].pop(c['retainedAssumptions'][-1]),
         'Assumption statements differ')
rejected('central-statement-changed', lambda c: c['assumptionStatements']['A-EVM'].__setitem__('statement', 'Trusted.'),
         'Central assumption statement differs')
rejected('decision-statement-changed', lambda c: c['assumptionStatements']['A-KEVM-TOOLCHAIN'].__setitem__(
    'statement', 'K is proved correct.'), 'Decision assumption statement differs')
rejected('unknown-assumption-source', lambda c: c['assumptionStatements']['A-EVM'].__setitem__('source', 'review'),
         'Assumption statement form differs')
rejected('final-abi-changed', lambda c: c['finalInputs'].__setitem__('abiSha256', '0' * 64), 'Final inputs differ')
rejected('final-runtime-changed', lambda c: c['finalInputs']['runtimeSha256ByContract'].__setitem__('TrustToken', '0' * 64),
         'Final inputs differ')
rejected('final-extra-input', lambda c: c['finalInputs'].__setitem__('deploymentSha256', '0' * 64), 'Final inputs differ')
rejected('general-link-claimed', lambda c: c.__setitem__('generalRuntimeLinkDischarged', True),
         'General runtime link flag differs')
SCOPED = next(iter(CLOSURE['assumptionScope']))
rejected('scope-unretained-assumption', lambda c: c['assumptionScope'].__setitem__('A-NOT-RETAINED', deepcopy(
    c['assumptionScope'][SCOPED])), 'not retained')
rejected('scope-empty-statement', lambda c: c['assumptionScope'][SCOPED].__setitem__('statement', ' '),
         'Assumption scope form differs')
rejected('scope-field-changed', lambda c: c['assumptionScope'][SCOPED]['support'][-1].__setitem__('expected', 'FAIL'),
         'Named field differs')
rejected('scope-support-outside-citations', lambda c: c['assumptionScope'][SCOPED]['support'].append(
    {'path': v.ABI_PATH, 'pointer': '/kernel', 'expected': None}), 'not in the cited evidence')

# Role, ledger and product controls on a copy of every file that the verifier reads.
copy = Path(tempfile.mkdtemp(prefix='registered-closure-controls-')).resolve()
try:
    for relative in v.metadata_inputs(ROOT):
        (copy / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, copy / relative)
    v.verify(copy)
    positives.append('unchanged-copy')

    def read(relative):
        return json.loads((copy / relative).read_text(encoding='utf-8'))

    def write(relative, value):
        (copy / relative).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8', newline='\n')

    def rebind_roles(relative):
        """Name the changed file by its new digest in the role records and the role records in the ledger."""
        new = v.digest(copy / relative)
        for role_path in v.ROLE_PATHS.values():
            record = read(role_path)
            for items in record['conditions'].values():
                for item in items:
                    if item['path'] == relative:
                        item['sha256'] = new
            write(role_path, record)
        ledger = read(v.LEDGER_PATH)
        row = next(item for item in ledger['obligations'] if item['id'] == v.ROW_ID)
        for name, role_path in v.ROLE_PATHS.items():
            row['registeredClosureEvidence']['references'][name]['sha256'] = v.digest(copy / role_path)
        write(v.LEDGER_PATH, ledger)

    def rebound_closure(relative):
        candidate = deepcopy(CLOSURE)
        new = v.digest(copy / relative)
        for items in list(candidate['conditionEvidence'].values()) + [
                d['evidence'] for d in candidate['findingDispositions'].values()]:
            for item in items:
                if item['path'] == relative:
                    item['sha256'] = new
        return candidate

    def product_change(name, relative, edit, expected=None, rebind=False):
        saved = {path: (copy / path).read_bytes() for path in [relative, v.LEDGER_PATH, *v.ROLE_PATHS.values()]}
        try:
            edit(copy / relative)
            if rebind:
                rebind_roles(relative)
            candidate = rebound_closure(relative) if rebind else deepcopy(CLOSURE)
            if expected is None:
                accepted(name, candidate, copy)
                return
            v.EXPECTED_EVIDENCE_DIGEST = v.payload_digest(candidate)
            try:
                v.verify_record(candidate, copy, CLOSURE_SHA256)
            except v.ERRORS as error:
                if expected not in str(error):
                    raise AssertionError(f'{name}: rejected for another reason: {error}')
                controls.append(name)
                return
            finally:
                v.EXPECTED_EVIDENCE_DIGEST = PINNED
            raise AssertionError('registered closure product change accepted: ' + name)
        finally:
            for path, data in saved.items():
                (copy / path).write_bytes(data)

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
                raise AssertionError('product control anchor not found once: ' + old[:60])
            path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')
        return edit

    def row_of(document):
        return next(item for item in document['obligations'] if item['id'] == v.ROW_ID)

    def role_change(name, role_name, change, expected):
        path = v.ROLE_PATHS[role_name]

        def edit(file):
            document = json.loads(file.read_text(encoding='utf-8'))
            change(document)
            file.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8', newline='\n')
            ledger = read(v.LEDGER_PATH)
            row_of(ledger)['registeredClosureEvidence']['references'][role_name]['sha256'] = v.digest(file)
            write(v.LEDGER_PATH, ledger)
        product_change(name, path, edit, expected)

    first_entry = lambda d: d['conditions'][FIRST][0]

    def control_entry(d):
        return next(item for items in d['conditions'].values() for item in items if 'controls' in item)
    role_change('role-unbound', 'positive', lambda d: d.__setitem__('closureSha256', '0' * 64), 'does not bind the closure')
    role_change('negative-passes', 'negative', lambda d: d.__setitem__('status', 'PASS'), 'Role record contract differs')
    role_change('role-statement', 'compiledConsumer', lambda d: d.__setitem__('statement', 'Compiled.'), 'Role statement differs')
    role_change('role-missing-condition', 'negative', lambda d: d['conditions'].pop(DISCHARGED[-1]),
                'does not cover every discharged condition')
    role_change('role-empty-condition', 'positive', lambda d: d['conditions'].__setitem__(FIRST, []),
                'no evidence for a condition')
    role_change('role-unknown-kind', 'negative', lambda d: first_entry(d).__setitem__('kind', 'REVIEW'),
                'Role entry form differs')
    role_change('role-stale-evidence', 'positive', lambda d: first_entry(d).__setitem__('sha256', '0' * 64),
                'Role evidence differs from the current file')
    role_change('role-changed-field', 'compiledConsumer', lambda d: first_entry(d)['support'][0].__setitem__(
        'expected', 'FAIL'), 'Named field differs')
    role_change('role-false-nonclaim', 'negative', lambda d: d['nonclaims'].__setitem__('independentAssurance', False),
                'role nonclaims required')
    role_change('role-fixture', 'positive', lambda d: d['nonclaims'].__setitem__('fixtureOnly', True), 'fixture marker')
    role_change('role-no-fields', 'positive', lambda d: first_entry(d).__setitem__('support', []), 'Role entry fields differ')
    CONTROLLED = any('controls' in item for items in v.read_json(copy / v.ROLE_PATHS['negative'])['conditions'].values()
                     for item in items)
    if CONTROLLED:
        role_change('control-name-unknown', 'negative', lambda d: control_entry(d)['controls'].append('no-such-control'),
                    'Role control is not in the control script')
        role_change('control-kind-changed', 'negative', lambda d: control_entry(d).__setitem__('kind', 'KILLED_MUTANT'),
                    'Role control entry form differs')
        role_change('control-script-hash', 'negative', lambda d: control_entry(d).__setitem__('sha256', '0' * 64),
                    'Role control script differs from the current file')
        script = control_entry(v.read_json(copy / v.ROLE_PATHS['negative']))['path']

        def unrun(path):
            text = path.read_text(encoding='utf-8')
            anchor = "resolve(root, '" + script + "')"
            if anchor not in text:
                raise AssertionError('product control anchor not found: ' + anchor)
            path.write_text(text.replace(anchor, "resolve(root, 'scripts/never-run.py')"), encoding='utf-8',
                            newline='\n')
        product_change('control-script-not-run', v.REQUIRED_CONTROLS_PATH, unrun,
                       'The required controls do not run the control script')
        product_change('control-script-changed', script, append('\n# edited\n'),
                       'Role control script differs from the current file')
    product_change('ledger-row-reopened', v.LEDGER_PATH, edit_json(lambda d: row_of(d).__setitem__('status', 'CURRENT-MANDATORY')),
                   'The ledger row is not closed')
    product_change('ledger-reference-drift', v.LEDGER_PATH, edit_json(lambda d: row_of(d)['registeredClosureEvidence'][
        'references']['negative'].__setitem__('sha256', '0' * 64)), 'does not cite the four records')
    product_change('ledger-text-without-record', v.LEDGER_PATH, edit_json(lambda d: row_of(d).__setitem__(
        'compiledConsumer', 'Compiled consumers exist.')), 'does not name compiledConsumer')
    product_change('ledger-general-links-closed', v.LEDGER_PATH, edit_json(lambda d: [
        item.__setitem__('status', 'CLOSED') for item in d['obligations'] if item['id'] in v.GENERAL_IDS]),
                   'General runtime link flag differs')
    product_change('ledger-one-general-link-closed', v.LEDGER_PATH, edit_json(lambda d: next(
        item for item in d['obligations'] if item['id'] == v.GENERAL_IDS[0]).__setitem__('status', 'CLOSED')), None)
    product_change('changed-cited-record', REG, append(' '), 'differs from the current file')
    verifier_path = v.read_json(copy / REG)['rehashVerifier']['path']
    product_change('changed-cited-verifier', verifier_path, append('\n# edited\n'), 'verifier differs from the current file')
    def ungate(path):
        text = path.read_text(encoding='utf-8')
        if verifier_path not in text:
            raise AssertionError('product control anchor not found: ' + verifier_path)
        path.write_text(text.replace(verifier_path, verifier_path[:-len('.py')] + '_disabled.py'), encoding='utf-8',
                        newline='\n')
    product_change('ungated-cited-verifier', v.REQUIRED_GATE_PATH, ungate, 'no verifier that the required gate runs')
    product_change('changed-conditions-list', v.CONDITIONS_PATH, append(' '), 'Conditions source differs')
    product_change('changed-runtime-identity', v.RUNTIME_IDENTITY_PATH, edit_json(
        lambda d: d['runtimes']['TrustToken'].__setitem__('runtimeSha256', '0' * 64)), 'Final inputs differ')
    source = v.read_json(copy / v.RUNTIME_IDENTITY_PATH)['sourceInputs'][0]['path']
    product_change('changed-runtime-source', source, append('\n'), 'Runtime source differs from the runtime identity')
    product_change('changed-abi', v.ABI_PATH, append(' '), 'Final inputs differ')
    product_change('discharged-central-assumption', v.CENTRAL_LEDGER_PATH, edit_json(lambda d: next(
        item for item in d['assumptions'] if item['id'] == 'A-MUTATION').__setitem__('status', 'DISCHARGED')),
                   'Central assumption statement differs')
    product_change('new-central-assumption', v.CENTRAL_LEDGER_PATH, edit_json(lambda d: d['assumptions'].append(
        {'id': 'A-NEW-CONTROL', 'status': 'ASSUMED', 'statement': 'A new assumption.'})),
                   'Retained assumptions differ: missing A-NEW-CONTROL')
    product_change('decision-sentence-changed', v.DECISION_PATH, replace('are trusted to produce', 'produce'),
                   'Decision assumption statement differs')
    product_change('record-retains-new-assumption', REG, edit_json(lambda d: d['retainedAssumptions'].__setitem__(
        'A-NEW-RECORD', 'A record assumption.')), 'Retained assumptions differ: missing A-NEW-RECORD', rebind=True)
    product_change('record-runtime-differs', REG, edit_json(lambda d: d['runtimeIdentity']['Native']['executed'][
        'TrustToken'].__setitem__('templateSha256', '0' * 64)), 'differs from the runtime identity', rebind=True)
    product_change('record-unnamed-member-changed', REG, edit_json(lambda d: d.__setitem__('scope', d['scope'] + ' ')),
                   None, rebind=True)
    CARRIED = 'An open item of the crosswalk is still carried to a later gate'
    product_change('crosswalk-open-item-carried', v.DISPOSITIONS_PATH, edit_json(
        lambda d: d['openItems'][0].__setitem__('disposition', 'AWAITS_FORMAL_READER')), CARRIED)
    product_change('crosswalk-open-item-needs-decision', v.DISPOSITIONS_PATH, edit_json(
        lambda d: d['openItems'][-1].__setitem__('disposition', 'NEEDS_DECISION')), CARRIED)
    product_change('crosswalk-open-item-carry-over', v.DISPOSITIONS_PATH, edit_json(
        lambda d: d['openItems'][-1].__setitem__('carryOver', {'receivingGate': 'a later gate'})), CARRIED)
    product_change('crosswalk-dispositions-unreviewed', v.DISPOSITIONS_PATH, edit_json(
        lambda d: d.__setitem__('status', 'DRAFT')), CARRIED)
finally:
    shutil.rmtree(copy, ignore_errors=True)
print(json.dumps({'status': 'PASS_PUBLIC_REGISTERED_CLOSURE', 'positive': len(positives),
                  'negativeControls': len(controls)}, indent=2))
