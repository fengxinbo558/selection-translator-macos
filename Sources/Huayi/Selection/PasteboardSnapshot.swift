import AppKit
import Foundation

struct PasteboardSnapshot {
    struct Item {
        let entries: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(entries: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let restoredItems = items.map { snapshot in
            let item = NSPasteboardItem()
            for entry in snapshot.entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
