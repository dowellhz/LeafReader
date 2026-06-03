import Cocoa
import UniformTypeIdentifiers

enum ExportPanelSupport {
    struct FormatOption {
        let title: String
        let fileExtension: String
    }

    static func contentTypes(for formats: [FormatOption]) -> [UTType] {
        formats.compactMap { UTType(filenameExtension: $0.fileExtension) }
    }

    static func popup(for titles: [String], selectedIndex: Int = 0) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        if titles.indices.contains(selectedIndex) {
            popup.selectItem(at: selectedIndex)
        }
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }

    static func selectedIndex(from popup: NSPopUpButton, count: Int, defaultIndex: Int = 0) -> Int {
        let index = popup.indexOfSelectedItem
        return (0..<count).contains(index) ? index : defaultIndex
    }

    static func outputURL(_ url: URL, matching format: FormatOption) -> URL {
        url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    static func accessoryView(rows: [(title: String, control: NSView)]) -> NSView {
        let rowHeight: CGFloat = 32
        let rowSpacing: CGFloat = 8
        let height = CGFloat(rows.count) * rowHeight + CGFloat(max(0, rows.count - 1)) * rowSpacing
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
        var previousRow: NSView?

        for rowSpec in rows {
            let row = accessoryRow(title: rowSpec.title, control: rowSpec.control)
            container.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: rowHeight)
            ])
            if let previousRow {
                row.topAnchor.constraint(equalTo: previousRow.bottomAnchor, constant: rowSpacing).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
            }
            previousRow = row
        }
        return container
    }

    private static func accessoryRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 92),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        return row
    }
}
