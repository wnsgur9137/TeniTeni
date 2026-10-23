import CoreGraphics
import Foundation
import Testing
@testable import TeniVision

/// 가짜 관측. `HumanBodyPoseObservation`을 합성할 수 없어서 경계 프로토콜을
/// 둔 것이고, 그 경계가 실제로 이 정도로 좁은지가 여기서 드러난다.
private struct FakePose: BodyPoseObservable {
    var samples: [PoseJoint: PoseJointSample] = [:]

    func sample(for joint: PoseJoint) -> PoseJointSample? { samples[joint] }

    /// 어깨 둘만 놓인 관측. 사람 선택 테스트용.
    static func shoulders(width: CGFloat, confidence: Double = 0.9) -> FakePose {
        FakePose(samples: [
            .leftShoulder: PoseJointSample(point: CGPoint(x: 0.5 - width / 2, y: 0.6), confidence: confidence),
            .rightShoulder: PoseJointSample(point: CGPoint(x: 0.5 + width / 2, y: 0.6), confidence: confidence),
        ])
    }
}

@Suite("포즈 어댑터")
struct PoseAdapterTests {

    @Test("관측에 있는 관절 여섯 개가 전부 넘어온다")
    func 전체_매핑() {
        var pose = FakePose()
        for (index, joint) in PoseJoint.allCases.enumerated() {
            pose.samples[joint] = PoseJointSample(
                point: CGPoint(x: Double(index) / 10, y: 0.5),
                confidence: 0.8
            )
        }
        let frame = PoseFrameAdapter.frame(from: pose, at: 1.25)
        #expect(frame.joints.count == PoseJoint.allCases.count)
        #expect(frame.timestamp == 1.25)
    }

    @Test("좌표와 신뢰도를 그대로 옮긴다 — 뒤집지 않는다")
    func 좌표_보존() {
        let pose = FakePose(samples: [
            .rightWrist: PoseJointSample(point: CGPoint(x: 0.25, y: 0.75), confidence: 0.42)
        ])
        let frame = PoseFrameAdapter.frame(from: pose, at: 0)
        let sample = frame.joints[.rightWrist]
        #expect(sample?.point == CGPoint(x: 0.25, y: 0.75))
        #expect(sample?.confidence == 0.42)
    }

    @Test("관측에 없는 관절은 프레임에도 없다")
    func 결손_관절() {
        let pose = FakePose(samples: [
            .leftWrist: PoseJointSample(point: .zero, confidence: 0.9)
        ])
        let frame = PoseFrameAdapter.frame(from: pose, at: 0)
        #expect(frame.joints.count == 1)
        #expect(frame.joints[.rightWrist] == nil)
    }

    /// 어댑터가 걸러내면 같은 판단이 두 곳에 생긴다. 임계는 프로파일의 일이다.
    @Test("신뢰도가 낮아도 어댑터는 버리지 않는다")
    func 신뢰도_통과() {
        let pose = FakePose(samples: [
            .leftHip: PoseJointSample(point: CGPoint(x: 0.5, y: 0.4), confidence: 0.01)
        ])
        let frame = PoseFrameAdapter.frame(from: pose, at: 0)
        #expect(frame.joints[.leftHip]?.confidence == 0.01)
        // 거르는 쪽은 여기다.
        #expect(frame.point(.leftHip, minimumConfidence: 0.3) == nil)
        #expect(frame.point(.leftHip, minimumConfidence: 0.005) != nil)
    }

    @Test("빈 관측은 관절 없는 프레임이 된다")
    func 빈_관측() {
        let frame = PoseFrameAdapter.frame(from: FakePose(), at: 2)
        #expect(frame.joints.isEmpty)
        #expect(frame.timestamp == 2)
    }
}

@Suite("사람 선택")
struct PrimaryObservationTests {

    @Test("어깨 폭이 가장 큰 사람을 고른다")
    func 가장_가까운_사람() {
        let near = FakePose.shoulders(width: 0.30)
        let far = FakePose.shoulders(width: 0.08)
        let chosen = PoseEstimator.primary(in: [far, near, far], minimumConfidence: 0.3)
        #expect(chosen?.shoulderWidth(minimumConfidence: 0.3) == near.shoulderWidth(minimumConfidence: 0.3))
    }

    @Test("어깨 신뢰도가 임계에 못 미치는 사람은 후보가 아니다")
    func 신뢰도_미달_제외() throws {
        let big = FakePose.shoulders(width: 0.40, confidence: 0.1)
        let small = FakePose.shoulders(width: 0.10, confidence: 0.9)
        let chosen = PoseEstimator.primary(in: [big, small], minimumConfidence: 0.3)
        let width = try #require(chosen?.shoulderWidth(minimumConfidence: 0.3))
        #expect(width == small.shoulderWidth(minimumConfidence: 0.3))
    }

    @Test("어깨가 아무도 안 보이면 고르지 않는다")
    func 전원_어깨_없음() {
        let wristOnly = FakePose(samples: [
            .rightWrist: PoseJointSample(point: .zero, confidence: 0.9)
        ])
        #expect(PoseEstimator.primary(in: [wristOnly, wristOnly], minimumConfidence: 0.3) == nil)
    }

    @Test("관측이 없으면 고르지 않는다")
    func 빈_배열() {
        #expect(PoseEstimator.primary(in: [FakePose](), minimumConfidence: 0.3) == nil)
    }

    @Test("한쪽 어깨만 보이면 폭을 내지 않는다")
    func 한쪽_어깨() {
        let half = FakePose(samples: [
            .leftShoulder: PoseJointSample(point: CGPoint(x: 0.4, y: 0.6), confidence: 0.9)
        ])
        #expect(half.shoulderWidth(minimumConfidence: 0.3) == nil)
    }

    @Test("어깨 폭은 두 어깨 사이 거리다")
    func 폭_계산() throws {
        let pose = FakePose(samples: [
            .leftShoulder: PoseJointSample(point: CGPoint(x: 0.3, y: 0.5), confidence: 0.9),
            .rightShoulder: PoseJointSample(point: CGPoint(x: 0.3, y: 0.8), confidence: 0.9),
        ])
        let width = try #require(pose.shoulderWidth(minimumConfidence: 0.3))
        #expect(abs(width - 0.3) < 1e-9)
    }
}
