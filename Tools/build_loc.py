# Tools/build_loc.py: 크리에이터 허브에서 내려받은 번역표(Tools/loc_table.csv)로 언어별 모듈(Shared/Loc_<언어>.lua)을 만든다.
# 번역표를 새로 내려받으면 loc_table.csv 를 덮어쓰고 `python3 Tools/build_loc.py` 를 다시 돌린다.
import csv, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LANGS = ["ko", "ja", "de", "fr", "es", "pt", "zh-hans"]

def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'

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
        (tmpl if re.search(r"\{number\d+\}", src) else exact).append((src, tr))
    name = "Loc_" + lang.replace("-", "_")
    out = ["-- %s (ReplicatedStorage 안의 ModuleScript, 이름: %s)" % (name, name),
           "-- 자동 생성 파일: Tools/build_loc.py 가 Tools/loc_table.csv 에서 만든다. 직접 고치지 않는다.",
           "return {", "\texact = {"]
    out += ["\t\t[%s] = %s," % (lua(s), lua(t)) for s, t in exact]
    out += ["\t},", "\ttemplates = {"]
    out += ["\t\t{ %s, %s }," % (lua(s), lua(t)) for s, t in tmpl]
    out += ["\t},", "}", ""]
    path = os.path.join(ROOT, "Shared", name + ".lua")
    open(path, "w", encoding="utf-8").write("\n".join(out))
    print(name, len(exact), len(tmpl), os.path.getsize(path))
