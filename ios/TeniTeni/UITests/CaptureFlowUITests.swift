import XCTest

/// 촬영 흐름의 **배선**을 잡는다.
///
/// 단위 테스트는 reducer까지만 닿는다. `onAppear`가 방향을 잠그는지,
/// `fullScreenCover`가 실제로 뜨는지는 뷰 계층에서만 일어나므로
/// 상수 대 상수 비교로는 배선이 끊겨도 통과한다 — SPEC-0078이 고치겠다고
/// 적은 "아무도 읽지 않는 죽은 선언"이 바로 그 양식이었다.
///
/// 근거: 이슈 #83
final class CaptureFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // 앞 테스트가 촬영(가로)에서 죽으면 방향이 남는다. `tearDown`만으로는
        // 모자라다 — 죽은 테스트는 `tearDown`을 돌지 못한다. 가로로 시작하면
        // 홈의 아래쪽 카드가 화면 밖으로 밀려 **탭이 조용히 먹지 않고**,
        // 무관한 테스트가 "피커가 안 뜬다"로 실패한다.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
        completeOnboardingIfNeeded()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    // MARK: 전환

    func test_시작을_누르면_프레이밍_가이드가_뜬다() {
        choose(situation: "볼머신")
        tapStart()

        XCTAssertTrue(
            app.staticTexts["선수가 네모 안에 들어오게 두세요"].waitForExistence(timeout: 10),
            "홈의 '시작'이 촬영을 열어야 한다"
        )
        XCTAssertTrue(app.staticTexts["볼머신 · 내 스윙"].exists, "무엇을 찍는지 계속 보여야 한다")
        XCTAssertTrue(app.buttons["뒤로"].exists)
        XCTAssertTrue(app.buttons["촬영 시작"].exists)
    }

    func test_뒤로를_누르면_홈으로_돌아온다() {
        choose(situation: "볼머신")
        tapStart()
        XCTAssertTrue(app.buttons["뒤로"].waitForExistence(timeout: 10))

        app.buttons["뒤로"].tap()

        XCTAssertTrue(homeHeader.waitForExistence(timeout: 10), "촬영을 닫으면 홈으로 돌아와야 한다")
    }

    func test_라인_판정을_고르면_안내가_달라진다() {
        choose(situation: "시합")
        let lineCall = app.buttons["라인 판정"]
        XCTAssertTrue(lineCall.waitForExistence(timeout: 5), "시합에서만 관찰 대상이 나타난다")
        lineCall.tap()
        tapStart()

        XCTAssertTrue(
            app.staticTexts["라인이 화면을 가로지르게 두세요"].waitForExistence(timeout: 10),
            "배치가 다르면 가이드도 달라야 한다"
        )
        XCTAssertFalse(
            app.staticTexts["선수가 네모 안에 들어오게 두세요"].exists,
            "내 스윙 안내가 남아 있으면 안 된다"
        )
    }

    // MARK: 방향

    func test_촬영은_가로를_유지하고_나오면_푼다() {
        choose(situation: "볼머신")
        XCTAssertTrue(waitUntil { !self.isLandscape }, "홈은 세로다")

        tapStart()
        XCTAssertTrue(app.buttons["뒤로"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { self.isLandscape }, "촬영 흐름은 가로로 뜬다")

        // 기기를 세로로 돌려도 따라가지 않는다 — 폰은 삼각대 위에 가로로 있다.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: 3) { self.isLandscape }, "촬영 중에는 가로를 유지한다")

        app.buttons["뒤로"].tap()
        XCTAssertTrue(homeHeader.waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            waitUntil { !self.isLandscape },
            "나오면 잠금이 풀려야 한다 — 풀지 않으면 세로 화면 12종이 가로로 남는다"
        )
    }

    // MARK: 도우미

    private var homeHeader: XCUIElement { app.staticTexts["오늘은 어떻게 치나요"] }

    private var isLandscape: Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
    }

    /// 상황 카드는 접근성 레이블에 배치 안내까지 합쳐진다. 앞글자로 찾는다.
    private func choose(situation: String) {
        XCTAssertTrue(homeHeader.waitForExistence(timeout: 10), "홈이 떠야 한다")
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", situation)
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "\(situation) 카드가 있어야 한다")
        card.tap()
    }

    private func tapStart() {
        app.buttons["시작"].tap()
        allowSystemPermissionsIfAsked()
    }

    /// 카메라·마이크 다이얼로그. 처음 한 번만 뜨므로 없으면 바로 빠진다.
    private func allowSystemPermissionsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            let allow = springboard.buttons["허용"]
            guard allow.waitForExistence(timeout: 3) else { return }
            allow.tap()
        }
    }

    /// 온보딩은 설치 직후 한 번만 뜬다. CI는 매번 새 시뮬레이터다.
    private func completeOnboardingIfNeeded() {
        let begin = app.buttons["시작하기"]
        guard begin.waitForExistence(timeout: 10) else { return }
        begin.tap()
        let hand = app.buttons["오른손"]
        XCTAssertTrue(hand.waitForExistence(timeout: 5), "주 사용 손을 물어야 한다")
        hand.tap()
        app.buttons["다음"].tap()
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
