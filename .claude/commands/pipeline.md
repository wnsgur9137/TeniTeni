# /pipeline

작업 파악부터 병합까지 10단계를 순서대로 수행한다.

**규약은 `docs/09-프로세스/PIPELINE.md`에 있다. 시작 전에 반드시 읽고 그대로 따른다.**
이 파일은 절차만 담는다 — 라벨 체계·실행 매트릭스·게이트 목록·검증 체크리스트는 규약 문서가 정본이다.

한국어로 응답한다. 각 단계 결과를 한 줄로 보고하며 진행한다.

## 입력 인자

사용자가 넘긴 인자: `$ARGUMENTS`

- `<이슈번호>`: 해당 이슈로 바로 진행 (1~2단계 생략)
- `--from=N`: N단계부터 재개
- `--stop-at=N`: N단계까지만
- `--merge=critical|auto|confirm`: 병합 처리 (기본 `critical`)
- `--type=`, `--area=`: 라벨 강제 지정
- `-h`, `--help`: 도움말 출력 후 종료

### Help Mode

`-h`/`--help`면 아래만 출력하고 아무것도 실행하지 않는다.

```
=== /pipeline 도움말 ===

Usage: /pipeline [이슈번호] [options]
Example: /pipeline
         /pipeline 12
         /pipeline --from=6 --merge=confirm

-- 단계 --
  1 현재 작업 파악    2 예정 작업 파악   3 진행 작업 확정
  4 레퍼런스(조건부)  5 기존 설계 파악   6 기획서(조건부)
  7 디자인(조건부)    8 개발(조건부)     9~10 /ship 위임

-- Options --
  --from=N       N단계부터 재개
  --stop-at=N    N단계까지만
  --merge=       critical(기본) | auto | confirm
  --type=        feature|bugfix|refactor|docs|chore
  --area=        ios-ui|ios-core|backend|ml|docs
  -h, --help     이 도움말

-- 정지 조건 --
  게이트 실패 · 반복 20회 초과 · 리뷰 CRITICAL 미해소 · merge conflict
  → 그 단계에서 멈추고 원인을 보고한다.
========================
```

---

## 인증

이 저장소의 GitHub API 작업은 **개인 계정 토큰**이 필요하다. 모든 `gh` 호출 전에:

```bash
export GH_TOKEN="$WNSGUR9137_GITHUB_TOKEN"
unset GITHUB_TOKEN
```

`GITHUB_TOKEN`(회사 계정)은 이 저장소 권한이 없고 keyring보다 우선한다. 자세한 내용은 `docs/03-기술스택/REPOSITORY.md` 7.6절.

## 진행 상태 판정

**상태 파일을 만들지 마라.** 매 실행 시작 시 실물을 조회해 어디까지 됐는지 판정한다 (규약 12.10절의 표).

`--from`이 주어지면 그 단계부터, 없으면 판정 결과의 다음 단계부터 시작한다.
`--from=N`의 선행 조건이 충족되지 않으면 **중단하고 무엇이 빠졌는지 알린다.**

---

## 1단계: 현재 작업 상황 파악

```bash
gh issue list --repo wnsgur9137/TeniTeni --state open --json number,title,labels,milestone
gh api repos/wnsgur9137/TeniTeni/milestones --jq '.[] | "\(.title): \(.closed_issues)/\(.open_issues + .closed_issues)"'
```

- 열린 이슈, 마일스톤별 진행률, `in-progress` 라벨이 붙은 작업을 요약한다
- 진행 중이던 작업이 있으면 **그것을 이어받을지 먼저 묻는다**

## 2단계: 예정 작업 파악

- 현재 마일스톤의 열린 이슈를 우선순위대로 정렬한다
- `blocked` 라벨이 붙은 것은 후보에서 빼되 **사유와 함께 보여준다**
- 이슈가 없으면 `docs/04-계획/WORK-PLAN.md`의 다음 단계를 보고 이슈 생성을 제안한다

## 3단계: 진행 작업 확정

- 후보 **2~3개를 한 줄 근거와 함께** 제시하고 고르게 한다 (AskUserQuestion)
- 인자로 이슈 번호가 왔으면 이 단계를 생략한다
- `type:`/`area:` 라벨 확인 → 없으면 추론해 제안하고, 승인 시 부여한다
- 선택된 이슈에 `in-progress` 라벨을 붙인다
- **실행 매트릭스**(규약 12.3)로 4·6·7·8 실행 여부를 결정하고 한 줄로 알린다

작업 브랜치를 만든다. 이름은 `<type>/<이슈번호>-<slug>` (예: `feat/12-swing-detector`).

## 4단계: 레퍼런스 확인 (조건부)

매트릭스에서 실행 대상일 때만.

- `docs/08-레퍼런스/`에서 관련 앱 문서를 찾는다
- 프론트매터 `researched`가 **3개월 이내면 읽고 통과** — 재조사하지 않는다
- 초과하거나 문서가 없으면 조사한다
  - `claude-in-chrome` 시도 → 실패하면 **`WebFetch`로 전환** (파이프라인을 막지 않는다)
  - 얻을 것: 지표 정의 · 기능 범위 · 사용자 불만
  - **시각적 모방은 하지 않는다**
- 문서에 섹션을 추가하고 `researched`를 갱신한다

## 5단계: 기존 설계 파악

이슈와 관련된 문서를 읽는다. 최소한 다음은 확인한다.

- `docs/INDEX.md`에서 관련 문서 식별
- 해당 영역의 설계 문서 (`02-설계/`, `03-기술스택/`)
- 관련 결정 (`05-결정/DECISION-LOG.md`의 확정 요약, 해당 D-xx·ADR)
- `area:ios-ui`면 `06-디자인/IA-FLOW.md`, `DESIGN-SYSTEM.md`

**설계와 어긋나는 작업이면 여기서 멈추고 알린다.** 설계를 먼저 고칠지, 예외로 진행할지는 사용자 판단이다.

## 6단계: 기획서 작성·검증 (조건부)

- `docs/_templates/기획서.md`에서 시작해 `docs/07-기획/SPEC-<이슈번호 4자리>-<slug>.md` 작성
- **이미 결정된 사항은 재론하지 않고 링크만 건다.** 대안 검토는 이번 작업 범위의 구현 선택지로 한정
- 규약 12.5의 체크리스트로 검증
- 이슈 본문에 요약 3줄 + 기획서 링크를 추가한다

## 7단계: 디자인 작성·검증 (조건부)

`area:ios-ui` + `type:feature`에서만.

- `design` 스킬 사용. 차트가 있으면 `dataviz`도 로드
- **기존 캔버스가 있으면 갱신한다.** 새 캔버스를 남발하지 않는다
- `DESIGN-SYSTEM.md` 토큰만 사용
- 규약 12.6의 체크리스트로 검증

## 8단계: 개발·검증 (조건부)

**코드가 바뀌면 항상 반복 개발 모드를 사용한다** (`type:docs`/`area:docs` 제외).

```
Skill(skill="oh-my-claudecode:ralph", args="<이슈 제목> — 종료 조건: <게이트 스크립트> 통과, 경고 0")
```

**상한을 직접 감시한다.** 매 반복마다:

```bash
ITER=$(python3 -c "import json;print(json.load(open('.omc/state/ralph-state.json'))['iteration'])" 2>/dev/null || echo 0)
```

`ITER >= 20`이면 즉시 `/oh-my-claudecode:cancel`을 호출하고 중단 보고한다.
훅의 자체 카운터(최대 100)는 지정 상한을 반영하지 않으므로 이 감시가 없으면 20회가 지켜지지 않는다.

**게이트**는 `area:` 라벨로 고른다 (규약 12.7의 표). 없는 영역은 경고 후 통과하되 PR 본문에 명시한다.

게이트 통과 후 `/oh-my-claudecode:cancel`로 모드를 정리한다.

## 9~10단계: /ship 위임

```
/ship --from=2 --merge=<옵션>
```

`/ship`이 commit → Draft PR → 리뷰 → 반영 → Ready → 병합을 처리한다. **재구현하지 마라.**

`/ship`에 넘길 맥락:
- 이슈 번호와 제목 (PR 본문에 `Closes #N`)
- 기획서 링크
- 게이트 결과
- 미수행 검증 항목 (실기기 등)

병합 후 이슈에서 `in-progress` 라벨을 제거한다 (`Closes #N`으로 자동 종료되지 않는 경우).

---

## 최종 보고

```
=== /pipeline 완료 ===
- 이슈     : #NN <제목>  [type:x / area:y]
- 실행 단계 : 1,2,3,(4),5,(6),(7),8,9,10
- 레퍼런스  : 갱신 | 재사용(researched: YYYY-MM-DD) | 생략
- 기획서    : docs/07-기획/SPEC-NNNN-*.md | 생략
- 디자인    : <URL> | 생략
- 개발      : 반복 N회 · 게이트 통과 | 게이트 없음(경고)
- PR        : #NN <URL> (병합됨 | Ready | Draft)
- 병합      : <sha> | 미수행(사유)

미완 사항
- <실기기 검증 등 사람이 해야 할 일>
- <미반영 리뷰 지적과 사유>
```

## 안전 규칙

- **force push · base 브랜치 직접 커밋을 하지 않는다.**
- 게이트 실패를 우회하려고 테스트를 지우거나 약화시키지 않는다.
- 중단할 때는 **어느 단계에서 왜 멈췄는지**와 `--from=N` 재개 방법을 함께 알린다.
- 검증하지 않은 것을 검증했다고 보고하지 않는다. 실기기처럼 못 한 것은 못 했다고 적는다.
- 자가 검증에는 작성자=리뷰어 사각이 있다. PR과 리뷰 코멘트에 명시한다.
