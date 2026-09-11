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
TOKENS_SWIFT="ios/TeniTeni/Sources/DesignSystem/Tokens.swift"
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

printf '\n\033[32m=== 문서 게이트 통과 ===\033[0m\n'
