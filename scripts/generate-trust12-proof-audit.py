#!/usr/bin/env python3
"""Render every declared child theorem into the recursive oracle audit."""
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'formal/isabelle/TRUST12_OBSTRUCTIONS'
TARGET = DIRECTORY / 'TRUST12_Obstruction_Proof_Audit.thy'
paths = sorted(p for p in DIRECTORY.glob('*.thy') if p != TARGET)
names = []
for path in paths:
    context = None
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        locale = re.fullmatch(r'context\s+([A-Za-z0-9_]+)', line)
        if locale:
            if context is not None:
                raise RuntimeError('nested locale audit scope requires explicit support')
            context = locale.group(1)
        elif line == 'end':
            context = None
        theorem = re.match(r'^(?:lemma|theorem)\s+([A-Za-z0-9_]+)', line)
        if theorem:
            names.append((context + '.' if context else '') + theorem.group(1))

if not names or len(names) != len(set(names)):
    raise RuntimeError('empty or duplicate child theorem inventory')
roots = ',\n     '.join('@{thms '+name+'}' for name in names)
text = r'''theory TRUST12_Obstruction_Proof_Audit
  imports TRUST_State_Interaction_Controls
begin

ML \<open>
  val obstruction_roots =
    [ROOTS];
  val obstruction_facts = List.concat obstruction_roots;
  val obstruction_oracles = Thm_Deps.all_oracles obstruction_facts;
  val _ = if null obstruction_oracles then ()
    else error ("TRUST model audit found " ^ string_of_int (length obstruction_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\n" ^
    "explicit_root_count=" ^ string_of_int (length obstruction_roots) ^ "\n" ^
    "qualified_fact_count=" ^ string_of_int (length obstruction_facts) ^ "\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust/trust12-obstruction-proof-trust.txt\<close>
    [XML.Text audit_report];
\<close>

end
'''.replace('ROOTS',roots)
if '--write' in sys.argv:
    TARGET.write_text(text,encoding='utf8',newline='\n')
elif TARGET.read_text(encoding='utf8') != text:
    raise RuntimeError('child theorem audit inventory drift; regenerate after reviewing the source changes')
print(f'Child proof audit inventory PASS: {len(names)} declared theorem roots')
