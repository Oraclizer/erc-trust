#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public record of the registered gate without reading the session databases.

Record controls change one member of the record and re-pin the reviewed digest in memory, so that only the check named
for each control can reject it; one control keeps the pin. Product controls change one tracked input in a copy of the
files that metadata mode reads. Positive controls change only members of other records that this record does not
read, and must pass.
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
spec = importlib.util.spec_from_file_location('registered_gate_record_tests',
                                              ROOT / 'scripts/trust12/verify_registered_gate_v1.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
checkpoint = v.read_json(ROOT / v.CHECKPOINT_PATH)
v.public_contract(checkpoint, ROOT)
PINNED = v.EXPECTED_EVIDENCE_DIGEST
ERRORS = (RuntimeError, ValueError, KeyError, TypeError, AttributeError, IndexError, StopIteration)
controls, positives = [], ['unchanged-record']


def attempt(candidate, product, keep_pin):
    v.EXPECTED_EVIDENCE_DIGEST = PINNED if keep_pin else v.payload_digest(candidate)
    try:
        v.public_contract(candidate, product)
    finally:
        v.EXPECTED_EVIDENCE_DIGEST = PINNED


def rejected(name, mutate, expected, keep_pin=False, product=None):
    candidate = deepcopy(checkpoint)
    mutate(candidate)
    try:
        attempt(candidate, product or ROOT, keep_pin)
    except ERRORS as error:
        if expected not in str(error):
            raise AssertionError(f'{name}: rejected for another reason: {error}')
        controls.append(name)
        return
    raise AssertionError('registered gate record mutation accepted: ' + name)


def statement(candidate, role):
    return next(item for item in candidate['statements'] if item['role'] == role)


def text_swap(role, old, new):
    """Replace every occurrence, so that the criterion that reads the fragment no longer finds it."""
    def mutate(candidate):
        item = statement(candidate, role)
        assert item['text'].count(old) >= 1, (role, old)
        item['text'] = item['text'].replace(old, new)
    return mutate


def copy_product(target):
    """The files that metadata mode reads, at their relative paths."""
    paths = {v.VERIFIER_PATH, v.CONDITIONS_PATH, v.CHECKPOINT_PATH, *v.CROSS_RECORDS,
             *(row['path'] for row in checkpoint['modelIdentity']['sameAsProduct']),
             *(row['path'] for row in checkpoint['modelIdentity']['pinnedOnly'])}
    for relative in paths:
        (target / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target / relative)


def product_case(name, change, expected=None):
    with tempfile.TemporaryDirectory(prefix='registered-gate-controls-') as folder:
        target = Path(folder).resolve()
        copy_product(target)
        change(target)
        if expected is None:
            attempt(deepcopy(checkpoint), target, True)
            positives.append(name)
        else:
            rejected(name, lambda c: None, expected, keep_pin=True, product=target)


def edit_json(relative, mutate):
    def change(target):
        path = target / relative
        value = json.loads(path.read_text(encoding='utf-8'))
        mutate(value)
        path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8', newline='\n')
    return change


def edit_text(relative, old, new):
    def change(target):
        path = target / relative
        text = path.read_text(encoding='utf-8')
        assert text.count(old) >= 1, (relative, old)
        path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
    return change


CONTRACT, BOUNDARY, CRITERIA = 'Checkpoint contract differs', 'Public scope or boundary differs', 'Criteria do not follow'
COVERAGE, PRIVATE, ROLES = 'Coverage does not follow', 'Private or non-English metadata', 'Statement row differs'
for key in v.NONCLAIM_KEYS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False), 'nonclaims required')
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k), 'nonclaims required')
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-registered-gate-checkpoint-v2'), CONTRACT)
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_REGISTERED_CENTRAL_CLOSURE'), CONTRACT)
rejected('extra-key', lambda c: c.__setitem__('generalRuntimeLink', True), CONTRACT)
rejected('kept-pin', lambda c: c['coverage'].__setitem__('cells', 26), 'Reviewed evidence digest differs', keep_pin=True)
for key in v.PROSE_KEYS:
    rejected('changed-' + key, lambda c, k=key: c.__setitem__(k, c[k][:-1]), BOUNDARY)
rejected('process-label-in-scope', lambda c: c.__setitem__('scope', c['scope'] + ' See step E-' + '9.'),
         'Internal process label in prose')
rejected('private-path', lambda c: statement(c, 'gate-instance').__setitem__(
    'text', statement(c, 'gate-instance')['text'] + ' ' + chr(67) + ':' + chr(47) + 'Users'), PRIVATE)
rejected('internal-coordinate', lambda c: statement(c, 'gate-instance').__setitem__(
    'text', statement(c, 'gate-instance')['text'] + ' G' + '7'), PRIVATE)
rejected('home-relative-path', lambda c: statement(c, 'gate-instance').__setitem__(
    'text', statement(c, 'gate-instance')['text'] + ' ~' + '/Documents'), PRIVATE)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), PRIVATE)
rejected('em-dash', lambda c: c.__setitem__('scope', c['scope'] + ' a ' + chr(0x2014) + ' b'), PRIVATE)
rejected('retained-assumption-dropped', lambda c: c.__setitem__('retainedAssumptions', {}), 'Retained assumptions differ')
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64), 'Current verifier differs')
rejected('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'true'), 'Current verifier differs')
for criterion in v.CRITERIA:
    rejected('criterion-not-pass-' + criterion, lambda c, k=criterion: c['criteria'].__setitem__(k, 'FAIL'), CRITERIA)
rejected('criterion-removed', lambda c: c['criteria'].pop(v.CRITERIA[0]), CRITERIA)
rejected('gate-over-another-set', text_swap('gate-instance', 'e2_registry)', 'registry)'), CRITERIA)
rejected('removal-not-over-the-registry', text_swap('certificate-removal', ' - {certificate}', ''), CRITERIA)
rejected('registry-size-differs', text_swap('registry-size', '= 96', '= 95'), CRITERIA)
rejected('partition-over-another-set', text_swap('acceptance-partition', 'e2_registry', 'registry'), CRITERIA)
rejected('no-applied-witness', text_swap('enforced-cell-predicate', '= TRUST_Abstract_Applied) <and>', '= x) <and>'),
         CRITERIA)
rejected('no-checker-soundness', text_swap('gate-predicate', 'failure_report_checker_sound (failure_checkers profile)',
                                           'True'), CRITERIA)
rejected('checker-not-abi', text_swap('profile-checkers', '= abi_failure_checker', '= other_checker'), CRITERIA)
rejected('no-malformed-branch', text_swap('gate-predicate', 'e2_malformed_runtime_link_gate manifests', 'True'), CRITERIA)
rejected('no-code-pin', text_swap('hook-code-pins', 'account_code_at (transaction_pre execution)', 'True'), CRITERIA)
rejected('manifest-not-read-by-reader', text_swap('profile-manifests', 'psr_hook_manifest', 'other_manifest'), CRITERIA)
rejected('gate-outside-locale', lambda c: statement(c, 'gate-instance').__setitem__(
    'name', 'TRUST_Gate.' + statement(c, 'gate-instance')['name'].rpartition('.')[2]), CRITERIA)
rejected('locale-of-two-contexts', text_swap('gate-context', ' + ', ' '), CRITERIA)
rejected('cell-oracle-line', lambda c: c['audits'][0].__setitem__('line', c['audits'][0]['line'].replace(
    'cell_oracles=0', 'cell_oracles=1')), CRITERIA)
rejected('role-removed', lambda c: c['statements'].pop(0), 'Statement roles differ')
rejected('role-kind-changed', lambda c: c['statements'][0].__setitem__('kind', 'theorem'), ROLES)
rejected('role-session-changed', lambda c: c['statements'][0].__setitem__('session', 'session-gate-common'), ROLES)
rejected('role-text-emptied', lambda c: statement(c, 'gate-instance').__setitem__('text', ' '), ROLES)
rejected('unqualified-name', lambda c: statement(c, 'gate-instance').__setitem__('name', 'gate'), 'Statement name differs')
rejected('restated-cell-removed', lambda c: c['statements'].remove(next(
    item for item in c['statements'] if item['role'] == 'restated-cell')), 'Restated rows differ')
rejected('restated-execution-duplicated', lambda c: c['statements'].__setitem__(-1, deepcopy(c['statements'][-2])),
         'Restated rows differ')
rejected('restated-with-text', lambda c: c['statements'][-1].__setitem__('text', 'x'), 'Restated row differs')
rejected('audit-removed', lambda c: c['audits'].pop(), 'Final audit rows differ')
rejected('audit-without-names', lambda c: c['audits'][1].__setitem__('names', 0), 'Final audit rows differ')
rejected('registry-key-dropped', lambda c: c['registry']['keys'].pop(), 'Certificate keys differ from the registry record')
rejected('registry-key-renamed', lambda c: c['registry']['keys'].__setitem__(0, 'Native/FREEZE/other'),
         'Certificate keys differ from the registry record')
rejected('registry-hash-changed', lambda c: (c['registry'].__setitem__('sha256', 'a' * 64), next(
    row for row in c['artifacts'] if row['id'] == 'certificate-registry').__setitem__('sha256', 'a' * 64)),
         'Certificate registry hash differs from the registry record')
rejected('registry-artifact-split', lambda c: next(row for row in c['artifacts'] if row['id'] == 'certificate-registry')
         .__setitem__('sha256', 'b' * 64), 'Registry artifact differs')
rejected('coverage-inflated', lambda c: c['coverage']['registeredCertificates'].__setitem__('Native', 35), COVERAGE)
rejected('removals-inflated', lambda c: c['coverage']['certificateRemovals'].__setitem__('Hook', 32), COVERAGE)
rejected('oracle-dependencies-hidden', lambda c: c['coverage'].__setitem__('oracleDependencies', 1), COVERAGE)
rejected('quoted-criterion-changed', lambda c: c['evidenceFor'][0]['closureAcceptance'].__setitem__(1, 'A kernel run.'),
         'Quoted criteria differ from the conditions list')
rejected('supported-criterion-added', lambda c: c['evidenceFor'][0]['supported'].append(1),
         'Quoted criteria differ from the conditions list')
rejected('formal-theory-changed', lambda c: c['modelIdentity']['sameAsProduct'][0].__setitem__('sha256', '0' * 64),
         'Formal theory differs from the current product file')
rejected('pinned-theory-claimed-current', lambda c: c['modelIdentity']['pinnedOnly'][0].__setitem__(
    'sha256', v.digest(ROOT / c['modelIdentity']['pinnedOnly'][0]['path'])), 'Pinned formal theory row differs')
rejected('pinned-theory-other-model', lambda c: next(row for row in c['modelIdentity']['pinnedOnly'] if 'sameAs' in row)
         .__setitem__('sha256', 'c' * 64), 'Pinned formal theory differs')
rejected('anchor-changed', lambda c: next(row for row in c['artifacts'] if row['id'] == v.ANCHOR).__setitem__(
    'sha256', 'd' * 64), 'Anchor database differs from the aligned gate record')
rejected('shared-database-changed', lambda c: next(row for row in c['artifacts'] if row['id'] == 'session-reader-cells')
         .__setitem__('sha256', 'e' * 64), 'Shared session databases differ')
rejected('shared-source-changed', lambda c: next(source for row in c['kernelSessions'] for source in row['sources']
                                                 if 'sameAs' in source).__setitem__('sha256', 'f' * 64),
         'Shared source differs')
rejected('artifact-removed', lambda c: c['artifacts'].pop(), 'Artifact inventory differs')
rejected('artifact-kind-changed', lambda c: c['artifacts'][0].__setitem__('kind', 'registry'), 'Artifact inventory differs')
rejected('artifact-empty', lambda c: c['artifacts'][0].__setitem__('bytes', 0), 'Artifact inventory differs')
rejected('run-order-changed', lambda c: c['kernelRuns'].reverse(), 'Kernel runs do not cover the sessions in order')
rejected('session-moved-between-runs', lambda c: c['kernelRuns'][1]['sessions'].insert(
    0, c['kernelRuns'][0]['sessions'].pop()), 'Kernel session row differs')
rejected('run-id-changed', lambda c: c['kernelRuns'][0].__setitem__('id', 'x'), 'Kernel runs do not cover the sessions')
rejected('session-run-changed', lambda c: c['kernelSessions'][0].__setitem__('run', 'gate-instance-run'),
         'Kernel session row differs')
rejected('session-without-sources', lambda c: c['kernelSessions'][0].__setitem__('sources', []),
         'Kernel session row differs')
rejected('session-pass-count-text', lambda c: c['kernelSessions'][0].__setitem__('passMarkers', '1'),
         'Kernel session row differs')
rejected('session-removed', lambda c: c['kernelSessions'].pop(), 'Kernel session rows differ')
rejected('model-identity-key', lambda c: c['modelIdentity'].__setitem__('other', []), 'Model identity differs')

product_case('changed-condition', edit_text(v.CONDITIONS_PATH, 'Removing any registered certificate breaks',
                                            'Removing a registered certificate breaks'),
             'Quoted criteria differ from the conditions list')
product_case('registry-record-other-registry', edit_json(v.REGISTRY_RECORD, lambda r: next(
    row for row in r['artifacts'] if row['id'] == 'certificate-registry').__setitem__('sha256', '1' * 64)),
             'Certificate registry hash differs from the registry record')
product_case('registry-record-other-keys', edit_json(v.REGISTRY_RECORD, lambda r: r['certificates'][0].__setitem__(
    'key', 'Hook/OTHER/applied')), 'Certificate keys differ from the registry record')
product_case('reader-record-other-database', edit_json(v.READER_RECORD, lambda r: next(
    row for row in r['artifacts'] if row['id'] == 'session-reader-cells').__setitem__('sha256', '2' * 64)),
             'Shared session databases differ')
product_case('reader-record-other-manifest', edit_json(v.READER_RECORD, lambda r: r['cellStatements'].__setitem__(
    'hook', {key: 'other_manifest' for key in r['cellStatements']['hook']})), CRITERIA)
product_case('aligned-record-other-anchor', edit_json(v.ALIGNED_RECORD, lambda r: next(
    row for row in r['artifacts'] if row['id'] == 'hook-value-database').__setitem__('sha256', '3' * 64)),
             'Anchor database differs from the aligned gate record')
product_case('changed-formal-theory', edit_text(checkpoint['modelIdentity']['sameAsProduct'][0]['path'], '\n', '\n\n'),
             'Formal theory differs from the current product file')
product_case('changed-verifier-file', lambda target: (target / v.VERIFIER_PATH).write_bytes(
    (target / v.VERIFIER_PATH).read_bytes() + b'\n'), 'Current verifier differs')
product_case('unread-registry-member', edit_json(v.REGISTRY_RECORD, lambda r: r.__setitem__('scope', r['scope'] + ' x')))
product_case('unread-reader-member', edit_json(v.READER_RECORD, lambda r: r.__setitem__('scope', r['scope'] + ' x')))
product_case('unread-aligned-member', edit_json(v.ALIGNED_RECORD, lambda r: r.__setitem__('scope', r['scope'] + ' x')))
print(json.dumps({'status': 'PASS_PUBLIC_REGISTERED_GATE', 'positive': len(positives), 'negativeControls': len(controls),
                  'savedArtifactsVerified': False, 'proverRerun': False}, indent=2))
