import SwiftUI

@main
struct CrashTrimApp: App {
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("로그 처리") {
                Button("마스킹 및 정리") { model.process() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canProcess)
                Button("결과 복사") { model.copyResult() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.result == nil)
            }
        }
    }
}
