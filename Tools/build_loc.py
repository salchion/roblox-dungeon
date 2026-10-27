# Tools/build_loc.py: 크리에이터 허브에서 내려받은 번역표(Tools/loc_table.csv)로 언어별 모듈(Shared/Loc_<언어>.lua)을 만든다.
# 번역표를 새로 내려받으면 loc_table.csv 를 덮어쓰고 `python3 Tools/build_loc.py` 를 다시 돌린다.
import csv, json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LANGS = ["ko", "ja", "de", "fr", "es", "pt", "zh-hans"]

def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'

SPEC = re.compile(r'%(?:%|[0-9]*\.?[0-9]*[dsf])')
DELIM = re.compile(r'(<[^>]*>|\n)')

def specs(x):
    return [m for m in SPEC.findall(x) if m != '%%']

def convert(x):
    """%d / %f -> {numberN}, %s -> {textN} (번호는 나온 순서), %% -> %"""
    counter = [0]
    def sub(m):
        t = m.group(0)
        if t == '%%': return '%'
        counter[0] += 1
        return "{%s%d}" % ("text" if t.endswith("s") else "number", counter[0])
    return SPEC.sub(sub, x)

def own_pairs(lang):
    """우리가 손으로 만든 사전(Tools/ko_pairs.json 등)에서 [영어, 번역] 쌍을 읽는다. 지금은 한국어만 있다."""
    path = os.path.join(HERE, {"ko": "ko_pairs.json"}.get(lang, "none"))
    if not os.path.exists(path): return []
    out = []
    for en, tr in json.load(open(path, encoding="utf-8")):
        if specs(en) != specs(tr): continue  # 자리표시자 순서 / 개수가 다르면 건너뛴다
        out.append((en, tr))
        ep, tp = DELIM.split(en), DELIM.split(tr)
        if len(ep) > 1 and len(ep) == len(tp) and all(a == b for a, b in zip(ep[1::2], tp[1::2])): # 태그 / 줄바꿈 순서가 같으면 조각 단위로도
            for a, b in zip(ep[0::2], tp[0::2]):
                a, b = a.strip(), b.strip()
                if a and b and specs(a) == specs(b): out.append((a, b))
    return [(convert(a), convert(b)) for a, b in out]

rows = list(csv.reader(open(os.path.join(HERE, "loc_table.csv"), encoding="utf-8-sig")))
head = rows[0]
src_i = head.index("Source")
for lang in LANGS:
    col = head.index(lang)
    exact, tmpl, seen = [], [], set()
    for r in rows[1:]:
        if len(r) <= col: continue
        src, tr = r[src_i], r[col]
        if not src or not tr or tr == src or src in seen: continue
        seen.add(src)
        (tmpl if re.search(r"\{(?:number|text)\d+\}", src) else exact).append((src, tr))
        # 여러 줄 묶음은 줄 단위로도 넣는다 (게임 글자는 줄 / 색 태그 조각으로 따로 찾는다). 줄 수가 같을 때만.
        sl, tl = src.split("\n"), tr.split("\n")
        if len(sl) > 1 and len(sl) == len(tl):
            for a, b in zip(sl, tl):
                a, b = a.strip(), b.strip()
                if a and b and a != b and a not in seen:
                    seen.add(a)
                    (tmpl if re.search(r"\{(?:number|text)\d+\}", a) else exact).append((a, b))
    for src, tr in own_pairs(lang): # 번역표(CSV)에 없는 글자만 우리 사전으로 채운다
        if src in seen or not re.search(r"[A-Za-z]{3,}", src) or src == tr: continue
        seen.add(src)
        (tmpl if re.search(r"\{(?:number|text)\d+\}", src) else exact).append((src, tr))
    # 덜 막연한 패턴이 먼저: {text} 자리가 적고 고정 글자가 긴 것부터 (아무 글자나 받는 패턴이 먼저 잡아채지 않게)
    tmpl.sort(key=lambda pair: (len(re.findall(r"\{text\d+\}", pair[0])), -len(re.sub(r"\{(?:number|text)\d+\}", "", pair[0]))))
    base = "Loc_" + lang.replace("-", "_")
    # Studio 스크립트 한도(약 200KB) 때문에 한 파일이 ~110KB 를 넘지 않게 나눈다: Loc_xx, Loc_xx_2, Loc_xx_3 ... (게임이 차례로 찾아 합친다)
    LIMIT = 110000
    lines_exact = ["\t\t[%s] = %s," % (lua(a), lua(b)) for a, b in exact]
    lines_tmpl = ["\t\t{ %s, %s }," % (lua(a), lua(b)) for a, b in tmpl]
    chunks, cur, size = [], ([], []), 0
    for kind, lines in (("e", lines_exact), ("t", lines_tmpl)):
        for line in lines:
            if size + len(line.encode("utf-8")) > LIMIT:
                chunks.append(cur)
                cur, size = ([], []), 0
            cur[0 if kind == "e" else 1].append(line)
            size += len(line.encode("utf-8"))
    chunks.append(cur)
    for old in os.listdir(os.path.join(ROOT, "Shared")):
        if old == base + ".lua" or re.fullmatch(re.escape(base) + r"_\d+\.lua", old): os.remove(os.path.join(ROOT, "Shared", old))
    for index, (ex, tp) in enumerate(chunks, 1):
        name = base if index == 1 else "%s_%d" % (base, index)
        out = ["-- %s (ReplicatedStorage 안의 ModuleScript, 이름: %s)" % (name, name),
               "-- 자동 생성 파일: Tools/build_loc.py 가 Tools/loc_table.csv (+ 우리 사전) 에서 만든다. 직접 고치지 않는다.",
               "return {", "\texact = {"] + ex + ["\t},", "\ttemplates = {"] + tp + ["\t},", "}", ""]
        path = os.path.join(ROOT, "Shared", name + ".lua")
        open(path, "w", encoding="utf-8").write("\n".join(out))
        print(name, len(ex), len(tp), os.path.getsize(path))
