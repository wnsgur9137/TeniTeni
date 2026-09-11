import ProjectDescription

// 앱과 공용 모듈·도구를 한 워크스페이스로 묶는다.
// TeniVision은 iOS 앱과 macOS CLI가 함께 쓰는 분석 엔진이고,
// TeniTool은 0-C 오프라인 검증 도구다.
let workspace = Workspace(
    name: "TeniTeni",
    projects: [
        ".",
        "Projects/TeniVision",
        "Projects/TeniTool",
    ]
)
