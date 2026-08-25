import AppKit
import Carbon.HIToolbox
import Foundation

enum GlobalShortcutError: LocalizedError, Equatable {
    case invalid
    case conflict
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalid:
            "快捷键至少需要一个修饰键。"
        case .conflict:
            "这个快捷键已被其他应用使用，请换一个组合。"
        case .unavailable:
            "无法注册这个快捷键，请换一个组合。"
        }
    }
}

enum ShortcutCommand: UInt32, CaseIterable, Sendable {
    case translateSelection = 1
    case captureAndTranslate = 2
}

@MainActor
final class GlobalShortcutManager {
    var onTrigger: ((ShortcutCommand) -> Void)?

    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private(set) var currentShortcuts: [ShortcutCommand: ShortcutDefinition] = [:]

    deinit {
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(
        _ shortcut: ShortcutDefinition,
        for command: ShortcutCommand
    ) throws {
        guard shortcut.isValid else { throw GlobalShortcutError.invalid }
        try installEventHandlerIfNeeded()
        guard shortcut != currentShortcuts[command] else { return }

        if currentShortcuts.contains(where: { key, value in
            key != command && value == shortcut
        }) {
            throw GlobalShortcutError.conflict
        }

        var newHotKey: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: command.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(for: shortcut.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )

        guard status == noErr, let newHotKey else {
            if status == eventHotKeyExistsErr {
                throw GlobalShortcutError.conflict
            }
            throw GlobalShortcutError.unavailable(status)
        }

        if let hotKey = hotKeys[command.rawValue] {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys[command.rawValue] = newHotKey
        currentShortcuts[command] = shortcut
    }

    func unregister(_ command: ShortcutCommand? = nil) {
        if let command {
            if let hotKey = hotKeys.removeValue(forKey: command.rawValue) {
                UnregisterEventHotKey(hotKey)
            }
            currentShortcuts.removeValue(forKey: command)
            return
        }
        for hotKey in hotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        currentShortcuts.removeAll()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalShortcutManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      let command = ShortcutCommand(rawValue: identifier.id)
                else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in
                    manager.onTrigger?(command)
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
        guard status == noErr, eventHandler != nil else {
            throw GlobalShortcutError.unavailable(status)
        }
    }

    private func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static let signature: OSType = 0x4859_5954 // HYYT
}
