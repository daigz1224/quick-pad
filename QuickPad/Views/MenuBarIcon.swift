import AppKit

/// Hand-drawn menu-bar template image. Three stacked "stream entries":
/// a small bullet dot on the left followed by a horizontal line whose
/// length varies per row, mimicking a Bullet Journal rapid log at a
/// glance. Rendered as a template image so the menu bar auto-adapts it
/// to light/dark mode without any extra code.
enum MenuBarIcon {

    static func make() -> NSImage {
        // 18×16 is the "comfortable menu bar" size — matches the visual
        // weight of Apple's own template icons (clock, battery, etc.).
        let size = NSSize(width: 18, height: 16)

        let image = NSImage(size: size, flipped: false) { _ in
            let color = NSColor.black
            color.setStroke()
            color.setFill()

            // (baseline y, line length). y is measured from the bottom
            // of the canvas because `flipped: false`.
            let rows: [(y: CGFloat, width: CGFloat)] = [
                (12.5, 13),   // top — longest
                (8.5,  9),    // middle — shortest
                (4.5, 11),    // bottom
            ]

            for row in rows {
                // Bullet dot on the left.
                let dot = NSBezierPath(
                    ovalIn: NSRect(x: 1, y: row.y - 1, width: 2.2, height: 2.2)
                )
                dot.fill()

                // Horizontal "text" line to the right of the bullet.
                let stroke = NSBezierPath()
                stroke.move(to: NSPoint(x: 5, y: row.y))
                stroke.line(to: NSPoint(x: 5 + row.width, y: row.y))
                stroke.lineWidth = 1.3
                stroke.lineCapStyle = .round
                stroke.stroke()
            }

            return true
        }

        return image
    }
}
