import ProjectDescription

// 앱과 TeniVision 프레임워크를 한 워크스페이스로 묶는다.
// TeniVision은 macOS CLI(0-C 도구)도 참조하게 될 공용 엔진이다.
let workspace = Workspace(
    name: "TeniTeni",
    projects: [
        ".",
        "Projects/TeniVision",
    ]
)
