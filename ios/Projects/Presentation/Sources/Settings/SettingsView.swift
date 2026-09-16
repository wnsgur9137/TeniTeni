import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct SettingsView: View {
    @Bindable private var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("주 사용 손", selection: $store.handedness.sending(\.handednessChanged)) {
                        ForEach(Handedness.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("프로필")
                } footer: {
                    Text("주 사용 손은 **분석의 전제**입니다. 라켓 팔 강조·포핸드 분류·배치 안내가 이 값에 달려 있습니다.")
                }

                Section("소리") {
                    Toggle("스윙 감지음", isOn: $store.soundEnabled.sending(\.soundToggled))
                }

                Section {
                    LabeledContent("코트 프리셋", value: "1-F에서")
                        .foregroundStyle(Token.Text.tertiary)
                } header: {
                    Text("라인 판정")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { store.send(.closeTapped) }
                }
            }
        }
    }
}
