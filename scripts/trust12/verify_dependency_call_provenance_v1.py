#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify saved dependency-call field reception, raw input reception and the proper meaning of the thirteen original conditions without claiming whole engine semantics."""
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
import verify_model_source_reception_v1 as source_reader

CHECKPOINT = 'evidence/trust12/runtime-link/dependency-call-provenance-checkpoint-v1.json'
VERIFIER = 'scripts/trust12/verify_dependency_call_provenance_v1.py'
INDEX = 'dependency-call-provenance-artifact-index-v1.json'
SCHEMA = 'trust12-dependency-call-provenance-checkpoint-v1'
EXPECTED_EVIDENCE_DIGEST = '1b5450534e59704831532a8b1c5786088ef0a0dfc673d398989404ca3a546127'
CONFIRMED = ('assessCallTargetAndSelectorReceived','originalThirteenConditionsHookGatedMeaning',
             'configurationCalldataRawAndPayloadControls','configurationFrameFromExactPrefixReplay',
             'assessInputRawLexedParsedTypedAndEndOfInput','allDependencyCallFieldsFromRawTexts')
NONCLAIMS = ('standardEngineSemanticEquivalence','wholeConfigurationMeaningAndProducerImage',
             'summaryApplicationStepReplay','operationalCallListShapeAndOrderProvenance',
             'generalRuntimeLinks','centralRefinementClosure','independentAssurance',
             'fullTrustCompletion','releaseOrDeployment')
ROLES = ('source','root','binding','audit','inputs-before','inputs-after','heap','database',
         'parent-heap','parent-database','build-command','dryrun-command','hierarchy-receipt','scala-source','native-plan','build-log')
STAGE_COUNTS = {'assess-call-fields':27,'k13-proper-meaning':104,'dependency-call-payload':31,
                'config-call-frame':27,'assess-input-raw-reception':594,'assess-input-fields':51}


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('utf-8')


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key:value for key,value in checkpoint.items() if key!='rehashVerifier'})).hexdigest()


def public_contract(checkpoint,product):
    saved.require(checkpoint.get('schema')==SCHEMA and checkpoint.get('status')=='PASS_SAVED_DEPENDENCY_CALL_PROVENANCE',
                  'checkpoint schema or status differs')
    saved.require(payload_digest(checkpoint)==EXPECTED_EVIDENCE_DIGEST,'reviewed evidence digest differs')
    encoded=json.dumps(checkpoint,ensure_ascii=False)
    saved.require(encoded.isascii() and not saved.PRIVATE.search(encoded),'private or non-English metadata')
    saved.require(checkpoint['confirmed']=={key:True for key in CONFIRMED}
                  and checkpoint['claims']=={key:False for key in NONCLAIMS},'claim boundary differs')
    reader=checkpoint['rehashVerifier']
    saved.require(reader['path']==VERIFIER and reader['sha256']==saved.digest(product/VERIFIER)
                  and reader['bytes']==(product/VERIFIER).stat().st_size,'current verifier differs')
    for row in checkpoint['productIdentity'].values():
        path=saved.relative_file(product,row['path'])
        saved.require(path.stat().st_size==row['bytes'] and saved.digest(path)==row['sha256'],'current product input differs')
    stages=checkpoint['kernelStages']
    saved.require(len(stages)==len(STAGE_COUNTS) and {row['id']:len(row['roots']) for row in stages}==STAGE_COUNTS,
                  'complete stage and root inventory required')
    saved.require(sum(len(row['roots']) for row in stages)==834
                  and checkpoint['coverage']=={'kernelStages':6,'explicitRoots':834},'coverage differs')
    ids={row['id'] for row in stages}
    saved.require(len(ids)==6 and all(row['roots'] and len(row['roots'])==len(set(row['roots'])) for row in stages),
                  'empty or duplicate roots')
    rows=checkpoint['artifacts']
    expected={identifier+'-'+role for identifier in ids for role in ROLES}
    saved.require(len(rows)==len(expected) and {row['id'] for row in rows}==expected,'artifact roles differ')
    for row in rows:
        saved.require(type(row['bytes']) is int and row['bytes']>0 and re.fullmatch('[0-9a-f]{64}',row['sha256']),
                      'invalid artifact identity')
    return {row['id']:row for row in rows}


def hierarchy_receipt(path,audit):
    receipt=saved.read_json(path)
    bound=audit['exactHierarchyTransport']
    saved.require(saved.digest(path)==bound['receiptSha256'] and receipt['status']=='PASS_COMPACT_POLY_HIERARCHY'
                  and receipt['polyExitCode']==0 and receipt['hashesEqual'] is True,'exact hierarchy transport failed')
    for key in ('expressionBytes','expressionSha256','fileSha256','originalArgCount','forwardedArgCount'):
        saved.require(receipt[key]==bound[key],'hierarchy receipt binding differs')
    saved.require(receipt['expressionBytes']==receipt['fileBytes']
                  and receipt['expressionSha256']==receipt['fileSha256']
                  and receipt['originalArgCount']==receipt['forwardedArgCount']==18,'hierarchy bytes or argument order differs')
    saved.require(receipt['policySha256']==bound['policySha256'],'hierarchy policy differs')


def verify_saved(checkpoint,index,base,product,zstd):
    records=public_contract(checkpoint,product)
    saved.require(set(index)==set(records),'private locator inventory differs')
    files={key:saved.relative_file(base,value) for key,value in index.items()}
    for key,path in files.items():
        saved.require(path.stat().st_size==records[key]['bytes'] and saved.digest(path)==records[key]['sha256'],
                      'saved artifact differs: '+key)
    checked={}
    sessions=set()
    for row in checkpoint['kernelStages']:
        roles={role:files[row['id']+'-'+role] for role in ROLES}
        target,parent,theory=saved.root_identity(roles['root'].read_text(encoding='utf-8-sig'))
        saved.require((target,parent,theory)==(row['session'],row['parent'],row['theory']) and target not in sessions,
                      'registered stage or session uniqueness differs')
        sessions.add(target)
        binding,audit=saved.read_json(roles['binding']),saved.read_json(roles['audit'])
        saved.require(binding['parent']==parent and binding['roots']==audit['roots']==row['roots']
                      and audit['session']==target and audit['parent']==parent,'exact roots or parent differs')
        saved.require(binding.get('importedSources',[])==audit.get('importedSources',[])==[],
                      'unexpected imported-source inventory')
        saved.require(binding['sourceSha256']==audit['sourceSha256']==saved.digest(roles['source'])
                      and binding['rootSha256']==saved.digest(roles['root']),'bound source differs')
        saved.require(audit['status']=='PASS_ACTUAL_TOKEN_IDENTITY_STAGE_SAVED_KERNEL_AUDITED'
                      and audit['storedSourceByteExact'] is True and audit['primaryParentLineageMatches'] is True
                      and audit['inputsUnchanged'] is True and audit['oracleDependencies']==0 and audit['skipProofs'] is False
                      and audit['sourceTimeoutSeconds']==120 and audit['timeoutScale']==1
                      and audit['effectiveMLBuildTimeoutSeconds']==120 and audit['heapMiB']==2048,'saved completion differs')
        saved.require(audit['scope']==binding['scope']==row['scope'],'saved scope differs')
        planning=audit['singleAnalysisPlanningReceipt']
        saved.require(audit['separateDryRunExecuted'] is False and audit['dryRunSeconds'] is None
                      and binding['separateDryRunExecuted'] is False
                      and planning['status']=='PASS_SINGLE_ANALYSIS_EXACT_TARGET_SAVED'
                      and planning['launchedSession']==target and planning['launchCount']==1,
                      'single native analysis/exact target planning differs')
        log=roles['build-log'].read_text(encoding='utf-8',errors='strict')
        saved.require(re.findall(r'(?m)^Building (\S+) \.\.\.',log)==[target]
                      and re.findall(r'(?m)^Finished (\S+) \(',log)==[target],
                      'actual completed launch set differs')
        traces=[json.loads(text) for text in re.findall(r'(?m)^TRUST12_PROBE_RESULT (.+)$',log)]
        saved.require(traces==[planning],'actual single-analysis receipt differs')

        saved.require(audit['heapSha256']==saved.digest(roles['heap'])
                      and audit['databaseSha256']==saved.digest(roles['database']),'saved outputs differ')
        ancestors,output=saved.database_heap_info(roles['database'],target)
        _,parent_output=saved.database_heap_info(roles['parent-database'],parent)
        saved.require(output==saved.heap_identity(roles['heap'])
                      and ancestors.get(parent)==parent_output==saved.heap_identity(roles['parent-heap']),'heap lineage differs')
        saved.saved_source(roles['database'],target,roles['source'],zstd)
        messages=source_reader.source_messages(roles['database'],target,theory,[],zstd)
        saved.require(messages.count(row['marker'])==1,'complete oracle guard absent or ambiguous')
        actual_roots=re.findall(r'(?m)^(?:lemma|theorem|corollary)\s+(\w+)',roles['source'].read_text(encoding='utf-8-sig'))
        saved.require(actual_roots==row['roots'],'source declaration inventory differs')
        guarded=re.findall(r'val names = \[([^\]]*)\];',roles['source'].read_text(encoding='utf-8-sig'))
        guarded_names=re.findall(r'"([^"]+)"',guarded[0]) if len(guarded)==1 else []
        saved.require(len(guarded)==1 and [name.split('.',1)[-1] for name in guarded_names]==row['roots']
                      and all(name.split('.',1)[0]==theory for name in guarded_names),
                      'guarded root inventory differs')
        saved.require(row['hierarchyTransportRequired'] is True,'exact hierarchy transport is required')
        hierarchy_receipt(roles['hierarchy-receipt'],audit)
        before=saved.read_json(roles['inputs-before'],False)
        saved.require(before and before==saved.read_json(roles['inputs-after'],False)
                      and len({item['path'] for item in before})==len(before)==audit['currentInputsRehashed'],
                      'input snapshot differs')
        for item in before:
            path=Path(item['path']).resolve()
            saved.require(path.is_file() and (path not in checked or checked[path]==item['sha256']),
                          'missing or conflicting current input')
            if path not in checked:
                saved.require(saved.digest(path)==item['sha256'],'current proof input drift')
                checked[path]=item['sha256']
    return {'status':'PASS_SAVED_DEPENDENCY_CALL_PROVENANCE_REHASHED','kernelStages':6,
            'explicitRoots':834,'savedArtifactsRehashed':len(files),'currentInputsRehashed':len(checked),
            'freshKernelReplay':False,'claims':{key:False for key in NONCLAIMS}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product-root',type=Path,default=Path(__file__).resolve().parents[2])
    parser.add_argument('--metadata-only',action='store_true')
    parser.add_argument('--base',type=Path)
    parser.add_argument('--artifact-index',type=Path)
    parser.add_argument('--zstd',default='zstd')
    args=parser.parse_args()
    product=args.product_root.resolve()
    checkpoint=saved.read_json(product/CHECKPOINT)
    if args.metadata_only:
        saved.require(args.base is None and args.artifact_index is None,'metadata mode cannot verify saved artifacts')
        public_contract(checkpoint,product)
        report={'status':'PASS_PUBLIC_METADATA_ONLY','savedArtifactsVerified':False,'freshKernelReplay':False,
                'claims':{key:False for key in NONCLAIMS}}
    else:
        saved.require(args.base is not None and args.artifact_index is not None,'saved verification requires base and locator')
        base=args.base.resolve()
        saved.require(args.artifact_index.resolve().parent==base and args.artifact_index.name==INDEX,'unexpected private locator')
        report=verify_saved(checkpoint,saved.read_json(args.artifact_index),base,product,args.zstd)
    print(json.dumps(report,indent=2))
    return 0


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError,OSError,ValueError,KeyError,TypeError,sqlite3.Error):
        raise SystemExit('FAIL_DEPENDENCY_CALL_PROVENANCE: evidence rejected')
