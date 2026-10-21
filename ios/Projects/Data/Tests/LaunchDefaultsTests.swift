import Foundation
import Testing
@testable import Data

@Suite("LaunchDefaults")
struct LaunchDefaultsTests {

    @Test("실행 인자가 없으면 표준 저장소를 쓴다")
    func 평소() {
        #expect(LaunchDefaults.resolve(arguments: ["TeniTeni"]) === UserDefaults.standard)
    }

    @Test("UI 테스트 인자가 있으면 표준 저장소를 쓰지 않는다")
    func 분리() {
        let defaults = LaunchDefaults.resolve(arguments: ["TeniTeni", "-ui-testing"])
        #expect(defaults !== UserDefaults.standard)
    }

    /// 이 보장이 전부다 — **앞선 실행이 남긴 것이 다음 실행에 보이지 않는다.**
    /// 스위트를 나누기만 하고 비우지 않으면 첫 실행 이후로는 똑같이 오염된다.
    @Test("실행마다 비워진다")
    func 비워짐() {
        let key = "teniteni.launchdefaults.probe"
        let first = LaunchDefaults.resolve(arguments: ["-ui-testing"])
        first.set("남은 값", forKey: key)
        #expect(first.string(forKey: key) == "남은 값")

        let second = LaunchDefaults.resolve(arguments: ["-ui-testing"])
        #expect(second.string(forKey: key) == nil)
    }

    @Test("표준 저장소는 건드리지 않는다")
    func 표준_보존() {
        let key = "teniteni.launchdefaults.standard.probe"
        UserDefaults.standard.set("지켜야 한다", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        _ = LaunchDefaults.resolve(arguments: ["-ui-testing"])

        #expect(UserDefaults.standard.string(forKey: key) == "지켜야 한다")
    }
}
