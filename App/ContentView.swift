import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CrashTrim").font(.title2.weight(.semibold))
                    Text("식별 정보를 가리고, 분석에 필요한 로그를 남깁니다.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Mac 안에서만 처리", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            HSplitView {
                editorPane(title: "원문", subtitle: "macOS 앱 충돌 리포트 · 텍스트 / IPS JSON") {
                    LogTextView(text: $model.input, accessibilityLabel: "원문 로그")
                        .overlay(alignment: .topLeading) {
                            if model.input.isEmpty {
                                Text("문제 리포트 로그를 여기에 붙여넣으세요.")
                                    .foregroundStyle(.tertiary).padding(14).allowsHitTesting(false)
                            }
                        }
                }
                editorPane(title: "처리 결과", subtitle: "원래 형식 유지 · 모든 스레드와 진단 정보 보존") {
                    LogTextView(text: .constant(model.result?.output ?? ""), editable: false, accessibilityLabel: "마스킹된 결과")
                        .overlay {
                            if model.isProcessing {
                                ProgressView("마스킹 및 정리 중…")
                                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            } else if model.result == nil {
                                VStack(spacing: 10) {
                                    Image(systemName: "doc.text").font(.largeTitle)
                                    Text("‘마스킹 및 정리’를 누르면 결과가 표시됩니다.")
                                }
                                .foregroundStyle(.tertiary).allowsHitTesting(false)
                            }
                        }
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("추가로 가릴 문자열").font(.callout.weight(.semibold))
                    Text("이름·사내 식별자 등 자동 탐지가 어려운 값을 줄마다 입력하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                    LogTextView(text: $model.additionalStrings, accessibilityLabel: "추가 마스킹 문자열")
                        .frame(height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text("마스킹 범위").font(.callout.weight(.semibold))
                    Text("개인 경로 · 계정 · 네트워크 주소 · 시리얼 · 파트 넘버\nMac 모델 · 앱 식별자 · 빌드 UUID")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("식별자 마스킹으로 심볼 복원이 제한될 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("외부 전송과 자동 저장 없이 처리합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            HStack(spacing: 10) {
                Button { model.paste() } label: { Label("붙여넣기", systemImage: "doc.on.clipboard") }
                Button("모두 지우기") { model.clear() }
                    .disabled(model.input.isEmpty && model.additionalStrings.isEmpty)
                Spacer()
                Button { model.process() } label: { Label("마스킹 및 정리", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent).disabled(!model.canProcess)
                Button { model.copyResult() } label: {
                    Label(model.copied ? "복사됨" : "결과 복사", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.result == nil)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            HStack {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else if let result = model.result {
                    Image(systemName: result.recognized ? "checkmark.circle" : "info.circle")
                    Text(result.format)
                    Text("· 마스킹 \(result.maskedOccurrences)건 · 제외 \(result.removedItems)항목 / \(result.removedCharacters)자")
                } else {
                    Text(model.isProcessing ? "로그를 처리하고 있습니다." : "원문을 붙여넣고 마스킹 및 정리를 실행하세요.")
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(.quaternary.opacity(0.35))
        }
    }

    private func editorPane<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            content()
        }
        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
    }
}
