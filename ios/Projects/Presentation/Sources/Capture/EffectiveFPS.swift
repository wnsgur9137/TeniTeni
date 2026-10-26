import Foundation
import Synchronization

/// 지금 실제로 적용된 촬영 fps를 담는 공유 상자.
///
/// ## 왜 상자인가
///
/// 이 값은 **메인에서 쓰이고(포맷 변경) 분석 Task에서 읽힌다**(클립 저장).
/// 비구조 `Task`로 actor에 넘기면 생성 순서대로 실행되지 않으므로, 발열
/// 강등과 클립 저장이 겹치는 순간 경계 클립에 **어느 값이 들어갈지 알 수
/// 없다.** 상자를 공유하면 읽는 쪽이 그 시점의 값을 본다.
///
/// `@unchecked Sendable`을 쓰지 않는다 — 동시성 6.1의 4항.
///
/// 근거: docs/07-기획/SPEC-0107-thermal-response.md
final class EffectiveFPS: Sendable {

    private let storage = Mutex<Int?>(nil)

    init() {}

    /// 아직 포맷을 읽지 않았으면 `nil`이다.
    var value: Int? { storage.withLock { $0 } }

    func set(_ fps: Int) {
        storage.withLock { $0 = fps }
    }

    func reset() {
        storage.withLock { $0 = nil }
    }
}
