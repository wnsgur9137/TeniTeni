import Domain
import Foundation
import Testing
@testable import Presentation

private func cid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

private func session(fileNames: [String]) -> Session {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return Session(
        id: cid(0),
        startedAt: start,
        situation: .ballMachine,
        fps: 120,
        clips: fileNames.enumerated().map { index, name in
            Clip(
                id: cid(100 + index),
                fileName: name,
                recordedAt: start.addingTimeInterval(Double(index) * 10),
                fps: 120,
                swings: [
                    Swing(
                        id: cid(200 + index),
                        startSeconds: 1, endSeconds: 3, impactSeconds: 2
                    )
                ]
            )
        }
    )
}

private func locator(present: Set<String>) -> ClipLocator {
    ClipLocator(directory: URL(filePath: "/clips")) { present.contains($0.lastPathComponent) }
}

/// 목록이 "스윙 12개"라고 말하고 열면 재생할 것이 없는 상태를 없앤다.
/// 레퍼런스 조사에서 반복된 불만이 **"사라졌다"**였고 이것이 그 가장 나쁜
/// 형태다.
///
/// 근거: docs/07-기획/SPEC-0120-missing-clip.md
@Suite("클립 결손 판정")
struct ClipAvailabilityTests {

    @Test("전부 있으면 all이다")
    func 전부_있음() {
        let availability = ClipAvailability.of(
            session(fileNames: ["a.mov", "b.mov"]),
            locator: locator(present: ["a.mov", "b.mov"])
        )
        #expect(availability == .all)
        #expect(availability.notice == nil)
        #expect(availability.hasAnything)
    }

    @Test("전부 없으면 none이다")
    func 전부_없음() {
        let availability = ClipAvailability.of(
            session(fileNames: ["a.mov", "b.mov"]),
            locator: locator(present: [])
        )
        #expect(availability == .missing)
        #expect(availability.notice == "영상이 없습니다")
        #expect(availability.hasAnything == false)
    }

    /// 둘을 합치면 **클립 9개 중 1개가 없는 세션에도 "영상이 없습니다"**가
    /// 붙는다. 사용자가 열지 말지를 그 한 줄로 판단한다.
    @Test("일부만 없으면 partial이고 문구가 다르다")
    func 일부_없음() {
        let availability = ClipAvailability.of(
            session(fileNames: ["a.mov", "b.mov", "c.mov"]),
            locator: locator(present: ["a.mov", "c.mov"])
        )
        #expect(availability == .partial)
        #expect(availability.notice == "영상 일부 없음")
        #expect(availability.hasAnything)
        // 세 문구가 서로 다르다 — 합쳐지면 구분이 사라진다.
        #expect(ClipAvailability.partial.notice != ClipAvailability.missing.notice)
    }

    @Test("아홉 개 중 하나만 없어도 partial이다")
    func 하나만_없음() {
        let names = (0..<9).map { "clip-\($0).mov" }
        let availability = ClipAvailability.of(
            session(fileNames: names),
            locator: locator(present: Set(names.dropLast()))
        )
        #expect(availability == .partial)
    }

    /// ⚠️ **스윙 0개로 끝난 세션은 결손이 아니다.** 찍을 것이 없었을 뿐이고
    /// 그 세션은 진단 화면이 맡는다(SPEC-0110). `.missing`으로 떨어뜨리면
    /// **"영상이 없습니다"가 정상 세션에 붙는다.**
    @Test("클립이 0개면 all이다 — 결손이 아니다")
    func 클립_0개() {
        let availability = ClipAvailability.of(
            session(fileNames: []),
            locator: locator(present: [])
        )
        #expect(availability == .all)
        #expect(availability.notice == nil)
    }

    /// 빈 이름은 디렉터리 자신을 가리킨다 — `ClipLocator`가 막는다.
    @Test("빈 파일 이름은 없는 것으로 센다")
    func 빈_이름() {
        #expect(
            ClipAvailability.of(fileNames: [""], locator: locator(present: ["", "a.mov"]))
                == ClipAvailability.missing
        )
    }

    @Test("파일 이름만으로도 판정한다")
    func 이름_목록() {
        #expect(
            ClipAvailability.of(fileNames: ["a.mov"], locator: locator(present: ["a.mov"]))
                == .all
        )
        #expect(ClipAvailability.of(fileNames: [], locator: locator(present: [])) == .all)
    }
}
