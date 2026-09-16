import Foundation

/// 주 사용 손. **분석의 전제**이지 취향 설정이 아니다.
///
/// 이 값이 없으면 정할 수 없는 것들:
/// - 스켈레톤에서 **라켓 잡은 팔**(시안색)을 어느 쪽으로 칠할지
/// - 포핸드/백핸드 분류 (좌우가 뒤집힌다)
/// - 촬영 배치 안내 — 선수의 앞/뒤 중 어느 쪽이 카메라를 향하는지
///
/// `VISION-PIPELINE` 3.3이 구간 검출의 주 신호로 `dominantHand`를 쓴다.
/// 온보딩에서 **반드시** 받는다 — docs/06-디자인/IA-FLOW.md 10.7
public enum Handedness: String, Sendable, Codable, CaseIterable {
    case right
    case left

    public var label: String {
        switch self {
        case .right: "오른손"
        case .left: "왼손"
        }
    }
}
