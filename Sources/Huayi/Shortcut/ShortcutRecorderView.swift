import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    let shortcut: ShortcutDefinition
    let onCommit: (ShortcutDefinition) -> Result<Void, GlobalShortcutError>

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isRecording.toggle()
                if isRecording { installMonitor() } else { removeMonitor() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                    Text(isRecording ? "请按新的快捷键" : shortcut.displayString)
                        .monospacedDigit()
                    Spacer(minLength: 12)
                    Text(isRecording ? "Esc 取消" : "点击修改")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全局快捷键，当前为 \(shortcut.displayString)")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { removeMonitor() }
    }

    private func installMonitor() {
        errorMessage = nil
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                removeMonitor()
                return nil
            }
            if event.keyCode == UInt16(kVK_Delete), event.modifierFlags
                .intersection([.command, .control, .option, .shift]).isEmpty {
                commit(.defaultShortcut)
                return nil
            }

            let candidate = ShortcutDefinition(
                keyCode: UInt32(event.keyCode),
                modifiers: event.modifierFlags
            )
            guard candidate.isValid else {
                errorMessage = GlobalShortcutError.invalid.localizedDescription
                return nil
            }
            commit(candidate)
            return nil
        }
    }

    private func commit(_ candidate: ShortcutDefinition) {
        switch onCommit(candidate) {
        case .success:
            errorMessage = nil
            isRecording = false
            removeMonitor()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
