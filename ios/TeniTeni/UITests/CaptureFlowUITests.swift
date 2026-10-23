import XCTest

/// 촬영 흐름의 **배선**을 잡는다.
///
/// 단위 테스트는 reducer까지만 닿는다. `onAppear`가 방향을 잠그는지,
/// `fullScreenCover`가 실제로 뜨는지는 뷰 계층에서만 일어나므로
/// 상수 대 상수 비교로는 배선이 끊겨도 통과한다 — SPEC-0078이 고치겠다고
/// 적은 "아무도 읽지 않는 죽은 선언"이 바로 그 양식이었다.
///
/// ## 왜 `@MainActor`인가
///
/// `XCUIApplication`·`XCUIElement`·`XCUIDevice`는 전부 `@MainActor`다.
/// 격리를 선언하지 않으면 호출 하나하나가 경고가 되어 **77건**이 쌓였고,
/// 그만큼 새 경고가 노이즈에 묻혔다.
///
/// 클래스에 `@MainActor`를 붙이면 `setUp()`·`tearDown()`을 **async
/// 오버라이드로 바꿔야 한다.** 상위의 동기 메서드는 nonisolated라
/// 동기 오버라이드로 덮으면 격리가 어긋나 `sending 'self' risks causing
/// data races`가 난다. async 변형은 XCTest가 따로 제공하므로 그 충돌이
/// 없다.
///
/// 근거: 이슈 #83, #88
@MainActor
final class CaptureFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // 앞 테스트가 촬영(가로)에서 죽으면 방향이 남는다. `tearDown`만으로는
        // 모자라다 — 죽은 테스트는 `tearDown`을 돌지 못한다. 가로로 시작하면
        // 홈의 아래쪽 카드가 화면 밖으로 밀려 **탭이 조용히 먹지 않고**,
        // 무관한 테스트가 "피커가 안 뜬다"로 실패한다.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // 앞선 실행이 남긴 선택·온보딩 완료를 지운다. 없으면 테스트 결과가
        // **그 시뮬레이터에 무엇이 남아 있었는지**에 달린다 — #88
        app.launchArguments = ["-ui-testing"]
        app.launch()
        completeOnboarding()
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
        try await super.tearDown()
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

    func test_촬영은_가로를_유지하고_나오면_푼다() async {
        choose(situation: "볼머신")
        // `XCTAssertTrue`의 autoclosure는 async를 받지 못한다. 먼저 기다린
        // 결과를 변수에 담아 넘긴다.
        let homeIsPortrait = await waitUntil { !self.isLandscape }
        XCTAssertTrue(homeIsPortrait, "홈은 세로다")

        tapStart()
        XCTAssertTrue(app.buttons["뒤로"].waitForExistence(timeout: 10))
        let captureIsLandscape = await waitUntil { self.isLandscape }
        XCTAssertTrue(captureIsLandscape, "촬영 흐름은 가로로 뜬다")

        // 기기를 세로로 돌려도 따라가지 않는다 — 폰은 삼각대 위에 가로로 있다.
        XCUIDevice.shared.orientation = .portrait
        let staysLandscape = await waitUntil(timeout: 3) { self.isLandscape }
        XCTAssertTrue(staysLandscape, "촬영 중에는 가로를 유지한다")

        app.buttons["뒤로"].tap()
        XCTAssertTrue(homeHeader.waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .portrait
        let releasedToPortrait = await waitUntil { !self.isLandscape }
        XCTAssertTrue(
            releasedToPortrait,
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

    /// 상태를 비우고 시작하므로 온보딩은 **항상** 뜬다.
    ///
    /// 뜨지 않으면 상태가 비워지지 않은 것이다. 조용히 넘어가면 그 뒤의
    /// 실패가 엉뚱한 곳을 가리킨다 — 전에는 `guard`로 빠져나가며 10초를
    /// 버리고, 남은 선택 때문에 무관한 단정이 깨졌다.
    private func completeOnboarding() {
        let begin = app.buttons["시작하기"]
        XCTAssertTrue(
            begin.waitForExistence(timeout: 10),
            "온보딩이 떠야 한다 — 뜨지 않으면 앱 상태가 비워지지 않은 것이다"
        )
        begin.tap()
        let hand = app.buttons["오른손"]
        XCTAssertTrue(hand.waitForExistence(timeout: 5), "주 사용 손을 물어야 한다")
        hand.tap()
        app.buttons["다음"].tap()
    }

    /// 조건이 참이 될 때까지 기다린다.
    ///
    /// `Thread.sleep`이 아니라 `Task.sleep`이다. 이 클래스는 `@MainActor`이고
    /// 화면 조회도 전부 그 위에서 돈다 — 스레드를 막으면 **기다리는 동안
    /// 아무것도 못 한다.**
    private func waitUntil(
        timeout: TimeInterval = 5, _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }
}
