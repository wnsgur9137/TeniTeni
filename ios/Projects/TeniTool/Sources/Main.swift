import ArgumentParser
import TeniToolKit

// 실행 파일은 진입점만 갖는다. 커맨드 정의는 TeniToolKit에 있다 —
// 테스트가 링크할 수 있어야 하기 때문이다 (Project.swift 주석 참고).
@main
struct Main {
    static func main() async {
        await Teni.main()
    }
}
