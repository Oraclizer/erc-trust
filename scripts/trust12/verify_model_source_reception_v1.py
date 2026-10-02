#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify saved model-source reception; neither metadata nor rehash is replay."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import sqlite3
import sys

sys.dont_write_bytecode = True
import verify_received_valuation_current_v1 as saved

CHECKPOINT = 'evidence/trust12/runtime-link/model-source-reception-checkpoint-v1.json'
VERIFIER = 'scripts/trust12/verify_model_source_reception_v1.py'
INDEX = 'model-source-reception-artifact-index-v1.json'
SCHEMA = 'trust12-model-source-reception-checkpoint-v1'
EXPECTED_EVIDENCE_DIGEST = '12fe9449be26f3b8b33cdc207eae6f85caedd52ab0efa62f756526303537f291'
CONFIRMED = ('currentProductModelSourcesReceived','explicitExportedRootsOracleZero',
             'sourceBytesAndNamespacesPreserved','capturedSourceReceiverParentReused')
NONCLAIMS = ('allAuxiliaryGeneratedFactsAudited','modelToRuntimeCorrespondence',
             'originalSymbolicOperationalExecution','generalRuntimeLinks','centralRefinementClosure',
             'independentAssurance','fullTrustCompletion','releaseOrDeployment')
ROLES = ('source','root','binding','audit','inputs-before','inputs-after','heap','database','parent-heap','parent-database')


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('utf-8')


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({k:v for k,v in checkpoint.items() if k!='rehashVerifier'})).hexdigest()


def explicit_roots(name,text):
    active_locale=None
    result=[]
    for line in text.splitlines():
        tokens=line.split()
        if tokens and tokens[0]=='locale':
            saved.require(active_locale is None,'nested model locale inventory is unsupported')
            active_locale=tokens[1]
        elif tokens==['end'] and active_locale is not None:
            active_locale=None
        match=re.match(r'^(?:lemma|theorem|corollary)\s+(\w+)',line)
        if match:
            result.append(name+'.'+(active_locale+'.' if active_locale else '')+match[1])
    return result


def public_contract(checkpoint,product):
    saved.require(checkpoint.get('schema')==SCHEMA and checkpoint.get('status')=='PASS_SAVED_MODEL_SOURCE_RECEPTION',
                  'model checkpoint schema or status differs')
    saved.require(payload_digest(checkpoint)==EXPECTED_EVIDENCE_DIGEST,'reviewed model evidence digest differs')
    text=json.dumps(checkpoint,ensure_ascii=False)
    saved.require(text.isascii() and not saved.PRIVATE.search(text),'private or non-English public metadata')
    saved.require(checkpoint['confirmed']=={k:True for k in CONFIRMED}
                  and checkpoint['claims']=={k:False for k in NONCLAIMS},'model claim boundary differs')
    verifier=checkpoint['rehashVerifier']
    saved.require(verifier['path']==VERIFIER and verifier['sha256']==saved.digest(product/VERIFIER)
                  and verifier['bytes']==(product/VERIFIER).stat().st_size,'current model verifier differs')
    models=checkpoint['productModels']
    saved.require(len(models)==14 and len({r['path'] for r in models})==14,'complete current model inventory required')
    roots=[]
    for row in models:
        path=saved.relative_file(product,row['path'])
        saved.require(row['path']=='formal/isabelle/ERC_TRUST/'+row['theory']+'.thy','model path or owner differs')
        saved.require(path.stat().st_size==row['bytes'] and saved.digest(path)==row['sha256'],'current model bytes differ')
        actual=explicit_roots(row['theory'],path.read_text(encoding='utf-8-sig'))
        saved.require(actual==row['explicitRoots'],'current explicit model root inventory differs')
        roots.extend(actual)
    saved.require(len(roots)==len(set(roots))==353 and sum(r['bytes'] for r in models)==381907,
                  'model source or exported root coverage differs')
    stages=checkpoint['kernelStages']
    saved.require(len(stages)==12 and len({r['id'] for r in stages})==12,'model stage inventory differs')
    received=[r['logicalName'].split('.')[-1] for stage in stages for r in stage['importedSources']
              if r['logicalName'].startswith('ERC_TRUST.')]
    saved.require(len(received)==len(set(received))==14 and set(received)=={r['theory'] for r in models},
                  'received model source inventory differs')
    admitted=[name for stage in stages for name in stage['explicitModelRoots']]
    saved.require(len(admitted)==353 and set(admitted)==set(roots),'source reception does not cover explicit model roots')
    rows=checkpoint['artifacts']
    supports=[r for stage in stages for r in stage['importedSources'] if not r['logicalName'].startswith('ERC_TRUST.')]
    saved.require(len(supports)==1 and supports[0]['logicalName']=='HOL-Library.Nat_Bijection','model support source differs')
    saved.require(len(rows)==135 and len({r['id'] for r in rows})==135,'model saved artifact inventory differs')
    expected={stage['id']+'-'+role for stage in stages for role in ROLES}
    expected|={r['artifactId'] for stage in stages for r in stage['importedSources']}
    saved.require({r['id'] for r in rows}==expected,'model artifact roles differ')
    for row in rows:
        saved.require(type(row['bytes']) is int and row['bytes']>0 and re.fullmatch('[0-9a-f]{64}',row['sha256']),
                      'invalid saved model artifact identity')
    return {row['id']:row for row in rows}


def source_messages(database,target,theory,imports,zstd):
    wrapper=target+'.'+theory
    allowed={wrapper}|{name for name,_ in imports}
    with sqlite3.connect(database.resolve().as_uri()+'?mode=ro&immutable=1',uri=True) as connection:
        rows=connection.execute("select session_name,theory_name,compressed,body from isabelle_exports where name='PIDE/messages'").fetchall()
        sources=connection.execute('select session_name,name from isabelle_sources').fetchall()
    saved.require(rows and len({r[1] for r in rows})==len(rows)
                  and {r[1] for r in rows}<=allowed and wrapper in {r[1] for r in rows},'model PIDE source inventory differs')
    expected={theory+'.thy'}|{p.name for _,p in imports}
    thy=[(owner,str(name).replace('\\','/').split('/')[-1]) for owner,name in sources if str(name).endswith('.thy')]
    saved.require(len(thy)==len(expected) and {name for _,name in thy}==expected
                  and all(owner==target for owner,_ in thy),'model DB source inventory differs')
    texts={}
    for owner,name,compressed,raw in rows:
        saved.require(owner==target,'model export owner differs')
        text=saved.decompress(bytes(raw),compressed,zstd).decode('utf-8')
        saved.require('error_message' not in text,'model source has saved errors')
        texts[name]=text
    return texts[wrapper]


def verify_saved(checkpoint,index,base,product,zstd):
    records=public_contract(checkpoint,product)
    saved.require(set(index)==set(records),'model private locator inventory differs')
    files={key:saved.relative_file(base,value) for key,value in index.items()}
    for key,path in files.items():
        saved.require(path.stat().st_size==records[key]['bytes'] and saved.digest(path)==records[key]['sha256'],
                      'saved model artifact differs: '+key)
    checked={}
    for row in checkpoint['kernelStages']:
        roles={role:files[row['id']+'-'+role] for role in ROLES}
        root_text=roles['root'].read_text(encoding='utf-8-sig')
        resource_lines=re.findall(r'(?m)^  sessions ([^\n]+)$',root_text)
        resources=shlex.split(resource_lines[0]) if resource_lines else []
        expected_resources={item['logicalName'].split('.')[0] for item in row['importedSources']}
        saved.require(len(resource_lines)<=1 and len(resources)==len(set(resources))
                      and set(resources)==expected_resources,'model ROOT resource imports differ')
        root_text=re.sub(r'(?m)^  sessions [^\n]+\n','',root_text)
        target,parent,theory=saved.root_identity(root_text)
        saved.require((target,parent,theory)==(row['session'],row['parent'],row['theory']),'model target identity differs')
        binding,audit=saved.read_json(roles['binding']),saved.read_json(roles['audit'])
        saved.require(binding['parent']==parent and binding['roots']==audit['roots']==row['roots']
                      and audit['session']==target and audit['parent']==parent,'model roots or parent differs')
        saved.require(binding['sourceSha256']==audit['sourceSha256']==saved.digest(roles['source'])
                      and binding['rootSha256']==saved.digest(roles['root']),'model bound source differs')
        saved.require(audit['status']=='PASS_ACTUAL_TOKEN_IDENTITY_STAGE_SAVED_KERNEL_AUDITED'
                      and audit['storedSourceByteExact'] and audit['primaryParentLineageMatches'] and audit['inputsUnchanged']
                      and audit['oracleDependencies']==0 and audit['skipProofs'] is False
                      and audit['sourceTimeoutSeconds']==120 and audit['timeoutScale']==1 and audit['heapMiB']==2048,
                      'model kernel completion or proof profile differs')
        saved.require(audit['heapSha256']==saved.digest(roles['heap']) and audit['databaseSha256']==saved.digest(roles['database']),
                      'model saved output differs')
        ancestors,output=saved.database_heap_info(roles['database'],target)
        _,parent_output=saved.database_heap_info(roles['parent-database'],parent)
        saved.require(output==saved.heap_identity(roles['heap']) and ancestors.get(parent)==parent_output==saved.heap_identity(roles['parent-heap']),
                      'model saved parent lineage differs')
        saved.saved_source(roles['database'],target,roles['source'],zstd)
        imports=[]
        saved.require(len(binding.get('importedSources',[]))==len(audit.get('importedSources',[]))==len(row['importedSources']),
                      'model imported source count differs')
        for item,bound,observed in zip(row['importedSources'],binding.get('importedSources',[]),audit.get('importedSources',[]),strict=True):
            path=files[item['artifactId']]
            saved.require(item['logicalName']==bound['name']==observed['name']
                          and item['sha256']==bound['sha256']==observed['sha256']==saved.digest(path),
                          'model imported namespace or source differs')
            saved.saved_source(roles['database'],target,path,zstd)
            imports.append((item['logicalName'],path))
        messages=source_messages(roles['database'],target,theory,imports,zstd)
        for marker in row['markers']:
            saved.require(messages.count(marker)==1,'model source oracle guard absent or ambiguous')
        before=saved.read_json(roles['inputs-before'],False)
        saved.require(before==saved.read_json(roles['inputs-after'],False)
                      and len({r['path'] for r in before})==len(before)==audit['currentInputsRehashed'],'model input snapshot differs')
        for item in before:
            path=Path(item['path']).resolve()
            saved.require(path.is_file() and (path not in checked or checked[path]==item['sha256']),'missing or conflicting model input')
            if path not in checked:
                saved.require(saved.digest(path)==item['sha256'],'current model proof input drift')
                checked[path]=item['sha256']
    return {'status':'PASS_SAVED_MODEL_SOURCE_RECEPTION_REHASHED','savedArtifactsRehashed':len(files),
            'currentInputsRehashed':len(checked),'productModelTheories':14,'explicitModelRoots':353,
            'kernelStages':12,'freshKernelReplay':False,'claims':{k:False for k in NONCLAIMS}}


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
        saved.require(args.base is None and args.artifact_index is None,'metadata-only mode cannot verify saved model artifacts')
        public_contract(checkpoint,product)
        report={'status':'PASS_PUBLIC_METADATA_ONLY','savedArtifactsVerified':False,'freshKernelReplay':False,
                'claims':{k:False for k in NONCLAIMS}}
    else:
        saved.require(args.base is not None and args.artifact_index is not None,'model saved verification requires base and locator')
        base=args.base.resolve()
        saved.require(args.artifact_index.resolve().parent==base and args.artifact_index.name==INDEX,'unexpected model private locator')
        report=verify_saved(checkpoint,saved.read_json(args.artifact_index),base,product,args.zstd)
    print(json.dumps(report,indent=2))
    return 0


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError,OSError,ValueError,KeyError,TypeError,sqlite3.Error):
        raise SystemExit('FAIL_MODEL_SOURCE_RECEPTION: evidence rejected')
