#!/usr/bin/env python3
"""한글 사전 만들기: Tools/ko_pairs.json ([영어, 한국어] 목록) -> Shared/KoData1.lua, KoData2.lua ...
사용법:  python3 Tools/build_ko.py
- 영어 문장에 %d / %s / %.1f 가 있으면 "패턴"으로, 없으면 "정확히 같은 글자" 사전으로 만든다.
- <font ...> 같은 태그와 줄바꿈이 있으면 태그 순서가 같은 문장끼리 조각(글자 부분)으로 나눠 짝지어 둔다
  (게임이 문장을 여러 조각으로 이어 붙여 만들어도 조각 단위로 번역되게).
- 한국어 문장에도 %d / %s 를 영어와 같은 순서, 같은 개수로 넣는다 (순서를 바꾸면 그 패턴은 건너뛴다).
"""
import json, re, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pairs = json.load(open(os.path.join(ROOT, "Tools", "ko_pairs.json"), encoding="utf-8"))

SPEC = re.compile(r'%(?:%|[0-9]*\.?[0-9]*[dsf])')
DELIM = re.compile(r'(<[^>]*>|\n)')
MAGIC = set('^$()%.[]*+-?')

def specs(s):
    return [m for m in SPEC.findall(s) if m != '%%']

def to_pattern(en):
    out, last = ['^'], 0
    for m in SPEC.finditer(en):
        out.append(''.join('%' + c if c in MAGIC else c for c in en[last:m.start()]))
        tok = m.group(0)
        if tok == '%%': out.append('%%')
        elif tok.endswith('s'): out.append('(.-)')
        else: out.append('([%d,%.%-]+)')
        last = m.end()
    out.append(''.join('%' + c if c in MAGIC else c for c in en[last:]))
    out.append('$')
    return ''.join(out)

def to_template(ko):
    # 한국어 서식: 자리표시자는 전부 %s (캡처는 글자로 들어온다), 퍼센트 문자는 %% 로
    return SPEC.sub(lambda m: '%%' if m.group(0) == '%%' else '%s', ko)

def anchor(en):
    text = DELIM.sub(' ', en)
    text = SPEC.sub(' ', text)
    runs = [r for r in re.split(r"[ ,:;·\-—()\[\]!?\.'\"#/]+", text) if r]
    best = max(runs, key=len) if runs else ''
    return best if len(best) >= 3 else ''

exact, pats, seen = {}, [], set()

def add(en, ko):
    if en == ko or not re.search(r'[A-Za-z]{3,}', en): return
    key = (en, ko)
    if key in seen: return
    seen.add(key)
    if specs(en) or '%%' in en:
        if specs(en) != specs(ko):
            print('건너뜀 (자리표시자 개수/순서 다름):', en[:60].replace('\n', '⏎'), file=sys.stderr)
            return
        wild = len(re.findall(r'%s', en))
        literal = len(SPEC.sub('', en))
        pats.append((to_pattern(en), to_template(ko), anchor(en), wild * 1000 - literal))  # 점수가 낮을수록 먼저 (덜 막연하고 글자가 많은 패턴)
    else:
        exact.setdefault(en, ko)

skipped = 0
for en, ko in pairs:
    pe, pk = DELIM.split(en), DELIM.split(ko)
    if len(pe) == 1 and len(pk) == 1:
        add(en, ko)
        continue
    # 구분자(태그 / 줄바꿈) 순서가 같으면 글자 조각끼리 짝짓는다
    if len(pe) == len(pk) and all(pe[i] == pk[i] for i in range(1, len(pe), 2)):
        for i in range(0, len(pe), 2):
            a, b = pe[i], pk[i]
            if a.strip() and a != b: add(a, b)
    else:
        skipped += 1
        add(en, ko)  # 짝이 안 맞으면 문장 전체로만
print(f'정확히 같은 글자 {len(exact)}개, 패턴 {len(pats)}개, 조각 짝 맞춤 실패 {skipped}개', file=sys.stderr)

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '') + '"'

# 모듈 하나가 Studio 스크립트 한도(200KB)를 넘지 않게 나눠 쓴다
LIMIT = 90_000
chunks, cur, size = [], {'exact': [], 'pats': []}, 0
def flush():
    global cur, size
    if cur['exact'] or cur['pats']: chunks.append(cur)
    cur, size = {'exact': [], 'pats': []}, 0
for en, ko in exact.items():
    line = f'\t[{lua_str(en)}] = {lua_str(ko)},\n'
    cur['exact'].append(line); size += len(line.encode('utf-8'))
    if size > LIMIT: flush()
for pat, tmpl, anc, score in pats:
    line = f'\t{{ {lua_str(pat)}, {lua_str(tmpl)}, {lua_str(anc)}, {score} }},\n'
    cur['pats'].append(line); size += len(line.encode('utf-8'))
    if size > LIMIT: flush()
flush()

for old in os.listdir(os.path.join(ROOT, 'Shared')):
    if re.match(r'KoData\d+\.lua$', old): os.remove(os.path.join(ROOT, 'Shared', old))
names = []
for i, c in enumerate(chunks, 1):
    name = f'KoData{i}'
    names.append(name)
    body = (f'-- {name} (ReplicatedStorage 안의 ModuleScript, 이름: {name})\n'
            '-- 자동 생성 파일: Tools/build_ko.py 가 Tools/ko_pairs.json 에서 만든다. 직접 고치지 말고 ko_pairs.json 을 고친 뒤 다시 만든다.\n'
            'return {\n\texact = {\n' + ''.join('\t' + l for l in c['exact']) + '\t},\n\tpats = {\n' + ''.join('\t' + l for l in c['pats']) + '\t},\n}\n')
    open(os.path.join(ROOT, 'Shared', name + '.lua'), 'w', encoding='utf-8').write(body)
print('만든 파일:', ', '.join(names), file=sys.stderr)
json.dump(names, open(os.path.join(ROOT, 'Tools', '.ko_names.json'), 'w'))
