#!/usr/bin/env bash
# 문서 검증 게이트 — 링크 무결성 + 프론트매터 + 구조
# 사용: ./scripts/verify-docs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m⚠ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

step "상대경로 링크 무결성"
python3 - <<'PY' || exit 1
import pathlib, re, urllib.parse, sys

bad, total = [], 0
targets = list(pathlib.Path("docs").rglob("*.md"))
for extra in ("README.md", "CLAUDE.md"):
    p = pathlib.Path(extra)
    if p.exists():
        targets.append(p)

for p in targets:
    if "_templates" in str(p):
        continue
    txt = p.read_text(encoding="utf-8")
    body = txt.split("---\n", 2)[2] if txt.startswith("---\n") else txt
    for m in re.finditer(r'\[([^\]]*)\]\(([^)\s]+\.md)(#[^)]*)?\)', body):
        target = urllib.parse.unquote(m.group(2))
        if target.startswith(("http://", "https://")):
            continue
        total += 1
        if not (p.parent / target).resolve().exists():
            bad.append(f"{p} -> {target}")

print(f"  검사 {total}개")
if bad:
    print("  깨진 링크:")
    for b in bad:
        print(f"    {b}")
    sys.exit(1)
PY
ok "깨진 링크 없음"

step "프론트매터"
python3 - <<'PY' || exit 1
import pathlib, sys

REQUIRED = ("title:", "aliases:", "tags:", "created:", "updated:", "status:")
missing, incomplete = [], []

for p in pathlib.Path("docs").rglob("*.md"):
    if "_templates" in str(p):
        continue
    t = p.read_text(encoding="utf-8")
    if not t.startswith("---\n"):
        missing.append(str(p))
        continue
    head = t.split("---", 2)[1]
    absent = [k for k in REQUIRED if k not in head]
    if absent:
        incomplete.append(f"{p}: {', '.join(absent)}")

if missing:
    print("  프론트매터 없음:")
    for m in missing:
        print(f"    {m}")
if incomplete:
    print("  필수 키 누락:")
    for i in incomplete:
        print(f"    {i}")
if missing or incomplete:
    sys.exit(1)
print(f"  전 문서 통과")
PY
ok "프론트매터 정상"

step "구조 규약"
# 파일명은 영문, 폴더명은 한글 (P-05 결정)
BAD_NAMES=$(find docs -name "*.md" -not -path "*/_templates/*" \
  | while read -r f; do
      base=$(basename "$f")
      if printf '%s' "$base" | LC_ALL=C grep -q '[^ -~]'; then printf '%s\n' "$f"; fi
    done)
if [ -n "$BAD_NAMES" ]; then
  warn "파일명에 비ASCII 문자 (규약: 파일명 영문 / 폴더명 한글)"
  printf '%s\n' "$BAD_NAMES" | sed 's/^/    /'
else
  ok "파일명 규약 준수"
fi

# INDEX에서 참조되지 않는 문서 탐지
step "INDEX 등재 여부"
UNLINKED=$(python3 - <<'PY'
import pathlib, re
index = pathlib.Path("docs/INDEX.md").read_text(encoding="utf-8")
out = []
for p in pathlib.Path("docs").rglob("*.md"):
    s = str(p)
    if "_templates" in s or s.endswith("INDEX.md"):
        continue
    # 결정 노트와 레퍼런스는 허브 문서가 따로 있으므로 제외
    if "05-결정/stack/" in s or "05-결정/adr/" in s or "08-레퍼런스/" in s or "07-기획/" in s:
        continue
    rel = s[len("docs/"):]
    if rel not in index:
        out.append(s)
print("\n".join(out))
PY
)
if [ -n "$UNLINKED" ]; then
  warn "INDEX.md에 등재되지 않은 문서"
  printf '%s\n' "$UNLINKED" | sed 's/^/    /'
else
  ok "전 문서 등재됨"
fi

step "디자인 토큰 일치"
# DESIGN-SYSTEM.md가 정본이고 Tokens.swift가 그것을 코드로 옮긴 것이다.
# 갈라지면 목업과 구현이 어긋난다.
# 1-A에서 DesignSystem 모듈로 옮겼다. 경로를 안 고치면 아래 else 가지로
# 빠져 "건너뜁니다"가 되고, 목업과 구현이 갈라져도 게이트가 통과한다.
TOKENS_SWIFT="ios/Projects/DesignSystem/Sources/Tokens.swift"
DESIGN_DOC="docs/06-디자인/DESIGN-SYSTEM.md"
if [ -f "$TOKENS_SWIFT" ]; then
  MISMATCH=$(python3 - "$TOKENS_SWIFT" "$DESIGN_DOC" <<'PY2'
import re, sys, pathlib

swift = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
doc = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

# 0xRRGGBB → RRGGBB
code = {m.upper() for m in re.findall(r"0x([0-9A-Fa-f]{6})", swift)}
# 문서의 #RRGGBB. 11.8 대역 색 절은 토큰이 아니므로 제외한다.
body = doc.split("## 11.8")[0]
docs = {m.upper() for m in re.findall(r"#([0-9A-Fa-f]{6})", body)}

missing = sorted(docs - code)
extra = sorted(code - docs)
out = []
if missing:
    out.append("문서에만 있음 (코드에 누락): " + " ".join("#" + c for c in missing))
if extra:
    out.append("코드에만 있음 (문서에 없는 값): " + " ".join("#" + c for c in extra))
print("\n".join(out))
PY2
)
  if [ -n "$MISMATCH" ]; then
    printf '%s\n' "$MISMATCH" | sed 's/^/    /'
    fail "Tokens.swift와 DESIGN-SYSTEM.md의 색이 어긋납니다"
  fi
  ok "토큰 일치"
else
  printf "Tokens.swift 없음 — 건너뜁니다\n"
fi

# ─────────────────────────────────────────────────────────────
step "절 번호 참조"
# 문서 간 참조를 "촬영 프로토콜 5.7"처럼 절 번호로 씁니다. 대상 문서에서
# 절이 밀리면 링크는 멀쩡한 채 가리키는 곳만 틀립니다. 상대경로 검사는
# 파일 존재만 보므로 이것을 잡지 못합니다.
# 실제로 두 번 깨뜨렸습니다 — IA-FLOW 절 신설(#46), 프로토콜 5.7/5.8 순서(#49).
BADREF=$(python3 - <<'PY3'
import pathlib, re, sys

ALIAS = {
    "IA-FLOW": "IA-FLOW.md",
    "촬영 프로토콜": "CAPTURE-PROTOCOL.md",
    "프로토콜": "CAPTURE-PROTOCOL.md",
    "비전 파이프라인": "VISION-PIPELINE.md",
    "스켈레톤 오버레이": "SKELETON-OVERLAY.md",
    "작업 순서": "WORK-PLAN.md",
    "WORK-PLAN": "WORK-PLAN.md",
    "제품 개요": "PRODUCT-OVERVIEW.md",
    "디자인 시스템": "DESIGN-SYSTEM.md",
    "DESIGN-SYSTEM": "DESIGN-SYSTEM.md",
    "규약": "PIPELINE.md",
    "PIPELINE": "PIPELINE.md",
    "시스템 아키텍처": "ARCHITECTURE.md",
    "ARCHITECTURE": "ARCHITECTURE.md",
    "동시성": "CONCURRENCY.md",
    "CONCURRENCY": "CONCURRENCY.md",
    "ROADMAP": "ROADMAP.md",
    "REPOSITORY": "REPOSITORY.md",
    "IOS-STACK": "IOS-STACK.md",
    "BACKEND-STACK": "BACKEND-STACK.md",
}
# 흔한 낱말(저장소·로드맵·아키텍처 단독)은 넣지 않습니다 — "저장소 4.2GB"처럼
# 절 번호가 아닌 숫자를 잡아 오탐이 납니다. 대문자 파일명은 그 위험이 없습니다.

files = sorted(pathlib.Path("docs").rglob("*.md"))
secs = {}
for f in files:
    found = set(re.findall(r"^#{2,3} (\d+\.\d+)", f.read_text(encoding="utf-8"), re.M))
    if found:
        secs[f.name] = found

out = []
for f in files:
    text = f.read_text(encoding="utf-8")
    for alias, target in ALIAS.items():
        if target not in secs:
            continue
        for m in re.finditer(re.escape(alias) + r" (\d+\.\d+)", text):
            if m.group(1) not in secs[target]:
                out.append(f"{f}: \"{alias} {m.group(1)}\" — {target}에 그런 절이 없습니다")
print("\n".join(sorted(set(out))))
PY3
)
if [ -n "$BADREF" ]; then
  printf '%s\n' "$BADREF" | sed 's/^/    /'
  fail "없는 절을 가리키는 참조가 있습니다"
fi
ok "절 번호 참조 정상"

# ─────────────────────────────────────────────────────────────
step "타임라인 정합"
# WORK-PLAN 9.2의 타임라인은 9.3~9.5 단계 절의 요약입니다. 손으로 맞춰야
# 하고, 실제로 네 번 빠뜨렸습니다 — 0-D 분리(#39), 1-F 신설(#44),
# 0-D 기간 재배분(#56), Phase 0 기간(#57).
DRIFT=$(python3 - <<'PY4'
import pathlib, re

text = pathlib.Path("docs/04-계획/WORK-PLAN.md").read_text(encoding="utf-8")

block = re.search(r"## 9\.2 전체 타임라인.*?```\n(.*?)```", text, re.S)
if not block:
    print("9.2 타임라인 블록을 찾지 못했습니다")
    raise SystemExit

DUR = re.compile(r"\d[\d.~]*\s*[일주]")

def duration(chunk):
    """괄호 안에서 기간 토큰만 뽑는다. '(책상, 2~3일)' → '2~3일'"""
    m = DUR.search(chunk or "")
    return m.group(0).replace(" ", "") if m else None

# 타임라인 줄. 한 단계가 여러 줄로 쪼개질 수 있다 (0-D 1~5 / 6~8)
tl = {}
for line in block.group(1).splitlines():
    m = re.search(r"(\d-[A-F]′?)", line)
    if not m:
        continue
    paren = re.search(r"\(([^)]*)\)", line)
    tl.setdefault(m.group(1), []).append(duration(paren.group(1) if paren else ""))

# 단계 절 제목. Phase 2는 표로 되어 있어 절이 없다 — 그쪽은 검사하지 않는다.
sec = {}
for m in re.finditer(r"^### (\d-[A-F]′?)\.([^\n]*)", text, re.M):
    paren = re.search(r"\(([^)]*)\)", m.group(2))
    sec[m.group(1)] = duration(paren.group(1) if paren else "")

out = []

# 1) 절에 있는데 타임라인에 없다 — 이것이 실제로 네 번 중 두 번이었다
for stage in sorted(set(sec) - set(tl)):
    out.append(f"9.2 타임라인에 {stage}가 없습니다 (9.3~9.5에는 있음)")

# 2) 기간 불일치. 타임라인에서 한 줄뿐일 때만 본다 —
#    여러 줄이면 일부러 쪼갠 것이고(0-D), 합계 검증은 과하다.
for stage in sorted(set(tl) & set(sec)):
    rows = tl[stage]
    if len(rows) != 1 or rows[0] is None or sec[stage] is None:
        continue
    if rows[0] != sec[stage]:
        out.append(
            f"{stage} 기간 불일치 — 타임라인 '{rows[0]}' vs 절 제목 '{sec[stage]}'"
        )

print("\n".join(out))
PY4
)
if [ -n "$DRIFT" ]; then
  printf '%s\n' "$DRIFT" | sed 's/^/    /'
  fail "9.2 타임라인이 단계 절과 어긋납니다"
fi
ok "타임라인 일치"

printf '\n\033[32m=== 문서 게이트 통과 ===\033[0m\n'
