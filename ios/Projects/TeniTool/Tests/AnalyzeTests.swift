import Foundation
import Testing
@testable import TeniToolKit

// MARK: - 임팩트 매칭

/// 기준은 docs/02-설계/CAPTURE-PROTOCOL.md 5.5절이 정했다.
/// **이 경계가 틀리면 검출률이 통째로 틀어진다** — 게이트 판정의 근거다.
@Suite("임팩트 매칭")
struct ImpactMatcherTests {

    private func candidate(_ start: Int, _ duration: Double = 0.3) -> ImpactMatcher.Candidate {
        .init(startFrame: start, durationSec: duration)
    }

    @Test("±3프레임 경계", arguments: [
        (97, true), (98, true), (99, true), (100, true),
        (101, true), (102, true), (103, true),
        (96, false), (104, false),
    ])
    func 프레임_경계(_ startFrame: Int, _ shouldMatch: Bool) {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(startFrame)], impactFrames: [100]
        )
        #expect((outcome.matches[0] != nil) == shouldMatch, "startFrame \(startFrame)")
        #expect(outcome.hits == (shouldMatch ? 1 : 0))
    }

    @Test("0.2초 미만은 매칭하지 않는다", arguments: [
        (0.199, false), (0.2, true), (0.21, true), (0.1, false), (0.0, false),
    ])
    func 지속_경계(_ duration: Double, _ shouldMatch: Bool) {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(100, duration)], impactFrames: [100]
        )
        #expect((outcome.matches[0] != nil) == shouldMatch, "duration \(duration)")
    }

    /// "궤적 하나라도 잡히면 성공"으로 하면 검출률이 부풀려진다.
    @Test("한 임팩트에 여러 궤적이 걸리면 가장 가까운 하나만")
    func 중복_매칭() {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(103), candidate(100), candidate(102)],
            impactFrames: [100]
        )
        #expect(outcome.hits == 1)
        #expect(outcome.falsePositives == 2)
        // 거리 0인 두 번째 후보가 이겨야 한다
        #expect(outcome.matches[1] == 100)
        #expect(outcome.matches[0] == nil)
        #expect(outcome.matches[2] == nil)
    }

    @Test("임팩트가 여럿이면 각각 하나씩 매칭한다")
    func 다중_임팩트() {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(36), candidate(216), candidate(396)],
            impactFrames: [36, 216, 396]
        )
        #expect(outcome.hits == 3)
        #expect(outcome.falsePositives == 0)
        #expect(outcome.matches == [36, 216, 396])
    }

    @Test("무관한 궤적은 오검출로 센다")
    func 오검출() {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(36), candidate(500)],
            impactFrames: [36]
        )
        #expect(outcome.hits == 1)
        #expect(outcome.falsePositives == 1)
    }

    @Test("검출이 없으면 검출률 0")
    func 검출_없음() {
        let outcome = ImpactMatcher.match(candidates: [], impactFrames: [36, 216])
        #expect(outcome.hits == 0)
        #expect(ImpactMatcher.detectionRate(hits: 0, impactCount: 2) == 0)
    }

    /// 분모는 검출 개수가 아니라 **정답 타구 수**다.
    @Test("검출률 분모는 정답 타구 수")
    func 검출률_분모() {
        #expect(ImpactMatcher.detectionRate(hits: 2, impactCount: 3) == 2.0 / 3.0)
        #expect(ImpactMatcher.detectionRate(hits: 3, impactCount: 3) == 1.0)
        // 타구가 0이면 나눗셈이 정의되지 않는다
        #expect(ImpactMatcher.detectionRate(hits: 0, impactCount: 0) == 0)
    }

    @Test("정답이 비어 있으면 전부 오검출")
    func 정답_없음() {
        let outcome = ImpactMatcher.match(
            candidates: [candidate(36), candidate(216)], impactFrames: []
        )
        #expect(outcome.hits == 0)
        #expect(outcome.falsePositives == 2)
    }
}

// MARK: - 인자 검증

@Suite("analyze 인자")
struct AnalyzeArgumentTests {

    /// `parse`가 파싱 시점에 `validate()`까지 부른다. 따로 호출할 필요가 없고,
    /// 나눠 쓰면 검증 실패가 parse에서 터져 테스트가 엉뚱하게 깨진다.
    @Test("trajectoryLength는 5 이상이어야 한다", arguments: ["4", "3", "0", "-1"])
    func 최소_길이(_ value: String) {
        #expect(throws: (any Error).self) {
            // `--opt -1` 형태는 -1을 옵션으로 해석하므로 = 표기를 쓴다
            try Analyze.parse(["/dev/null", "--trajectory-length=\(value)"])
        }
    }

    @Test("반지름 범위가 뒤집히면 거부")
    func 반지름_역전() {
        #expect(throws: (any Error).self) {
            try Analyze.parse(["/dev/null", "--min-radius", "0.02", "--max-radius", "0.01"])
        }
    }

    @Test("없는 영상은 거부")
    func 없는_파일() {
        #expect(throws: (any Error).self) {
            try Analyze.parse(["/does/not/exist.mov"])
        }
    }

    @Test("없는 정답 파일은 거부")
    func 없는_정답() {
        #expect(throws: (any Error).self) {
            try Analyze.parse(["/dev/null", "--ground-truth", "/does/not/exist.json"])
        }
    }

    @Test("기본값이 프로토콜 5.4의 초기값과 같다")
    func 기본값() throws {
        let command = try Analyze.parse(["/dev/null"])
        #expect(command.trajectoryLength == 5)
        #expect(command.minRadius == 0.002)
        #expect(command.maxRadius == 0.015)
    }

    @Test("5는 통과한다 — 경계가 배타적이지 않다")
    func 최소_경계() throws {
        let command = try Analyze.parse(["/dev/null", "--trajectory-length", "5"])
        #expect(command.trajectoryLength == 5)
    }
}
