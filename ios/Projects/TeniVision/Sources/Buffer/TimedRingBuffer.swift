import Foundation

/// 최근 N초를 들고 있다가 소급해서 꺼내는 버퍼.
///
/// 스윙은 **감지된 뒤에** 그 전 구간이 필요하다. 트리거가 울린 시점에는
/// 이미 테이크백이 지나갔으므로, 계속 담고 있다가 되감아야 한다.
///
/// ## 용량을 시간으로 받는 이유
///
/// 프레임 수로 받으면 fps가 바뀔 때 조용히 어긋난다 — 120fps의 240프레임은
/// 2초지만 60fps면 4초다. [프로토콜 5.2](../../../../docs/02-설계/CAPTURE-PROTOCOL.md)가
/// fps를 사용자 선택으로 뒀고, 발열 시 120 → 60으로 낮추는 경로도 있어
/// **실제로 갈린다.**
///
/// 근거: docs/07-기획/SPEC-0070-persistence-foundation.md 구현 선택지 2
public struct TimedRingBuffer<Element>: Sendable where Element: Sendable {

    public struct Entry: Sendable {
        public let timestamp: TimeInterval
        public let value: Element

        public init(timestamp: TimeInterval, value: Element) {
            self.timestamp = timestamp
            self.value = value
        }
    }

    /// 들고 있을 시간. 이보다 오래된 것은 넣을 때 버린다.
    public let window: TimeInterval
    private var entries: [Entry] = []

    public init(window: TimeInterval) {
        precondition(window > 0, "window는 0보다 커야 한다")
        self.window = window
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// 가장 최근 타임스탬프. 비어 있으면 `nil`.
    public var latest: TimeInterval? { entries.last?.timestamp }

    /// 넣으면서 창 밖으로 나간 것을 버린다.
    ///
    /// - Note: 타임스탬프가 뒤로 가는 입력(되감기)은 상정하지 않는다.
    ///   프레임은 단조 증가한다.
    ///
    ///   전제가 깨지면 **조용히 틀린 구간이 나온다.** 전화 수신 등으로
    ///   `AVCaptureSession`이 중단됐다 재개되며 클럭이 리셋되면
    ///   `evict`의 `cutoff`가 과거로 돌아가 아무것도 버려지지 않고,
    ///   `latest`가 최댓값이 아니라 작은 값을 가리켜 `suffix(seconds:)`가
    ///   버퍼 전체를 돌려준다. 그런 경로를 만들면 `removeAll()` 후 다시
    ///   채워야 한다. 릴리스 비용이 0인 `assert`로 표시해 둔다.
    public mutating func append(_ value: Element, at timestamp: TimeInterval) {
        assert(
            timestamp >= (entries.last?.timestamp ?? -.infinity),
            "타임스탬프가 역행했다 (\(entries.last?.timestamp ?? 0) → \(timestamp))"
        )
        entries.append(Entry(timestamp: timestamp, value: value))
        evict(now: timestamp)
    }

    /// 마지막 `seconds`초를 오래된 것부터 돌려준다.
    ///
    /// `seconds`가 `window`보다 크면 갖고 있는 만큼만 나온다 — 버린 것을
    /// 되살릴 수는 없다.
    public func suffix(seconds: TimeInterval) -> [Element] {
        guard seconds > 0, let latest else { return [] }
        let cutoff = latest - seconds
        return entries.filter { $0.timestamp > cutoff }.map(\.value)
    }

    /// 두 시각 사이를 꺼낸다. 스윙 구간을 잘라낼 때 쓴다.
    public func range(from: TimeInterval, to: TimeInterval) -> [Element] {
        guard from <= to else { return [] }
        return entries.filter { $0.timestamp >= from && $0.timestamp <= to }.map(\.value)
    }

    /// 두 시각 사이를 **시각과 함께** 꺼낸다.
    ///
    /// 클립으로 쓸 때는 프레임마다 시각이 필요하다 — `range(from:to:)`는
    /// 값만 주므로 PTS를 매길 수 없다.
    public func slice(from: TimeInterval, to: TimeInterval) -> [Entry] {
        guard from <= to else { return [] }
        return entries.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    public mutating func removeAll() { entries.removeAll() }

    private mutating func evict(now: TimeInterval) {
        let cutoff = now - window
        // 유일한 호출자인 append가 **먼저 넣고** 부르므로 마지막 원소의
        // 타임스탬프는 now와 같고, window > 0이라 now > cutoff가 항상
        // 성립한다. 즉 최소 한 개는 남으며 nil이 될 수 없다 — "전부 창
        // 밖이라 마지막만 남긴다"는 분기는 도달하지 않는 코드였다.
        guard let firstKept = entries.firstIndex(where: { $0.timestamp > cutoff }) else { return }
        if firstKept > 0 { entries.removeFirst(firstKept) }
    }
}
