#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the public reflection scan record boundary without reading the stored build information or report.

Record controls change one field of the record and re-pin the reviewed digest in memory, so that only the semantic
check named for each control can reject it; one control keeps the pin. Product controls change one tracked input in
a copy of the files that metadata mode reads (one of them also names the changed source in the record copy, so that
only the inline assembly check can reject it); three positive controls, among them two that change only ledger
members the scan does not read, must pass.
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
spec = importlib.util.spec_from_file_location('reflection_scan_record_tests',
                                              ROOT / 'scripts/trust12/verify_reflection_scan_v1.py')
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
    raise AssertionError('reflection scan record mutation accepted: ' + name)


def endpoint(candidate, name):
    return candidate['endpoints'][name]


def variable(candidate, name, label):
    return next(item for item in endpoint(candidate, name)['variables'] if item['label'] == label)


def guard(candidate, name, function, kind=None):
    return next(item for item in endpoint(candidate, name)['guards']
                if item['function'] == function and (kind is None or item['class'] == kind))


def storage(candidate, runtime, label):
    return next(item for item in candidate['storageDispositions'] if item['runtime'] == runtime and item['label'] == label)


NATIVE, PARTIAL, HOOK = v.ENDPOINT_NAMES
CONTRACT, BOUNDARY, COVERAGE = 'Checkpoint contract differs', 'Public scope or boundary differs', 'Coverage differs'
for key in v.NONCLAIM_KEYS:
    rejected('false-promotion-' + key, lambda c, k=key: c['nonclaims'].__setitem__(k, False), 'nonclaims required')
    rejected('removed-nonclaim-' + key, lambda c, k=key: c['nonclaims'].pop(k), 'nonclaims required')
rejected('changed-schema', lambda c: c.__setitem__('schema', 'trust12-reflection-scan-checkpoint-v2'), CONTRACT)
rejected('changed-status', lambda c: c.__setitem__('status', 'PASS_PRESERVATION_AND_REFLECTION_CLOSED'), CONTRACT)
rejected('extra-key', lambda c: c.__setitem__('guardsProven', True), CONTRACT)
rejected('changed-scope', lambda c: c.__setitem__('scope', c['scope'].replace(
    'No write or guard is unclassified', 'Every guard is sound')), BOUNDARY)
rejected('compiler-checks-listed', lambda c: c.__setitem__('pathBoundary', c['pathBoundary'].replace(
    'are not source guards and are not listed', 'are listed')), BOUNDARY)
rejected('discovered-callbacks', lambda c: c.__setitem__('pathBoundary', c['pathBoundary'].replace(
    'are declared in the scan tool, not discovered by it', 'are discovered by the scan')), BOUNDARY)
rejected('weakened-classification-boundary', lambda c: c.__setitem__('classificationBoundary', c[
    'classificationBoundary'].replace('A classification does not prove', 'A classification proves')), BOUNDARY)
rejected('hidden-reversal-negatives', lambda c: c.__setitem__('reversalCheckBoundary', c['reversalCheckBoundary'].replace(
    ', and no removal negative targets a domain or identifier check of a reversal request', '')), BOUNDARY)
rejected('weakened-condition-boundary', lambda c: c.__setitem__('conditionBoundary', c['conditionBoundary'].replace(
    'this record does not address that part', 'this record closes that part')), BOUNDARY)
rejected('changed-reproduction-boundary', lambda c: c.__setitem__('reproductionBoundary', c['reproductionBoundary'] + ' x'),
         BOUNDARY)
rejected('inflated-guard-coverage', lambda c: c['coverage']['endpoints'][NATIVE]['guards'].__setitem__(
    'LEDGER_CONSUMER', 40), COVERAGE)
rejected('changed-layout-count', lambda c: c['coverage']['compiledLayoutVariables'].__setitem__('ProfileGovernor', 3),
         COVERAGE)
rejected('nonzero-problems', lambda c: c['coverage'].__setitem__('problems', 1), COVERAGE)
rejected('pending-review', lambda c: c['coverage'].__setitem__('reviewPending', 1), COVERAGE)
rejected('invalid-artifact-hash', lambda c: c['artifacts'][0].__setitem__('sha256', 'not-a-hash'), 'Artifact inventory')
rejected('changed-artifact-kind', lambda c: c['artifacts'][1].__setitem__('kind', 'inventory'), 'Artifact inventory')
rejected('removed-artifact', lambda c: c['artifacts'].pop(), 'Artifact inventory')
rejected('shared-artifact-hash', lambda c: c['artifacts'][1].__setitem__('sha256', c['artifacts'][0]['sha256']),
         'Artifact inventory')
rejected('changed-verifier', lambda c: c['rehashVerifier'].__setitem__('sha256', '0' * 64), 'Current verifier differs')
rejected('moved-verifier', lambda c: c['rehashVerifier'].__setitem__('path', 'scripts/verify.py'), 'Current verifier differs')
rejected('changed-command', lambda c: c['rehashVerifier'].__setitem__('command', 'python3 verify.py'),
         'Current verifier differs')
for key in v.IDENTITY_PATHS:
    rejected('changed-product-' + key, lambda c, k=key: c['productIdentity'][k].__setitem__('sha256', '0' * 64),
             'Product identity differs')
rejected('removed-implementation-source', lambda c: c['implementationSources'].pop(), 'Implementation sources differ')
rejected('changed-implementation-source', lambda c: c['implementationSources'][0].__setitem__('sha256', '0' * 64),
         'Implementation sources differ')
rejected('changed-central-members', lambda c: c['ledgerMembers']['central'].__setitem__('sha256', '0' * 64),
         'Ledger members differ')
rejected('changed-profile-members', lambda c: c['ledgerMembers']['trust12'].__setitem__('sha256', '0' * 64),
         'Ledger members differ')
rejected('changed-compiler-version', lambda c: c['compiler'].__setitem__('solcVersion', '0.8.35'), 'Compiler record differs')
rejected('changed-acceptance', lambda c: c['evidenceFor']['closureAcceptance'].__setitem__(1, 'Reviewed by hand.'),
         'Condition text differs')
rejected('changed-finding', lambda c: c['evidenceFor']['finding'].__setitem__('id', 'no-formal-storage-reader'),
         'Condition text differs')
rejected('extra-endpoint-key', lambda c: endpoint(c, NATIVE).__setitem__('callees', []), 'Endpoint rows differ')
rejected('reordered-endpoints', lambda c: c.__setitem__('endpoints', dict(reversed(list(c['endpoints'].items())))),
         'Endpoint rows differ')
rejected('disposed-variable-as-field', lambda c: variable(c, NATIVE, '_pendingCommitments').update(
    {'class': 'ABSTRACT_FIELD', 'column': 'BOUND_BY_CENTRAL_LEDGER'}), 'Variable row differs')
rejected('runtime-only-variable-as-disposed', lambda c: variable(c, PARTIAL, '_entered').__setitem__(
    'class', 'RUNTIME_ONLY_BY_DISPOSITION'), 'Variable row differs')
rejected('derived-column-as-bound', lambda c: variable(c, HOOK, '_owned').__setitem__('column', 'BOUND_BY_CENTRAL_LEDGER'),
         'Variable row differs')
rejected('unclassified-variable', lambda c: variable(c, HOOK, '_receipts').update({'class': 'UNCLASSIFIED', 'column': None}),
         'Variable row differs')
rejected('writerless-variable', lambda c: variable(c, NATIVE, '_balances').__setitem__('writers', []),
         'Variable row differs')
rejected('removed-variable', lambda c: endpoint(c, NATIVE)['variables'].remove(variable(c, NATIVE, '_routeTicket')),
         'Coverage does not follow from the rows')
rejected('unclassified-guard', lambda c: guard(c, NATIVE, '_move').__setitem__('class', 'UNCLASSIFIED'), 'Guard row differs')
rejected('unknown-ledger-row', lambda c: guard(c, PARTIAL, '_validateAndAuthorizeAction', 'LEDGER_CONSUMER').__setitem__(
    'rows', ['ADP-NOPE-99']), 'Guard row differs')
rejected('consumer-in-profile-ledger', lambda c: guard(c, PARTIAL, '_validateAndAuthorizeAction',
                                                       'LEDGER_CONSUMER').__setitem__('ledger', 'trust12'),
         'Guard row differs')
rejected('disposition-rows-swapped', lambda c: guard(c, NATIVE, 'forcedTransfer').__setitem__('rows', ['NAT-REV-02']),
         'Guard row differs')
rejected('runtime-only-guard-with-rows', lambda c: guard(c, NATIVE, 'nonReentrant').update(
    {'class': 'LEDGER_CONSUMER_BY_DISPOSITION', 'ledger': 'central', 'rows': ['NAT-ROUTE-01']}), 'Guard row differs')
rejected('consumer-guard-as-runtime-only', lambda c: guard(c, PARTIAL, '_validateAndAuthorizeAction',
                                                           'LEDGER_CONSUMER').update(
    {'class': 'RUNTIME_ONLY_BY_DISPOSITION', 'ledger': None, 'rows': []}), 'Guard row differs')
rejected('native-same-body', lambda c: guard(c, NATIVE, '_move').__setitem__('sameBodyAs', 'ERC3643TrustAdapter'),
         'Guard row differs')
rejected('unsorted-guard-rows', lambda c: guard(c, NATIVE, '_bubble').__setitem__('rows', ['NAT-ROUTE-01', 'NAT-FAIL-01']),
         'Guard row differs')
rejected('removed-guard', lambda c: endpoint(c, HOOK)['guards'].pop(), 'Coverage does not follow from the rows')
rejected('reordered-entries', lambda c: endpoint(c, NATIVE)['entries'].reverse(), 'Endpoint entries differ')
rejected('removed-reentry', lambda c: endpoint(c, HOOK)['reentries'].pop(), 'Endpoint entries differ')
rejected('changed-storage-reason', lambda c: storage(c, 'TrustToken', '_pendingCommitments').__setitem__(
    'reason', 'Runtime state.'), 'Storage disposition rows differ')
rejected('changed-storage-writers', lambda c: storage(c, 'ProfileGovernor', 'topologySealed').__setitem__(
    'writtenBy', ['seal', 'unseal']), 'Storage disposition rows differ')
rejected('changed-storage-slot', lambda c: storage(c, 'ERC3643HookCompliance', 'bound').__setitem__('slot', 1),
         'Storage disposition rows differ')
rejected('changed-storage-rows', lambda c: storage(c, 'ERC3643HookGovernor', 'sealedBinding').__setitem__(
    'rows', ['HOOK-CALLER-AUTH']), 'Storage disposition rows differ')
rejected('removed-storage-row', lambda c: c['storageDispositions'].pop(), 'Coverage does not follow from the rows')
rejected('reader-item-resolved', lambda c: c['openItems'][0].__setitem__('disposition', 'RESOLVED_BY_SCAN'),
         'Open item dispositions differ')
rejected('removed-open-item', lambda c: c['openItems'].pop(), 'Coverage does not follow from the rows')
rejected('changed-hook-writers', lambda c: c.__setitem__('hookColumnWritersWithOwnText', ['_activateSeal', '_bind']),
         'Hook writer dispositions differ')
rejected('reviewed-digest-pin', lambda c: guard(c, NATIVE, '_move').__setitem__('line', 1), 'Reviewed evidence digest differs',
         keep_pin=True)
privacy = v.privacy_boundary
rejected('private-path', lambda c: c.__setitem__('scope', 'see ' + chr(67) + ':' + chr(47) + 'Users'), 'Private',
         check=privacy)
rejected('home-path', lambda c: c.__setitem__('scope', 'see ' + chr(47) + 'ho' + 'me' + chr(47) + 'user'), 'Private',
         check=privacy)
rejected('internal-coordinate', lambda c: c.__setitem__('scope', 'stage G' + '7'), 'Private', check=privacy)
rejected('lowercase-step-suffix', lambda c: c.__setitem__('scope', 'stage rl' + '20'), 'Private', check=privacy)
rejected('non-english-text', lambda c: c.__setitem__('scope', c['scope'] + ' ' + chr(0xAC00)), 'Private', check=privacy)
rejected('em-dash', lambda c: c.__setitem__('scope', 'a ' + chr(0x2014) + ' b'), 'Private', check=privacy)

# Product controls on a copy of every file that metadata mode reads.
copy = Path(tempfile.mkdtemp(prefix='reflection-scan-controls-')).resolve()
try:
    for relative in v.metadata_inputs(ROOT):
        (copy / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, copy / relative)
    v.public_contract(checkpoint, copy)
    positives.append('unchanged-copy')

    def product_change(name, relative, edit, expected=None, rebind=False):
        """Change one copied file; with rebind, the record copy also names the changed source by its new hash."""
        path = copy / relative
        original = path.read_bytes() if path.exists() else None
        try:
            edit(path)
            if expected is None:
                v.public_contract(checkpoint, copy)
                positives.append(name)
            else:
                def mutate(candidate):
                    if rebind:
                        row = next(item for item in candidate['implementationSources'] if item['path'] == relative)
                        row.update(v.file_identity(copy, relative))
                rejected(name, mutate, expected, product=copy)
        finally:
            if original is None:
                path.unlink()
            else:
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

    def first_row(document, key='rows'):
        return document[key][0]

    def native_consumer(document):
        row = next(item for item in document['rows'] for consumer in item['finalSourceConsumers']
                   if consumer.get('path') == 'implementation/src/TrustToken.sol')
        consumer = next(item for item in row['finalSourceConsumers'] if item.get('path') == 'implementation/src/TrustToken.sol')
        consumer['snippet'] += ' '

    def closure_row(document):
        return next(item for item in document['obligations'] if item['id'] == 'REGISTERED-CENTRAL-CLOSURE')

    product_change('central-unread-member', v.LEDGER_PATHS['central'],
                   edit_json(lambda d: first_row(d).__setitem__('title', first_row(d)['title'] + ' (edited)')))
    product_change('profile-unread-member', v.LEDGER_PATHS['trust12'],
                   edit_json(lambda d: closure_row(d).setdefault('supplementalEvidence', []).append('evidence/x.json')))
    product_change('changed-scan-tool', v.IDENTITY_PATHS['scanTool'], append('\n# edited\n'), 'Product identity differs')
    product_change('changed-dispositions', v.IDENTITY_PATHS['dispositions'],
                   edit_json(lambda d: d['storage'][0].__setitem__('reason', 'Runtime state.')), 'Product identity differs')
    product_change('changed-crosswalk', v.IDENTITY_PATHS['crosswalk'], append(' '), 'Product identity differs')
    product_change('changed-consumer-snippet', v.LEDGER_PATHS['central'], edit_json(native_consumer), 'Ledger members differ')
    product_change('removed-assumption', v.LEDGER_PATHS['central'], edit_json(lambda d: d['assumptions'].pop()),
                   'Ledger members differ')
    product_change('renamed-obligation', v.LEDGER_PATHS['trust12'],
                   edit_json(lambda d: d['obligations'][0].__setitem__('id', 'HOOK-RENAMED')), 'Ledger members differ')
    product_change('changed-implementation-source', 'implementation/src/TrustToken.sol', append('\n'),
                   'Implementation sources differ')
    product_change('assembly-storage-write', 'implementation/src/TrustToken.sol',
                   append('\n// assembly { sstore(0, 1) }\n'), 'inline assembly storage write', rebind=True)
    product_change('added-implementation-source', 'implementation/src/Extra.sol',
                   lambda path: path.write_text('// SPDX-License-Identifier: BSD-3-Clause\n', encoding='utf-8'),
                   'Implementation sources differ')
    product_change('changed-compiler-declaration', v.COMPILER_FILE,
                   replace('solc_version = "0.8.36"', 'solc_version = "0.8.35"'), 'Compiler declaration differs')
    product_change('changed-acceptance-text', v.CONDITIONS_PATH,
                   replace('not by review alone.', 'or by review.'), 'Condition text differs')
finally:
    shutil.rmtree(copy, ignore_errors=True)
print(json.dumps({'status': 'PASS_PUBLIC_REFLECTION_SCAN', 'positive': len(positives),
                  'negativeControls': len(controls), 'scanRerun': False}, indent=2))
