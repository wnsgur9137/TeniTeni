import Domain
import Foundation
import Testing
@testable import Presentation

/// 화면에 찍히는 문자열. 순수 함수라 뷰 없이 고정할 수 있다.
///
/// 이 묶음이 있는 이유: 리플레이의 뷰 코드 대부분은 단위 테스트가 닿지
/// 않는다(`AVPlayerLayer`·`GeometryReader`·방향 잠금). **닿는 것만이라도
/// 고정해 둔다.**
@Suite("리플레이 표시 문자열")
struct ReplayTextTests {

    @Test("배속 라벨")
    func 배속_라벨() {
        #expect(PlaybackSpeed.eighth.label == "0.125×")
        #expect(PlaybackSpeed.quarter.label == "0.25×")
        #expect(PlaybackSpeed.half.label == "0.5×")
        #expect(PlaybackSpeed.normal.label == "1×")
    }

    @Test("배속 순서는 느린 것부터다")
    func 배속_순서() {
        // 화면이 `allCases`를 그대로 가로로 늘어놓는다. 순서가 뒤집히면
        // 왼쪽이 느린 쪽이라는 전제가 깨진다.
        #expect(PlaybackSpeed.allCases.map(\.rawValue) == [0.125, 0.25, 0.5, 1])
    }

    @Test("1×만 느린 재생이 아니다")
    func 슬로우모션_구분() {
        #expect(PlaybackSpeed.allCases.filter(\.isSlowMotion).count == 3)
        #expect(PlaybackSpeed.normal.isSlowMotion == false)
    }

    @Test("스윙 번호는 전체와 함께 보여준다")
    func 번호_표시() {
        let item = ReplayItem(
            clipID: UUID(),
            fileName: "a.mov",
            swing: Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5),
            clipFPS: 120,
            position: 12,
            total: 34
        )

        #expect(ReplayView.positionText(item) == "스윙 12 / 34")
        // 아직 못 읽었을 때도 자리를 비우지 않는다.
        #expect(ReplayView.positionText(nil) == "스윙")
    }

    @Test("요약의 스윙 행은 구간 안의 임팩트를 말한다")
    func 요약_행_문구() {
        // **클립 기준 절대초를 보여주면 사용자가 어디를 말하는지 모른다.**
        // 스윙이 5초에 시작해 임팩트가 5.6초면 "임팩트 0.60초"다.
        let swing = Swing(startSeconds: 5, endSeconds: 6.8, impactSeconds: 5.6)

        #expect(SessionSummaryView.swingDetail(swing) == "1.8초 · 임팩트 0.60초")
    }

    @Test("뒤집힌 구간에서도 음수를 적지 않는다")
    func 요약_행_방어() {
        let broken = Swing(startSeconds: 5, endSeconds: 4, impactSeconds: 3)

        #expect(SessionSummaryView.swingDetail(broken) == "0.0초 · 임팩트 0.00초")
    }

    @Test("스크러버 시각은 소수 두 자리다")
    func 스크러버_시각() {
        // 120fps에서 한 프레임이 8.3ms다. 소수 한 자리면 프레임 이동이
        // 화면에 드러나지 않는다.
        #expect(ReplayScrubberView.time(0) == "0.00")
        #expect(ReplayScrubberView.time(0.6166) == "0.62")
        #expect(ReplayScrubberView.time(-1) == "0.00")
    }
}
