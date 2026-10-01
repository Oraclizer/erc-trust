#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the captured-source checkpoint; saved-evidence rehash is not replay."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys

sys.dont_write_bytecode = True
import verify_received_valuation_current_v1 as saved

CHECKPOINT = 'evidence/trust12/runtime-link/native-full-source-admission-checkpoint-v1.json'
VERIFIER = 'scripts/trust12/verify_full_source_admission_v1.py'
INDEX = 'native-full-source-admission-artifact-index-v1.json'
SCHEMA = 'trust12-native-full-source-admission-checkpoint-v1'
EXPECTED_EVIDENCE_DIGEST = '82a8f1f2e05ee3936f34e41981791dbbb327cea50686023644060641c81d2b53'
CONFIRMED = ('rawSourceEOF', 'wholeTypedSubstitution', 'checkedEnvironment',
             'groundQueryInputIdentity', 'nativeGroundDefinedness', 'logicalWrapperTransport',
             'fullSourceObservationReceiver')
NONCLAIMS = ('crossKernelSemantics', 'producerImage', 'originalExecutionLaw',
             'generalRuntimeLinks', 'otherProfiles', 'centralRefinementClosure',
             'independentAssurance', 'fullTrustCompletion', 'releaseOrDeployment')
KERNEL_ROLES = ('source', 'root', 'binding', 'audit', 'inputs-before', 'inputs-after',
                'heap', 'database', 'parent-heap', 'parent-database')
NATIVE_ROLES = ('result', 'plan', 'inputs-before', 'inputs-after', 'runtime-before',
                'runtime-after', 'query', 'utility-result', 'raw', 'converted', 'export', 'ground')
GT = {'tag': 'SortApp', 'name': 'SortGeneratedTopCell', 'args': []}
TOP = {'tag': 'Top', 'sort': GT}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False).encode('utf-8')


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != 'rehashVerifier'})).hexdigest()


def public_contract(checkpoint, product):
    saved.require(checkpoint.get('schema') == SCHEMA and checkpoint.get('status') == 'PASS_SAVED_CAPTURED_SOURCE_ADMISSION',
                  'checkpoint schema or status differs')
    saved.require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, 'reviewed evidence digest differs')
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    saved.require(encoded.isascii() and not saved.PRIVATE.search(encoded), 'private or non-English checkpoint metadata')
    saved.require(checkpoint['confirmed'] == {key: True for key in CONFIRMED}
                  and checkpoint['claims'] == {key: False for key in NONCLAIMS}, 'checkpoint claim scope differs')
    verifier = checkpoint['rehashVerifier']
    saved.require(verifier['path'] == VERIFIER and verifier['sha256'] == saved.digest(product / VERIFIER)
                  and verifier['bytes'] == (product / VERIFIER).stat().st_size, 'current rehash verifier differs')
    for item in checkpoint['productIdentity'].values():
        path = saved.relative_file(product, item['path'])
        saved.require(path.stat().st_size == item['bytes'] and saved.digest(path) == item['sha256'], 'current product input differs')
    rows = checkpoint['artifacts']
    saved.require(rows and len({row['id'] for row in rows}) == len(rows), 'empty or duplicate artifact inventory')
    for row in rows:
        saved.require(type(row['bytes']) is int and row['bytes'] > 0 and re.fullmatch('[0-9a-f]{64}', row['sha256']),
                      'invalid artifact identity')
    return {row['id']: row for row in rows}


def verify_saved(checkpoint, index, base, product, zstd):
    records = public_contract(checkpoint, product)
    saved.require(set(index) == set(records), 'private locator inventory differs')
    files = {key: saved.relative_file(base, value) for key, value in index.items()}
    for key, file in files.items():
        saved.require(file.stat().st_size == records[key]['bytes'] and saved.digest(file) == records[key]['sha256'],
                      'saved artifact identity differs: ' + key)
    checked = {}
    for item in checkpoint['kernelStages']:
        prefix = item['id'] + '-'
        roles = {role: files[prefix + role] for role in KERNEL_ROLES}
        target, parent, theory = saved.root_identity(roles['root'].read_text(encoding='utf-8-sig'))
        saved.require((target, parent, theory) == (item['session'], item['parent'], item['theory']), 'registered kernel stage differs')
        binding = saved.read_json(roles['binding'])
        audit = saved.read_json(roles['audit'])
        saved.require(binding['parent'] == parent and binding['roots'] == item['roots']
                      and audit['roots'] == item['roots'] and audit['session'] == target and audit['parent'] == parent,
                      'exact kernel roots or parent differs')
        saved.require(binding['sourceSha256'] == audit['sourceSha256'] == saved.digest(roles['source'])
                      and binding['rootSha256'] == saved.digest(roles['root']), 'bound kernel source differs')
        saved.require(audit['status'] == 'PASS_ACTUAL_TOKEN_IDENTITY_STAGE_SAVED_KERNEL_AUDITED'
                      and audit['storedSourceByteExact'] and audit['primaryParentLineageMatches'] and audit['inputsUnchanged']
                      and audit['oracleDependencies'] == 0 and audit['skipProofs'] is False
                      and audit['sourceTimeoutSeconds'] == 120 and audit['timeoutScale'] == 1 and audit['heapMiB'] == 2048,
                      'kernel completion, oracle, or execution profile differs')
        saved.require(audit['heapSha256'] == saved.digest(roles['heap'])
                      and audit['databaseSha256'] == saved.digest(roles['database']), 'audited saved outputs differ')
        inputs, output = saved.database_heap_info(roles['database'], target)
        _, parent_output = saved.database_heap_info(roles['parent-database'], parent)
        saved.require(output == saved.heap_identity(roles['heap'])
                      and inputs.get(parent) == parent_output == saved.heap_identity(roles['parent-heap']), 'saved heap lineage differs')
        saved.saved_source(roles['database'], target, roles['source'], zstd)
        messages = saved.database_messages(roles['database'], zstd, target, theory)
        saved.require(messages.count(item['marker']) == 1 and 'error_message' not in messages, 'saved oracle guard absent or ambiguous')
        for marker in item['additionalMarkers']:
            saved.require(messages.count(marker) == 1, 'additional consumer guard absent or ambiguous')
        before = saved.read_json(roles['inputs-before'], False)
        saved.require(before == saved.read_json(roles['inputs-after'], False)
                      and len({row['path'] for row in before}) == len(before) == audit['currentInputsRehashed'], 'run snapshot differs')
        for row in before:
            path = Path(row['path']).resolve()
            saved.require(path.is_file() and (path not in checked or checked[path] == row['sha256']), 'missing or conflicting current input')
            if path not in checked:
                saved.require(saved.digest(path) == row['sha256'], 'current input drift')
                checked[path] = row['sha256']
    for item in checkpoint['nativeQueries']:
        roles = {role: files[item['id'] + '-' + role] for role in NATIVE_ROLES}
        receipt = saved.read_json(roles['result'])
        detail = saved.read_json(roles['utility-result'])
        query = saved.read_json(roles['query'])
        plan = saved.read_json(roles['plan'])
        raw, converted = saved.read_json(roles['raw']), saved.read_json(roles['converted'])
        ground = saved.read_json(roles['ground'])
        saved.require(receipt['status'] == 'PASS_NATIVE_WHOLE_SOURCE_CEIL_ONLY'
                      and receipt['variant'] == item['variant'] and receipt['exitCode'] == 0 and receipt['nativeProofAccepted']
                      and receipt['cleanup']['confirmed'] and receipt['inputsUnchanged'] and receipt['runtimeUnchanged']
                      and receipt['sdkExactRoundtrip'] and receipt['assumeDefined'] is False
                      and receipt['operationalExecutionDischarged'] is False and receipt['generalCredit'] is False,
                      'whole-source native query was not accepted in the declared scope')
        saved.require(raw['status'] == 'valid' and converted['valid'] is True
                      and converted['predicate'] == converted['substitution'] == TOP, 'native query is invalid or residual')
        saved.require(query == plan['expectedQuery'] and saved.digest(roles['plan']) == receipt['planSha256']
                      and query['assumeDefined'] is False and query['freeVariables'] == [], 'actual native query differs')
        saved.require(query['predicateKore']['left'] == {'tag': 'Ceil', 'argSort': GT, 'sort': GT, 'arg': ground}
                      and query['predicateKore']['right'] == {'tag': item['ceilingResult'], 'sort': GT}
                      and query['predicateKore']['guard'] == TOP, 'native source or requested ceiling result differs')
        saved.require(detail['status'] == 'PREDICATE_PROVED' and detail['assumeDefined'] is False
                      and detail['baselineBefore'] == detail['baselineAfter'] == plan['expectedBaseline'], 'native utility baseline or result differs')
        for role, field in [('query', 'querySha256'), ('raw', 'rpcRawResultSha256'), ('converted', 'rpcResultSha256')]:
            saved.require(saved.digest(roles[role]) == detail[field], 'native utility artifact differs')
        saved.require(saved.digest(roles['ground']) == plan['groundSourceSha256']
                      and saved.digest(roles['export']) == plan['expectedExportSha256'] == detail['derivedModule']['sha256']
                      and detail['derivedModule']['registeredByThisTool'] is False, 'native ground or unregistered export differs')
        saved.require(saved.read_json(roles['inputs-before'], False) == saved.read_json(roles['inputs-after'], False)
                      and saved.read_json(roles['runtime-before']) == saved.read_json(roles['runtime-after']), 'native custody snapshots differ')
    return {'status': 'PASS_SAVED_CAPTURED_SOURCE_ADMISSION_REHASHED', 'savedArtifactsRehashed': len(files),
            'currentInputsRehashed': len(checked), 'kernelStages': len(checkpoint['kernelStages']),
            'nativeQueries': len(checkpoint['nativeQueries']), 'freshKernelReplay': False,
            'claims': {key: False for key in NONCLAIMS}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--metadata-only', action='store_true')
    parser.add_argument('--base', type=Path)
    parser.add_argument('--artifact-index', type=Path)
    parser.add_argument('--zstd', default='zstd')
    args = parser.parse_args()
    product = args.product_root.resolve()
    checkpoint = saved.read_json(product / CHECKPOINT)
    if args.metadata_only:
        saved.require(args.base is None and args.artifact_index is None, 'metadata-only mode cannot assert saved-artifact verification')
        public_contract(checkpoint, product)
        report = {'status': 'PASS_PUBLIC_METADATA_ONLY', 'savedArtifactsVerified': False,
                  'freshKernelReplay': False, 'claims': {key: False for key in NONCLAIMS}}
    else:
        saved.require(args.base is not None and args.artifact_index is not None, 'saved-artifact verification requires base and locator')
        base = args.base.resolve()
        saved.require(args.artifact_index.resolve().parent == base and args.artifact_index.name == INDEX, 'unexpected private locator')
        report = verify_saved(checkpoint, saved.read_json(args.artifact_index), base, product, args.zstd)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, sqlite3.Error):
        raise SystemExit('FAIL_CAPTURED_SOURCE_ADMISSION: evidence rejected')
