import ArgumentParser
import Foundation

/// `1/1000` 같은 표기를 초 단위로 읽는다.
/// 프로젝트 문서가 전부 분수 표기를 쓰므로 CLI도 같은 표기를 받는다 —
/// 0.001을 넘기게 하면 문서의 표와 대조할 때 매번 환산해야 한다.
public struct Exposure: Equatable, Sendable {
    public let seconds: Double
    public let label: String

    public init(seconds: Double, label: String) {
        self.seconds = seconds
        self.label = label
    }
}

extension Exposure: ExpressibleByArgument {
    public init?(argument: String) {
        let text = argument.trimmingCharacters(in: .whitespaces)

        if text.contains("/") {
            let parts = text.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  numerator > 0, denominator > 0
            else { return nil }
            self.init(seconds: numerator / denominator, label: text)
            return
        }

        guard let value = Double(text), value > 0 else { return nil }
        self.init(seconds: value, label: text)
    }

    public static var defaultCompletionKind: CompletionKind {
        .list(["1/1000", "1/500", "1/250", "1/120", "1/60"])
    }
}
