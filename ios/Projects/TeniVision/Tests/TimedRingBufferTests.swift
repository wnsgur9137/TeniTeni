import Foundation
import Testing
@testable import TeniVision

/// fps를 주면 프레임 번호를 타임스탬프로 바꿔준다.
/// **같은 프레임 수라도 fps가 다르면 다른 시간**이라는 것이 이 버퍼의 요점이다.
private func timestamps(frames: Int, fps: Double, from: TimeInterval = 0) -> [TimeInterval] {
    (0..<frames).map { from + Double($0) / fps }
}

@Suite("TimedRingBuffer")
struct TimedRingBufferTests {

    // MARK: - 빈 버퍼

    @Test("빈 버퍼는 아무것도 주지 않는다")
    func 빈_버퍼() {
        let buffer = TimedRingBuffer<Int>(window: 2)
        #expect(buffer.isEmpty)
        #expect(buffer.count == 0)
        #expect(buffer.latest == nil)
        #expect(buffer.suffix(seconds: 1).isEmpty)
        #expect(buffer.range(from: 0, to: 10).isEmpty)
    }

    // MARK: - 창 밖 폐기

    @Test("창을 넘어가면 가장 오래된 것부터 버린다")
    func 폐기() {
        var buffer = TimedRingBuffer<Int>(window: 1)
        for i in 0..<30 { buffer.append(i, at: Double(i) / 10) }  // 0.0 ~ 2.9초

        // 마지막이 2.9초, 창이 1초 → 1.9초 초과만 남는다 (2.0 ~ 2.9의 10개)
        #expect(buffer.count == 10)
        #expect(buffer.suffix(seconds: 1) == Array(20..<30))
    }

    @Test("창 안이면 하나도 버리지 않는다")
    func 창_안() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        for i in 0..<30 { buffer.append(i, at: Double(i) / 10) }

        #expect(buffer.count == 30)
    }

    /// 경계값. `cutoff`와 **같은** 타임스탬프는 버린다 — `>` 이므로.
    /// 이걸 `>=`로 바꾸면 창이 한 프레임씩 길어진다.
    @Test("정확히 창 길이만큼 떨어진 것은 버린다")
    func 경계() {
        var buffer = TimedRingBuffer<String>(window: 2)
        buffer.append("a", at: 0)
        buffer.append("b", at: 1)
        buffer.append("c", at: 2)  // a는 정확히 2초 전 → 버린다

        #expect(buffer.count == 2)
        #expect(buffer.suffix(seconds: 5) == ["b", "c"])
    }

    @Test("한 번에 창을 통째로 건너뛰어도 방금 넣은 것은 남는다")
    func 큰_점프() {
        var buffer = TimedRingBuffer<Int>(window: 2)
        buffer.append(1, at: 0)
        buffer.append(2, at: 0.5)
        buffer.append(3, at: 100)  // 앞의 둘은 한참 밖

        #expect(buffer.count == 1)
        #expect(buffer.suffix(seconds: 2) == [3])
    }

    // MARK: - 마지막 N초

    /// ⚠️ **fps가 달라도 N초는 N초다.** 프레임 수로 용량을 받았다면
    /// 120fps와 60fps에서 다른 길이가 나왔을 것이다 — SPEC-0070 구현 선택지 2.
    @Test("fps가 달라도 마지막 2초가 나온다", arguments: [120.0, 60.0, 30.0])
    func fps_무관(_ fps: Double) {
        var buffer = TimedRingBuffer<Int>(window: 5)
        let stamps = timestamps(frames: Int(fps * 4), fps: fps)
        for (index, t) in stamps.enumerated() { buffer.append(index, at: t) }

        let last2 = buffer.suffix(seconds: 2)
        let span = stamps[stamps.count - last2.count] ... stamps[stamps.count - 1]

        #expect(span.upperBound - span.lowerBound < 2)
        #expect(Double(last2.count) == fps * 2, "\(fps)fps의 2초는 \(fps * 2)프레임이다")
    }

    @Test("창보다 긴 구간을 달라고 하면 가진 만큼만 준다")
    func 과다_요청() {
        var buffer = TimedRingBuffer<Int>(window: 1)
        for i in 0..<120 { buffer.append(i, at: Double(i) / 60) }  // 2초치

        #expect(buffer.suffix(seconds: 10).count == buffer.count)
        #expect(buffer.count < 120, "창 밖은 이미 버려졌다")
    }

    @Test("0초 이하를 달라고 하면 빈 배열이다")
    func 영_요청() {
        var buffer = TimedRingBuffer<Int>(window: 2)
        buffer.append(1, at: 0)

        #expect(buffer.suffix(seconds: 0).isEmpty)
        #expect(buffer.suffix(seconds: -1).isEmpty)
    }

    // MARK: - 구간 추출

    @Test("두 시각 사이를 꺼낸다 — 양끝 포함")
    func 구간() {
        var buffer = TimedRingBuffer<Int>(window: 100)
        for i in 0..<10 { buffer.append(i, at: Double(i)) }

        #expect(buffer.range(from: 3, to: 5) == [3, 4, 5])
    }

    @Test("뒤집힌 구간은 빈 배열이다")
    func 뒤집힌_구간() {
        var buffer = TimedRingBuffer<Int>(window: 100)
        for i in 0..<10 { buffer.append(i, at: Double(i)) }

        #expect(buffer.range(from: 5, to: 3).isEmpty)
    }

    @Test("버린 구간은 되살아나지 않는다")
    func 버린_구간() {
        var buffer = TimedRingBuffer<Int>(window: 1)
        for i in 0..<10 { buffer.append(i, at: Double(i)) }

        #expect(buffer.range(from: 0, to: 5).isEmpty)
    }

    // MARK: - 기타

    @Test("비우면 빈 버퍼가 된다")
    func 비우기() {
        var buffer = TimedRingBuffer<Int>(window: 2)
        buffer.append(1, at: 0)
        buffer.removeAll()

        #expect(buffer.isEmpty)
        #expect(buffer.latest == nil)
    }

    @Test("slice는 시각을 함께 돌려준다")
    func slice_시각() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        for (index, time) in timestamps(frames: 5, fps: 1).enumerated() {
            buffer.append(index, at: time)
        }

        let picked = buffer.slice(from: 1, to: 3)
        #expect(picked.map(\.value) == [1, 2, 3])
        #expect(picked.map(\.timestamp) == [1, 2, 3])
    }

    @Test("slice는 경계를 포함한다")
    func slice_경계() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        buffer.append(0, at: 0)
        buffer.append(1, at: 1)

        #expect(buffer.slice(from: 0, to: 1).count == 2)
        #expect(buffer.slice(from: 0, to: 0).map(\.value) == [0])
    }

    @Test("거꾸로 된 범위는 비어 있다")
    func slice_역범위() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        buffer.append(0, at: 0)
        buffer.append(1, at: 1)

        #expect(buffer.slice(from: 1, to: 0).isEmpty)
    }

    @Test("값 타입이라 복사본은 따로 논다")
    func 값_의미론() {
        var original = TimedRingBuffer<Int>(window: 10)
        original.append(1, at: 0)
        var copy = original
        copy.append(2, at: 1)

        #expect(original.count == 1)
        #expect(copy.count == 2)
    }
}

@Suite("장 수 상한")
struct TimedRingBufferCapacityTests {

    /// 카메라 프레임은 캡처 풀의 버퍼를 붙든다. 시간 창만 믿으면 60fps에서
    /// 180장을 들고 있게 되고 풀이 고갈된다 — #103.
    @Test("상한을 넘기면 오래된 것부터 버린다")
    func 상한_초과() {
        var buffer = TimedRingBuffer<Int>(window: 10, capacity: 3)
        for i in 0..<5 { buffer.append(i, at: Double(i) * 0.1) }
        #expect(buffer.count == 3)
        #expect(buffer.droppedByCapacity == 2)
        // 최신 셋이 남는다 — 임팩트 직전이 테이크백보다 중요하다.
        #expect(buffer.suffix(seconds: 10) == [2, 3, 4])
    }

    @Test("상한이 없으면 시간 창만으로 자른다")
    func 상한_없음() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        for i in 0..<100 { buffer.append(i, at: Double(i) * 0.01) }
        #expect(buffer.count == 100)
        #expect(buffer.droppedByCapacity == 0)
    }

    @Test("상한 안이면 아무것도 버리지 않는다")
    func 상한_이내() {
        var buffer = TimedRingBuffer<Int>(window: 10, capacity: 10)
        for i in 0..<5 { buffer.append(i, at: Double(i) * 0.1) }
        #expect(buffer.count == 5)
        #expect(buffer.droppedByCapacity == 0)
    }

    @Test("시간 창과 상한이 함께 걸리면 둘 다 적용된다")
    func 둘_다() {
        var buffer = TimedRingBuffer<Int>(window: 0.25, capacity: 10)
        for i in 0..<20 { buffer.append(i, at: Double(i) * 0.1) }
        // 창(0.25초)이 더 좁으므로 상한에는 닿지 않는다.
        #expect(buffer.count <= 3)
        #expect(buffer.droppedByCapacity == 0)
    }

    @Test("비우면 버린 수도 0으로 돌아간다")
    func 초기화() {
        var buffer = TimedRingBuffer<Int>(window: 10, capacity: 2)
        for i in 0..<5 { buffer.append(i, at: Double(i) * 0.1) }
        #expect(buffer.droppedByCapacity == 3)
        buffer.removeAll()
        #expect(buffer.droppedByCapacity == 0)
        #expect(buffer.isEmpty)
    }
}
