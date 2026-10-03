#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify the same-domain FREEZE direction-guard negatives on both supply branches without claiming the mutant transaction."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
import verify_received_valuation_current_v1 as saved

CHECKPOINT = 'evidence/trust12/runtime-link/native-supply-direction-negative-checkpoint-v1.json'
VERIFIER = 'scripts/trust12/verify_native_supply_direction_negative_v1.py'
INDEX = 'native-supply-direction-negative-artifact-index-v1.json'
SCHEMA = 'trust12-native-supply-direction-negative-checkpoint-v1'
STATUS = 'PASS_SAVED_NATIVE_SUPPLY_DIRECTION_NEGATIVE'
EXPECTED_EVIDENCE_DIGEST = 'aaf8128a8b75ac8639373031dbb0a2cef1e7cc2a85593d68d3a44f36a7e2ad5f'
PROPERTY = ('For every positive first and second target with second <= first, including first above supply, '
            'the second FREEZE stutters the named Native projection.')
INPUT_DOMAIN = 'first > 0 and second > 0 and second <= first'
NOT_ASSUMED = 'first <= total supply'
SUPPLY = '1000000000000000000000000'
HEAD = '19b691216ccce9257b8effdc2d6fd9f880785ade'
SEAL = 'e40c99d8b4f663902b22ecfee8cc484cf5ec610aae4b2b2f1afccc96db68ce86'
DEFINITION = 'b72f0bfe103c075909dc7938e4ede3d8008b61f054f8e9b3039667636535b66a'
PROVED_MODULE = '4b44372ab9245beae2c33f822d2b7da8f3e5c6490477054666f943614fb7d66e'
CONFIRMED = ('sameDomainGuardRemovalOnBothSupplyBranches','originalBranchesRejoinEstablishedStates',
             'branchPredicatesPartitionDeclaredDomain','compiledGuardOnlyMutantKilledAboveSupply',
             'historicalCompiledSourceMutantKilled')
NONCLAIMS = ('wholeMutantTransactionProved','compilerCorrectness','standardEngineSemanticEquivalence',
             'generalRuntimeLinks','centralRefinementClosure','independentAssurance',
             'fullTrustCompletion','releaseOrDeployment')
ORIGINAL_RULES = ['EVM.jumpi.true','EVM.jump']
REMOVED_RULES = ['EVM.jumpi.false','EVM.pc.inc']
JOIN_RULES = ['d40db55be13c107a708382df2ae9cea0d6305bbf5d6804de46250d7076a392e2','EVM.end-basic-block','EVM.step',
              'a49bbf5c4b82ee9c477b266571ac6462951ccd1a83f52cbf657b2c60368c2c04',
              'f445bdd373dac8403ad00559717364f6630b19cbc6e53d3bbd6fa784e4089f0d',
              '252afec90cf7fb845ffd258119c187b355a11eed9c39c5e3f4e0be6d6a362cfd',
              '9940b671074c218a6c5f0f9e7b90d05efbcc000ee2884306b43860e14f6979e4',
              '5c16c518a30e69f9310171a65e1f727e85eb263915c34e4ea0e4eb19b8ba9331','EVM.pc.inc']
CUT_DEPTH = 245
BELOW_PREFIX = ('prefix-01-result','prefix-02-result','prefix-03-result')
BRANCH_ROLES = {
    'first-at-most-supply': ('prefix-01-result','prefix-02-result','prefix-03-result',
                             'source-result','source-state','binding','mutated-source','original-result','original-post',
                             'original-rule','removed-result','removed-post','removed-rule','join-result','join-post',
                             'join-rule','established-result','established-post','negative'),
    'first-above-supply': ('reference-result','reference-state','cut-result','cut-post','cut-rule','binding',
                           'mutated-source','original-result','original-post','original-rule','removed-result',
                           'removed-post','removed-rule','join-result','join-post','join-rule','established-result',
                           'established-post','negative','driver'),
}
PAIR_ROLES = ('result','normal-source','mutant-source','probe-source','normal-results','mutant-results',
              'normal-workspace','mutant-workspace','event-topic','forge-version','input-binding')
GUARD = ('            if (request.amount <= _frozen[request.subject]) {\n'
         '                revert TrustInvalidCommand(request.actionId, REASON_FREEZE_DIRECTION);\n'
         '            }')
REMOVED_GUARD = '            // Direction guard removed in the isolated feasibility mutant only.'
PREDICATES = {'first-at-most-supply': 'first <= SUPPLY', 'first-above-supply': 'SUPPLY < first'}


SAVED_FLOOR = {'first-at-most-supply': '?WORD', 'first-above-supply': SUPPLY}


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('utf-8')


def stream_digest(value):
    result=hashlib.sha256()
    for chunk in json.JSONEncoder(sort_keys=True,separators=(',',':')).iterencode(value):
        result.update(chunk.encode())
    return result.hexdigest()


def find_cell(node,label):
    stack=[node]
    while stack:
        current=stack.pop()
        if isinstance(current,dict):
            if current.get('node')=='KApply' and current['label']['name']==label:
                return current
            stack.extend(current.get('args',[]))
    raise RuntimeError('cell missing: '+label)


def branch_state(path):
    """Hash the configuration with the saved call stack removed and read the saved caller's second stack word."""
    state=json.loads(Path(path).read_text(encoding='utf-8-sig'))
    call_stack=find_cell(state['config'],'<callStack>')
    word_stack=find_cell(call_stack,'<wordStack>')['args'][0]
    saved_pc=find_cell(call_stack,'<pc>')['args'][0]
    saved_depth=find_cell(call_stack,'<callDepth>')['args'][0]
    saved.require(word_stack['label']['name'].startswith('_:__EVM-TYPES') and saved_pc.get('token')=='12399'
                  and saved_depth.get('token')=='0','saved caller frame differs')
    second=word_stack['args'][1]['args'][0]
    floor=second.get('token') if second.get('node')=='KToken' else second.get('name')
    frames=call_stack['args']
    call_stack['args']=[]
    outside=stream_digest(state['config'])
    call_stack['args']=frames
    constraints=state['constraints']
    del state
    return outside,floor,constraints


def segment(row,source):
    """Check a retained bounded step record that has no separately retained checked rule."""
    saved.require(row['status']=='PASS_EXACT_BOOSTER_STEP' and row['sourceHead']==HEAD
                  and row['sourceInputSealSha256']==SEAL and row['definitionSha256']==DEFINITION
                  and row['sourceStateSha256']==source and row['depth']==row['requestedDepth']
                  and row['provedModuleSha256']==PROVED_MODULE and row['nativeRequestCount']==1
                  and row['proofPassed'] is True,'retained segment record differs')
    for key in ('callerAssumeStateDefined','customModuleRegistered','trustedMarkerExecuted','admitted','circularity',
                'productSourceModified','originalGraphModified','assumptionsAdded'):
        saved.require(row[key] is False,'unsafe retained segment flag')
    return [item.split(':',1)[0] for item in row['rules']]


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key:value for key,value in checkpoint.items() if key!='rehashVerifier'})).hexdigest()


def supply_bound(term,label,supply_first):
    saved.require(isinstance(term,dict) and term.get('node')=='KApply' and term['label']['name']=='#Equals'
                  and term['args'][0]=={'node':'KToken','token':'true','sort':{'node':'KSort','name':'Bool','params':[]}},
                  'branch constraint shape differs')
    predicate=term['args'][1]
    saved.require(predicate.get('node')=='KApply' and predicate['label']['name']==label and len(predicate['args'])==2,
                  'branch constraint operator differs')
    supply,word=(predicate['args'] if supply_first else predicate['args'][::-1])
    saved.require(supply=={'node':'KToken','token':SUPPLY,'sort':{'node':'KSort','name':'Int','params':[]}}
                  and word=={'node':'KVariable','name':'?WORD','sort':{'node':'KSort','name':'Int','params':[]}},
                  'branch constraint operands differ')


def public_contract(checkpoint,product):
    saved.require(checkpoint.get('schema')==SCHEMA and checkpoint.get('status')==STATUS,'checkpoint schema or status differs')
    saved.require(payload_digest(checkpoint)==EXPECTED_EVIDENCE_DIGEST,'reviewed evidence digest differs')
    encoded=json.dumps(checkpoint,ensure_ascii=False)
    saved.require(encoded.isascii() and not saved.PRIVATE.search(encoded),'private or non-English metadata')
    saved.require(checkpoint['confirmed']=={key:True for key in CONFIRMED}
                  and checkpoint['claims']=={key:False for key in NONCLAIMS},'claim boundary differs')
    saved.require(checkpoint['property']==PROPERTY and checkpoint['inputDomain']==INPUT_DOMAIN
                  and checkpoint['notAssumed']==NOT_ASSUMED,'declared Native scope differs')
    saved.require(checkpoint['coverage']=={'branches':2,'sharedConstraintCount':13,'coversDeclaredScope':True,
                                           'fullInputDomainNegative':True,'wholeMutantTransactionProved':False},
                  'coverage differs')
    guard=checkpoint['guard']
    saved.require(guard['programCounter']==11514 and guard['originalDestination']==11739
                  and guard['guardRemovedFallthrough']==11515 and guard['constraintCount']==14,'guard identity differs')
    saved.require(guard['sourceMutation']=={'id':'MUT-08-FREEZE-DIRECTION','file':'implementation/src/TrustToken.sol',
                                            'old':'request.amount <= _frozen[request.subject]','new':'false'},
                  'source mutation identity differs')
    branches=checkpoint['branches']
    saved.require([row['id'] for row in branches]==list(BRANCH_ROLES)
                  and all(row['predicate']==PREDICATES[row['id']] for row in branches),'branch partition differs')
    supply_bound(branches[0]['branchConstraint'],'_<=Int_',False)
    supply_bound(branches[1]['branchConstraint'],'_<Int_',True)
    for row in branches:
        saved.require(row['originalRules']==ORIGINAL_RULES and row['removedRules']==REMOVED_RULES
                      and row['joinRules']==JOIN_RULES and row['originalPostPc']==11739 and row['removedPostPc']==11515,
                      'branch rule or program-counter record differs')
        for key in ('sourceStateSha256','mutatedSourceSha256','constraintsAstSha256','controlNeutralFrameSha256',
                    'establishedFinalStateSha256'):
            saved.require(re.fullmatch('[0-9a-f]{64}',row[key]) is not None,'invalid branch identity')
    saved.require(branches[1]['cutDepth']==CUT_DEPTH and 'cutDepth' not in branches[0],'cut record differs')
    states=checkpoint['branchStates']
    saved.require(set(states)=={'configurationOutsideCallStackSha256','savedCallerExpectedFloor','differenceScope'}
                  and re.fullmatch('[0-9a-f]{64}',states['configurationOutsideCallStackSha256']) is not None
                  and states['savedCallerExpectedFloor']==SAVED_FLOOR
                  and states['differenceScope']=='path condition and saved caller frame only','branch state record differs')
    pair=checkpoint['compiledGuardOnlyPair']
    saved.require(pair['inputs']=={'supply':SUPPLY,'first':'1000000000000000000000002','second':'1000000000000000000000001'}
                  and pair['normal']['originalConsumer']=='Success' and pair['mutant']['originalConsumer']=='Failure'
                  and pair['mutant']['failureReason']=='rejection wrote action'
                  and pair['normal']['accepted'] is False and pair['mutant']['accepted'] is True
                  and pair['normal']['lifecycle']==0 and pair['mutant']['lifecycle']==2
                  and pair['normal']['visibleFrozenFloor']==pair['mutant']['visibleFrozenFloor']==SUPPLY
                  and pair['guardOnlySourceDifference'] is True and pair['normalSourceIsProductSource'] is True,
                  'compiled guard-only pair differs')
    reader=checkpoint['rehashVerifier']
    saved.require(reader['path']==VERIFIER and reader['sha256']==saved.digest(product/VERIFIER)
                  and reader['bytes']==(product/VERIFIER).stat().st_size,'current verifier differs')
    for row in checkpoint['productIdentity'].values():
        path=saved.relative_file(product,row['path'])
        saved.require(path.stat().st_size==row['bytes'] and saved.digest(path)==row['sha256'],'current product input differs')
    expected={branch+'-'+role for branch,roles in BRANCH_ROLES.items() for role in roles}|{'pair-'+role for role in PAIR_ROLES}
    rows=checkpoint['artifacts']
    saved.require(len(rows)==len(expected) and {row['id'] for row in rows}==expected,'artifact roles differ')
    for row in rows:
        saved.require(type(row['bytes']) is int and row['bytes']>=0 and re.fullmatch('[0-9a-f]{64}',row['sha256']),
                      'invalid artifact identity')
    return {row['id']:row for row in rows}


def step(row,source,depth,rules,post,rule):
    saved.require(row['status']=='PASS_EXACT_BOOSTER_STEP' and row['sourceHead']==HEAD
                  and row['sourceInputSealSha256']==SEAL and row['definitionSha256']==DEFINITION,'exact step pin differs')
    saved.require(row['sourceStateSha256']==source and row['depth']==row['requestedDepth']==depth
                  and row['actualPostSha256']==post and row['checkedRuleSha256']==rule,'exact step chain differs')
    saved.require([item.split(':',1)[0] for item in row['rules']]==rules,'exact step rules differ')
    saved.require(row['provedModuleSha256']==PROVED_MODULE and row['nativeRequestCount']==1
                  and row['proofPassed'] is True,'exact step proof record differs')
    for key in ('callerAssumeStateDefined','customModuleRegistered','trustedMarkerExecuted','admitted','circularity',
                'productSourceModified','originalGraphModified','assumptionsAdded'):
        saved.require(row[key] is False,'unsafe exact step flag')


def verify_branch(branch,sha,read,files):
    name=branch['id']
    binding=read(name+'-binding')
    saved.require(binding['status']=='PASS_SAME_DOMAIN_GUARD_MUTANT_BINDING' and binding['sourceHead']==HEAD
                  and binding['definitionSha256']==DEFINITION and binding['onlyKCellChanged'] is True
                  and binding['kContinuationPreserved'] is True
                  and binding['sourceConstraintCount']==binding['mutantConstraintCount']==14
                  and binding['boundMutationResult']['mutantCompiled'] is True
                  and binding['boundMutationResult']['result']=='KILLED','mutant binding differs')
    source=sha(name+('-cut-post' if name=='first-above-supply' else '-source-state'))
    saved.require(binding['sourceStateSha256']==source==branch['sourceStateSha256']
                  and binding['mutatedSourceSha256']==sha(name+'-mutated-source')==branch['mutatedSourceSha256']
                  and binding['constraintsAstSha256']==branch['constraintsAstSha256'],'mutant binding identity differs')
    original,removed,join=read(name+'-original-result'),read(name+'-removed-result'),read(name+'-join-result')
    step(original,source,2,ORIGINAL_RULES,sha(name+'-original-post'),sha(name+'-original-rule'))
    step(removed,branch['mutatedSourceSha256'],2,REMOVED_RULES,sha(name+'-removed-post'),sha(name+'-removed-rule'))
    step(join,sha(name+'-original-post'),len(JOIN_RULES),JOIN_RULES,sha(name+'-join-post'),sha(name+'-join-rule'))
    established=read(name+'-established-result')
    saved.require(established['status']=='PASS_EXACT_BOOSTER_STEP'
                  and established['actualPostSha256']==sha(name+'-established-post')==sha(name+'-join-post')
                  ==branch['establishedFinalStateSha256'],'original branch does not rejoin the established state')
    established_rules=segment(established,established['sourceStateSha256'])
    negative=read(name+'-negative')
    saved.require(negative['bindingResultSha256']==sha(name+'-binding')
                  and negative['originalBranch']['resultSha256']==sha(name+'-original-result')
                  and negative['guardRemovedBranch']['resultSha256']==sha(name+'-removed-result')
                  and negative['originalBranch']['checkedRuleSha256']==sha(name+'-original-rule')
                  and negative['guardRemovedBranch']['checkedRuleSha256']==sha(name+'-removed-rule'),
                  'negative record references differ from retained files')
    saved.require(negative['status']=='PASS_SAME_DOMAIN_DIRECTION_GUARD_NEGATIVE'
                  and negative['sourceStateSha256']==source and negative['mutatedSourceSha256']==branch['mutatedSourceSha256']
                  and negative['sameConstraintDomain'] is True and negative['samePostFrameExceptPcAndKControl'] is True
                  and negative['originalDestinationPc']==11739 and negative['guardRemovedFallthroughPc']==11515,
                  'negative result differs')
    posts=(negative['originalBranch']['post'],negative['guardRemovedBranch']['post'])
    saved.require(posts[0]['pc']==11739 and posts[1]['pc']==11515
                  and posts[0]['constraintCount']==posts[1]['constraintCount']==14
                  and posts[0]['constraintsAstSha256']==posts[1]['constraintsAstSha256']==branch['constraintsAstSha256']
                  and posts[0]['controlNeutralConfigurationAstSha256']==posts[1]['controlNeutralConfigurationAstSha256']
                  ==branch['controlNeutralFrameSha256'],'branch posts differ outside program counter and control')
    if name=='first-above-supply':
        saved.require(binding['schema']=='trust12-native-direction-guard-mutant-v2'
                      and binding['branch']=='first-amount-above-supply' and binding['sharedConstraintCount']==13
                      and binding['cutResultSha256']==sha(name+'-cut-result')
                      and binding['referenceStateSha256']==sha(name+'-reference-state')
                      and binding['constraintsEqualReferenceInOrder'] is True,'cut binding differs')
        supply_bound(binding['branchConstraint'],'_<Int_',True)
        supply_bound(binding['complementBranchConstraint'],'_<=Int_',False)
        saved.require(binding['branchConstraint']==branch['branchConstraint'],'branch constraint differs')
        cut=read(name+'-cut-result')
        step(cut,sha(name+'-reference-state'),CUT_DEPTH,[item.split(':',1)[0] for item in cut['rules']],
             source,sha(name+'-cut-rule'))
        rules=established_rules
        saved.require(established['sourceStateSha256']==sha(name+'-reference-state')
                      and established['depth']==len(rules)==CUT_DEPTH+2+len(JOIN_RULES)
                      and rules[:CUT_DEPTH]==[item.split(':',1)[0] for item in cut['rules']]
                      and rules[CUT_DEPTH:]==ORIGINAL_RULES+JOIN_RULES,'cut is not on the established segment')
        saved.require(join['expectedPostSha256']==branch['establishedFinalStateSha256'] and join['exactPostEqual'] is True,
                      'join was not checked against the established state')
        saved.require(negative['cut']['resultSha256']==sha(name+'-cut-result')
                      and negative['establishedSegmentJoin']['resultSha256']==sha(name+'-join-result')
                      and negative['establishedSegmentJoin']['checkedRuleSha256']==sha(name+'-join-rule')
                      and negative['establishedSegmentJoin']['exactPostSha256']==sha(name+'-join-post')
                      and negative['establishedSegmentJoin']['establishedSegmentResultSha256']==sha(name+'-established-result')
                      and negative['complementaryBranch']['negativeResultSha256']==sha('first-at-most-supply-negative'),
                      'negative record references differ from retained files')
        reference=read(name+'-reference-result')
        saved.require(reference['status']=='PASS_EXACT_BOOSTER_STEP'
                      and reference['actualPostSha256']==sha(name+'-reference-state'),'reference state record differs')
        driver=read(name+'-driver')
        saved.require(driver['status']=='PASS_DIRECTION_GUARD_FALSE_BRANCH_CHAIN' and driver['inputsUnchanged'] is True
                      and driver['mutantSuffixComplete'] is False,'driver receipt differs')
        saved.require(negative['complementaryBranch']['sourceStateSha256']==binding['complementStateSha256'],
                      'complementary branch binding differs')
    else:
        prefix_rules,previous=[],established['sourceStateSha256']
        for role in (*BELOW_PREFIX,'source-result'):
            row=read(name+'-'+role)
            prefix_rules+=segment(row,previous)
            previous=row['actualPostSha256']
        saved.require(previous==source,'retained prefix does not end at the branch source')
        cut_depth=len(prefix_rules)
        saved.require(established['depth']==len(established_rules)==cut_depth+2+len(JOIN_RULES)
                      and established_rules[:cut_depth]==prefix_rules
                      and established_rules[cut_depth:]==ORIGINAL_RULES+JOIN_RULES,
                      'branch source is not on the established segment')
        saved.require(negative['reasonCheckpointJoin']['resultSha256']==sha(name+'-join-result')
                      and negative['reasonCheckpointJoin']['checkedRuleSha256']==sha(name+'-join-rule')
                      and negative['reasonCheckpointJoin']['exactPostSha256']==sha(name+'-join-post')
                      and negative['reasonCheckpointJoin']['priorAuthorityResultSha256']==sha(name+'-established-result'),
                      'negative record references differ from retained files')
    return binding


def verify_saved(checkpoint,index,base,product):
    records=public_contract(checkpoint,product)
    saved.require(set(index)==set(records),'private locator inventory differs')
    files={key:saved.relative_file(base,value) for key,value in index.items()}
    hashes={}
    for key,path in files.items():
        hashes[key]=saved.digest(path)
        saved.require(path.stat().st_size==records[key]['bytes'] and hashes[key]==records[key]['sha256'],
                      'saved artifact differs: '+key)
    sha=hashes.__getitem__
    read=lambda key: saved.read_json(files[key])
    below=verify_branch(checkpoint['branches'][0],sha,read,files)
    above=verify_branch(checkpoint['branches'][1],sha,read,files)
    saved.require(above['complementStateSha256']==below['sourceStateSha256'],'branches are not complementary sources')
    declared=checkpoint['branchStates']
    constraint_keys={}
    for row,role in zip(checkpoint['branches'],('source-state','cut-post')):
        name=row['id']
        outside,floor,constraints=branch_state(files[name+'-'+role])
        saved.require(outside==declared['configurationOutsideCallStackSha256']
                      and floor==declared['savedCallerExpectedFloor'][name],
                      'branch states differ outside the declared caller-frame floor')
        saved.require(len(constraints)==14 and hashlib.sha256(json.dumps(constraints,sort_keys=True,separators=(',',':'))
                      .encode()).hexdigest()==row['constraintsAstSha256'],'state constraints differ from the record')
        constraint_keys[name]=[json.dumps(term,sort_keys=True) for term in constraints]
    below_keys,above_keys=constraint_keys['first-at-most-supply'],constraint_keys['first-above-supply']
    shared=set(below_keys)&set(above_keys)
    saved.require(len(shared)==13 and [key for key in below_keys if key not in shared]
                  ==[json.dumps(checkpoint['branches'][0]['branchConstraint'],sort_keys=True)]
                  and [key for key in above_keys if key not in shared]
                  ==[json.dumps(checkpoint['branches'][1]['branchConstraint'],sort_keys=True)],
                  'state constraints do not partition at the declared branch predicate')
    saved.require(below['boundSourceMutation']['id']==above['boundSourceMutation']['id']=='MUT-08-FREEZE-DIRECTION',
                  'source mutation binding differs')
    pair=read('pair-result')
    public=checkpoint['compiledGuardOnlyPair']
    saved.require(pair['status'].startswith('PASS_BOUNDED_COMPILED_SUPPLY_DIRECTION') and pair['sameProbeSource'] is True
                  and pair['guardOnlyProductionSourceDifference'] is True and pair['actualOriginalActionConsumerKilled'] is True
                  and pair['compiledMutantContinuationActivated'] is True and pair['sameSaturatedFloor'] is True
                  and pair['inputs']==public['inputs'],'compiled pair result differs')
    for side in ('normal','mutant'):
        observed,declared=pair['observations'][side],public[side]
        saved.require(pair['results'][side]['originalConsumer']==declared['originalConsumer']
                      and observed['accepted']==declared['accepted'] and observed['lifecycle']==declared['lifecycle']
                      and observed['visibleFrozenFloor']==declared['visibleFrozenFloor'],'compiled observation differs')
    saved.require(pair['results']['mutant']['reason']==public['mutant']['failureReason'],'compiled failure reason differs')
    expected={'normal':{'test_SupplyDirectionObservations()':('Success',None),
                        'test_SupplyDirectionOriginalConsumer()':('Success',None)},
              'mutant':{'test_SupplyDirectionObservations()':('Success',None),
                        'test_SupplyDirectionOriginalConsumer()':('Failure',public['mutant']['failureReason'])}}
    for side,tests in expected.items():
        raw=read('pair-'+side+'-results')
        saved.require(len(raw)==1,'compiled result suite differs')
        observed={name:(row['status'],row['reason']) for name,row in next(iter(raw.values()))['test_results'].items()}
        saved.require(observed==tests,'compiled raw test results differ')
    normal=files['pair-normal-source'].read_text(encoding='utf-8')
    mutant=files['pair-mutant-source'].read_text(encoding='utf-8')
    saved.require(normal.count(GUARD)==1 and normal.replace(GUARD,REMOVED_GUARD)==mutant,'mutant is not the guard-only removal')
    saved.require(sha('pair-normal-source')==checkpoint['productIdentity']['nativeSource']['sha256'],
                  'compiled pair source is not the current product source')
    for key in ('pair-normal-workspace','pair-mutant-workspace'):
        saved.require(files[key].stat().st_size>0,'compiled workspace missing')
    return {'status':'PASS_SAVED_NATIVE_SUPPLY_DIRECTION_NEGATIVE_REHASHED','branches':2,
            'savedArtifactsRehashed':len(files),'coversDeclaredScope':True,'wholeMutantTransactionProved':False,
            'freshExecution':False,'claims':{key:False for key in NONCLAIMS}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product-root',type=Path,default=Path(__file__).resolve().parents[2])
    parser.add_argument('--metadata-only',action='store_true')
    parser.add_argument('--base',type=Path)
    parser.add_argument('--artifact-index',type=Path)
    args=parser.parse_args()
    product=args.product_root.resolve()
    checkpoint=saved.read_json(product/CHECKPOINT)
    if args.metadata_only:
        saved.require(args.base is None and args.artifact_index is None,'metadata mode cannot verify saved artifacts')
        public_contract(checkpoint,product)
        report={'status':'PASS_PUBLIC_METADATA_ONLY','savedArtifactsVerified':False,'freshExecution':False,
                'claims':{key:False for key in NONCLAIMS}}
    else:
        saved.require(args.base is not None and args.artifact_index is not None,'saved verification requires base and locator')
        base=args.base.resolve()
        saved.require(args.artifact_index.resolve().parent==base and args.artifact_index.name==INDEX,'unexpected private locator')
        report=verify_saved(checkpoint,saved.read_json(args.artifact_index),base,product)
    print(json.dumps(report,indent=2))
    return 0


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError,OSError,ValueError,KeyError,TypeError,AttributeError,IndexError):
        raise SystemExit('FAIL_NATIVE_SUPPLY_DIRECTION_NEGATIVE: evidence rejected')
