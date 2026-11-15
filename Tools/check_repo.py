#!/usr/bin/env python3
"""저장소 자동 검사 (커밋 / 푸시 전에 한 번 돌린다).

  python3 Tools/check_repo.py

검사 항목
  1) manifest.json  - 저장소의 모든 Lua 스크립트가 Studio 에 올라갈 위치(parent) / 이름(name) / 종류(class) 와 함께 들어 있는가.
                      각 파일 첫 줄의 머리말("-- 이름 (ServerScriptService > Modules 안의 ModuleScript, 이름: 이름)")과 비교한다.
                      반대로 manifest 에만 있고 파일이 없는 항목도 잡는다. (Tools/*.lua 는 Studio 플러그인이라 검사에서 뺀다)
  2) 번역 모듈       - Tools/build_loc.py 를 임시 폴더에서 다시 돌린 결과와 Shared/Loc_*.lua / manifest 의 Loc 항목이 같은가.
                      (번역표 / 우리 사전을 고치고 build_loc.py 를 다시 돌리는 것을 잊으면 여기서 걸린다)
  3) 이름 중복       - 같은 부모 안에 같은 이름의 스크립트가 두 개 있으면 Studio 에서 하나가 사라진다.

문제가 있으면 어떤 파일을 어떻게 고쳐야 하는지 알려 주고 종료 코드 1 로 끝난다.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MANIFEST = os.path.join(ROOT, "manifest.json")

# 게임에 들어가지 않는 폴더 (Studio 플러그인 / 저장소 도구)
SKIP_DIRS = {"Tools", ".git", "browser"}

# 머리말이 없는 파일은 폴더 규칙으로 위치를 정한다
DIR_RULE = {
    "Server": ("ServerScriptService/Modules", "ModuleScript"),
    "Shared": ("ReplicatedStorage", "ModuleScript"),
}
SPECIAL = {
    "GameServer.lua": ("ServerScriptService", "Script"),
    "BootCoverClient.lua": ("ReplicatedFirst", "LocalScript"),  # 첫 화면 덮개: 다른 것보다 먼저 뜬다
}

HEADER = re.compile(r"^--\s*([A-Za-z0-9_]+)\s*\((.*?)안의\s*(Script|LocalScript|ModuleScript)\s*,\s*이름:\s*([A-Za-z0-9_]+)\)")

problems = []


def fail(message):
    problems.append(message)


def norm_place(text):
    """ 'ServerScriptService > Modules' / 'ServerScriptService/Modules' 를 같은 값으로 만든다."""
    return re.sub(r"\s+", "", text or "").replace(">", "/").strip("/")


def read_header(path):
    """파일 첫 두 줄의 머리말에서 (이름, 부모, 종류) 를 읽는다. 없으면 None."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        head = "\n".join(handle.read().split("\n")[:2])
    match = HEADER.search(head)
    if not match:
        return None
    name, parent, cls, declared = match.groups()
    return declared, norm_place(parent), cls


def lua_files():
    """게임에 들어가는 Lua 파일 목록 (도구 폴더는 뺀다)."""
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(files):
            if name.endswith(".lua"):
                out.append(os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, "/"))
    return out


def check_manifest():
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    entries = manifest.get("files") or []
    by_path = {}
    for entry in entries:
        path = (entry.get("path") or "").replace("\\", "/")
        if path in by_path:
            fail("manifest.json: 같은 경로가 두 번 들어 있습니다 - %s" % path)
        by_path[path] = entry

    files = lua_files()
    for rel in files:
        entry = by_path.get(rel)
        if not entry:
            fail("manifest.json 에 빠졌습니다: %s (parent / name / class / overwrite 를 적어 넣으세요)" % rel)
            continue
        if entry.get("overwrite") not in (True, False):
            fail("manifest.json: %s 의 overwrite 는 true / false 여야 합니다" % rel)
        stem = os.path.splitext(os.path.basename(rel))[0]
        if entry.get("name") != stem:
            fail("manifest.json: %s 의 name 이 '%s' 입니다 (파일 이름은 '%s')" % (rel, entry.get("name"), stem))
        header = read_header(os.path.join(ROOT, rel))
        if header:
            declared, parent, cls = header
            if declared != entry.get("name"):
                fail("%s: 머리말의 이름(%s)과 manifest 의 name(%s) 이 다릅니다" % (rel, declared, entry.get("name")))
            if parent != norm_place(entry.get("parent")):
                fail("%s: 머리말 위치(%s)와 manifest 의 parent(%s) 가 다릅니다" % (rel, parent, entry.get("parent")))
            if cls != entry.get("class"):
                fail("%s: 머리말 종류(%s)와 manifest 의 class(%s) 가 다릅니다" % (rel, cls, entry.get("class")))
            continue
        # 머리말이 없으면 폴더 규칙으로 확인한다
        if rel in SPECIAL:
            parent, cls = SPECIAL[rel]
        else:
            folder = os.path.dirname(rel)
            if folder in DIR_RULE:
                parent, cls = DIR_RULE[folder]
            elif not folder:  # 루트: GameServer / BootCoverClient 말고는 클라이언트 스크립트 (ModuleScript 로 require 되는 것도 있다)
                parent, cls = "StarterPlayer/StarterPlayerScripts", None
            else:
                fail("manifest.json: %s 는 머리말도 없고 폴더 규칙도 없어 위치를 확인할 수 없습니다" % rel)
                continue
        if norm_place(entry.get("parent")) != parent:
            fail("manifest.json: %s 의 parent 가 '%s' 입니다 (규칙은 '%s')" % (rel, entry.get("parent"), parent))
        if cls and entry.get("class") != cls:
            fail("manifest.json: %s 의 class 가 '%s' 입니다 (규칙은 '%s')" % (rel, entry.get("class"), cls))

    for path in by_path:
        if not os.path.exists(os.path.join(ROOT, path)):
            fail("manifest.json 에만 있고 파일이 없습니다: %s" % path)

    # 같은 부모 안의 이름 중복 (Studio 에서는 같은 이름이 두 개 있을 수 없다)
    seen = {}
    for entry in entries:
        key = (entry.get("parent"), entry.get("name"))
        if key in seen:
            fail("같은 위치에 같은 이름의 스크립트가 두 개입니다: %s / %s (%s, %s)"
                 % (key[0], key[1], seen[key], entry.get("path")))
        seen[key] = entry.get("path")
    print("[1/3] manifest.json 검사: Lua 파일 %d개 · manifest 항목 %d개" % (len(files), len(entries)))


def check_loc():
    """Tools/build_loc.py 를 임시 폴더에서 다시 돌려 Shared/Loc_*.lua 와 같은지 본다."""
    builder = os.path.join(HERE, "build_loc.py")
    if not os.path.exists(builder):
        fail("Tools/build_loc.py 가 없습니다")
        return
    temp = tempfile.mkdtemp(prefix="check_repo_")
    try:
        shutil.copytree(HERE, os.path.join(temp, "Tools"), ignore=shutil.ignore_patterns("__pycache__"))
        os.makedirs(os.path.join(temp, "Shared"))
        for name in os.listdir(os.path.join(ROOT, "Shared")):
            if name.endswith(".lua"):
                shutil.copy2(os.path.join(ROOT, "Shared", name), os.path.join(temp, "Shared", name))
        shutil.copy2(MANIFEST, os.path.join(temp, "manifest.json"))
        result = subprocess.run([sys.executable, os.path.join(temp, "Tools", "build_loc.py")],
                                cwd=temp, capture_output=True, text=True)
        if result.returncode != 0:
            fail("build_loc.py 가 실패했습니다 (번역표 / 사전을 확인하세요):\n" + (result.stderr or result.stdout).strip())
            return
        repo_loc = sorted(n for n in os.listdir(os.path.join(ROOT, "Shared"))
                          if re.fullmatch(r"Loc_[A-Za-z_0-9]+\.lua", n))
        new_loc = sorted(n for n in os.listdir(os.path.join(temp, "Shared"))
                         if re.fullmatch(r"Loc_[A-Za-z_0-9]+\.lua", n))
        if repo_loc != new_loc:
            fail("Shared/Loc_*.lua 파일 목록이 build_loc.py 결과와 다릅니다 (python3 Tools/build_loc.py 를 다시 돌리세요)\n"
                 "    저장소에만: %s\n    다시 만들면: %s"
                 % (sorted(set(repo_loc) - set(new_loc)), sorted(set(new_loc) - set(repo_loc))))
        for name in sorted(set(repo_loc) & set(new_loc)):
            with open(os.path.join(ROOT, "Shared", name), "rb") as repo_file:
                repo_bytes = repo_file.read()
            with open(os.path.join(temp, "Shared", name), "rb") as new_file:
                new_bytes = new_file.read()
            if repo_bytes != new_bytes:
                fail("Shared/%s 가 build_loc.py 결과와 다릅니다: python3 Tools/build_loc.py 를 다시 돌려 커밋하세요" % name)
        # build_loc.py 는 manifest 도 다시 쓰므로, Loc 항목이 같은지도 본다
        with open(MANIFEST, encoding="utf-8") as handle:
            repo_manifest = json.load(handle)
        with open(os.path.join(temp, "manifest.json"), encoding="utf-8") as handle:
            new_manifest = json.load(handle)
        pick = lambda data: sorted((e for e in data["files"] if str(e.get("path", "")).startswith("Shared/Loc_")),
                                   key=lambda e: e.get("path"))
        if pick(repo_manifest) != pick(new_manifest):
            fail("manifest.json 의 Shared/Loc_* 항목이 build_loc.py 결과와 다릅니다: python3 Tools/build_loc.py 를 다시 돌리세요")
        print("[2/3] 번역 모듈 검사: Shared/Loc_*.lua %d개 (7언어)" % len(repo_loc))
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main():
    check_manifest()
    check_loc()
    print("[3/3] 이름 중복 / 누락 검사 완료")
    if problems:
        print()
        print("문제 %d개:" % len(problems))
        for message in problems:
            print(" - " + message)
        return 1
    print()
    print("OK: 저장소 검사 통과 (manifest / 번역 모듈 / 이름 모두 정상)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
