import Domain
import Foundation
import OSLog
import SwiftData

/// SwiftData 저장 모델. **`Domain` 엔티티와 따로 둔다.**
///
/// `@Model`은 클래스에 붙는 매크로라 `Domain`에 직접 붙이면 9.6의
/// "`Domain`은 아무것도 import하지 않는다"를 어긴다. 매핑 코드가 생기지만
/// D-08이 "교체 비용은 Data 계층에 한정된다"고 약속했으므로 그 약속을
/// 지키는 쪽이다.
/// 근거: docs/07-기획/SPEC-0070-persistence-foundation.md 구현 선택지 1
@Model
final class SessionModel {
    #Index<SessionModel>([\.startedAt])
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var situationRaw: String
    var observableRaw: String
    var fps: Int

    /// 세션을 지우면 클립도 지운다. 세션 없는 클립은 의미가 없다.
    @Relationship(deleteRule: .cascade, inverse: \ClipModel.session)
    var clips: [ClipModel]

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        situationRaw: String,
        observableRaw: String,
        fps: Int,
        clips: [ClipModel] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.situationRaw = situationRaw
        self.observableRaw = observableRaw
        self.fps = fps
        self.clips = clips
    }
}

@Model
final class ClipModel {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var recordedAt: Date
    var fps: Int
    var session: SessionModel?

    @Relationship(deleteRule: .cascade, inverse: \SwingModel.clip)
    var swings: [SwingModel]

    init(
        id: UUID,
        fileName: String,
        recordedAt: Date,
        fps: Int,
        swings: [SwingModel] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.fps = fps
        self.swings = swings
    }
}

@Model
final class SwingModel {
    @Attribute(.unique) var id: UUID
    var startSeconds: TimeInterval
    var endSeconds: TimeInterval
    var impactSeconds: TimeInterval
    /// `nil`이면 아직 분류되지 않았다. 분류는 1-D다.
    var kindRaw: String?
    var clip: ClipModel?

    init(
        id: UUID,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        impactSeconds: TimeInterval,
        kindRaw: String?
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.impactSeconds = impactSeconds
        self.kindRaw = kindRaw
    }
}

// MARK: - 매핑

extension SwingModel {
    convenience init(_ swing: Swing) {
        self.init(
            id: swing.id,
            startSeconds: swing.startSeconds,
            endSeconds: swing.endSeconds,
            impactSeconds: swing.impactSeconds,
            kindRaw: swing.kind?.rawValue
        )
    }

    var domain: Swing {
        Swing(
            id: id,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            impactSeconds: impactSeconds,
            kind: kindRaw.flatMap(SwingKind.init(rawValue:))
        )
    }
}

extension ClipModel {
    convenience init(_ clip: Clip) {
        self.init(
            id: clip.id,
            fileName: clip.fileName,
            recordedAt: clip.recordedAt,
            fps: clip.fps,
            swings: clip.swings.map(SwingModel.init)
        )
    }

    var domain: Clip {
        Clip(
            id: id,
            fileName: fileName,
            recordedAt: recordedAt,
            fps: fps,
            swings: swings
                .sorted { $0.startSeconds < $1.startSeconds }
                .map(\.domain)
        )
    }
}

extension SessionModel {
    convenience init(_ session: Session) {
        self.init(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            situationRaw: session.situation.rawValue,
            observableRaw: session.observable.rawValue,
            fps: session.fps,
            clips: session.clips.map(ClipModel.init)
        )
    }

    /// 저장된 문자열이 현재 enum에 없으면 기본값으로 떨어진다. 앱이
    /// 크래시하는 것보다 낫고, 그런 값이 생기는 것은 스키마가 바뀐
    /// 뒤이므로 마이그레이션이 다룰 일이다.
    ///
    /// ⚠️ 다만 **조용히** 떨어지면 안 된다. 폴백이 두 필드에서 따로
    /// 일어나면 도메인이 불가능하다고 선언한 조합이 만들어진다 —
    /// `situationRaw`만 알 수 없는 값이 되면 `.rally`로 떨어지는데
    /// `observableRaw`는 `.lineCall` 그대로 살아남아, `allowsLineCall`이
    /// 거짓인 상황에 라인 판정이 붙는다. 1-D의 룰 엔진과 보관함 UI는 그
    /// 조합을 전제하지 않는다. 로그를 남기고, 쌍을 도메인 규칙에 맞춘다.
    var domain: Session {
        let situation = CaptureSituation(rawValue: situationRaw) ?? {
            Self.logger.error(
                "알 수 없는 situationRaw \"\(self.situationRaw, privacy: .public)\" — .rally로 떨어뜨린다. 마이그레이션 누락"
            )
            return .rally
        }()

        var observable = ObservationTarget(rawValue: observableRaw) ?? {
            Self.logger.error(
                "알 수 없는 observableRaw \"\(self.observableRaw, privacy: .public)\" — .swing으로 떨어뜨린다. 마이그레이션 누락"
            )
            return .swing
        }()

        // 라인 판정이 불가능한 상황에 라인 판정이 붙어 있으면 상황을 믿는다.
        if !situation.allowsLineCall, observable == .lineCall {
            Self.logger.error(
                "\(self.situationRaw, privacy: .public)은 라인 판정을 허용하지 않는데 observableRaw가 lineCall이다 — .swing으로 맞춘다"
            )
            observable = .swing
        }

        return Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            situation: situation,
            observable: observable,
            fps: fps,
            clips: clips
                .sorted { $0.recordedAt < $1.recordedAt }
                .map(\.domain)
        )
    }

    static let logger = Logger(
        subsystem: "com.wnsgur9137.TeniTeni.Data", category: "persistence"
    )
}
