import Foundation

/// 포즈를 몇 프레임에 한 번 돌릴지 정한다.
///
/// 120fps로 찍으면 프레임당 예산이 8.3ms로 반토막 난다. 사람 동작은 120Hz
/// 샘플링이 필요 없고 공은 필요하므로, **궤적은 전 프레임 · 포즈는 60fps**로
/// 간다 — [D-04](../../../../../docs/05-결정/stack/D-04-concurrency.md)의 스트림 분리.
///
/// 버리는 판단을 인테이크에서 하는 이유: 스트림의 `bufferingNewest(1)`는
/// **소비자가 밀릴 때만** 버린다. 소비자가 안 밀리면 120장이 전부 포즈로
/// 들어가 예산을 넘긴다. 버릴 것은 처음부터 보내지 않는다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
struct FrameDecimator: Sendable {

    /// 몇 프레임마다 한 장을 분석하는가. 1이면 전부.
    let stride: Int

    init(stride: Int) {
        self.stride = max(1, stride)
    }

    /// 촬영 fps에서 간격을 뽑는다. 분석 목표를 **넘지 않는** 가장 촘촘한 간격이다.
    ///
    /// 촬영이 분석 목표보다 느리면 1이다 — 없는 프레임을 만들 수는 없다.
    ///
    /// ## 왜 내림이 아닌가
    ///
    /// `actualFPS`는 `1 / activeVideoMinFrameDuration`에서 나오고, 그 값은
    /// 요청한 120이 아니라 기기가 정규화한 값이다 — **119.88(NTSC 계열)
    /// 포맷이 실존한다.** 내림하면 `119.88 / 60 = 1.998` → 1이 되어
    /// 데시메이션이 통째로 풀린다. 포즈가 초당 120회 돌고, **오류는 하나도
    /// 나지 않는다** — 기기에서 왜 느린지 알 단서가 없다.
    ///
    /// 그래서 2% 허용오차를 두고 올린다. 119.88 → 2, 59.94 → 1, 90 → 2.
    init(captureFPS: Double, analysisFPS: Double = 60) {
        guard captureFPS > 0, analysisFPS > 0 else {
            self.stride = 1
            return
        }
        self.stride = max(1, Int((captureFPS / analysisFPS - 0.02).rounded(.up)))
    }

    func includes(_ sequence: UInt64) -> Bool {
        sequence % UInt64(stride) == 0
    }
}
