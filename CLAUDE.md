# TeniTeni

테니스 스윙 분석 iOS 앱. Swift 6 / SwiftUI / TCA, Tuist 멀티모듈.

## 파이프라인 규약

**[docs/09-프로세스/PIPELINE.md](docs/09-프로세스/PIPELINE.md)가 정본이다.** 전역 `/pipeline` 커맨드는 이 문서를 읽고 그대로 따른다 — 라벨 체계(12.2) · 실행 매트릭스(12.3) · 기획서 선행 PR(12.5) · 게이트(12.7) · PR 단위(12.8)가 거기 있다.

## 이 저장소에서만 다른 것

### GitHub 인증

모든 `gh` 호출 전에:

```bash
export GH_TOKEN="$WNSGUR9137_GITHUB_TOKEN"
unset GITHUB_TOKEN
```

`GITHUB_TOKEN`(회사 계정)은 이 저장소 권한이 없고 **keyring보다 우선한다.** `git push`는 `origin`에 SSH alias가 박혀 있어 그대로 쓰면 된다. 근거: [docs/03-기술스택/REPOSITORY.md](docs/03-기술스택/REPOSITORY.md) 7.6절.

### 병합

**병합은 매번 명시적으로 지시받는다. 승인은 PR 간에 이어지지 않는다.** `--merge` 값과 무관하게 이 규칙이 우선한다.

PR Assignee는 항상 `wnsgur9137`.

### 게이트

| 영역 | 명령 |
|---|---|
| iOS | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify-ios.sh` (Xcode 26.6 필요) |
| 문서 | `./scripts/verify-docs.sh` |

**로컬 경고 집계는 증분 빌드라 숨은 경고가 있다.** 판정은 CI 전체 빌드 수치로 한다.

### 쓰지 않는 것

- **반복 개발 모드(`ralph`)** — 규약 12.7. 키워드 오발동으로 무관한 작업에 모드가 따라붙고 훅 카운터가 상한을 반영하지 않는다
- `` `pipeline` ``·`` `ralph` ``를 평문으로 쓰면 키워드 훅이 걸린다. 문서와 대화에서 **백틱으로 감싼다**
