import AppKit
import DzhmilCore

final class DronePanel: NSPanel {
    static let size = CGSize(width: 340, height: 320)
    static let droneBottomMargin: CGFloat = 30
    static var droneSize: CGSize { CGSize(width: DroneView.width, height: DroneView.height) }
    static var droneRect: CGRect {
        CGRect(x: (size.width - droneSize.width) / 2, y: droneBottomMargin, width: droneSize.width, height: droneSize.height)
    }
    static var droneCenterOffset: CGPoint { CGPoint(x: droneRect.midX, y: droneRect.midY) }

    var allowsKey = false

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    func origin(forDroneCenter center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - Self.droneCenterOffset.x, y: center.y - Self.droneCenterOffset.y)
    }

    var droneCenter: CGPoint {
        CGPoint(x: frame.minX + Self.droneCenterOffset.x, y: frame.minY + Self.droneCenterOffset.y)
    }
}

final class ClickThroughHostingView<Content: SwiftUI.View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
}

import SwiftUI
