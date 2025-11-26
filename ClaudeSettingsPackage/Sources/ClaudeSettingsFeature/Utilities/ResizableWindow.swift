import AppKit
import SwiftUI

// MARK: - Resizable Window Modifier

/// A view modifier that makes a sheet resizable and persists its size between presentations
private struct ResizableWindowModifier: ViewModifier {
    @AppStorage private var width: Double
    @AppStorage private var height: Double

    init(key: String, defaultWidth: CGFloat, defaultHeight: CGFloat) {
        self._width = AppStorage(wrappedValue: defaultWidth, "\(key)Width")
        self._height = AppStorage(wrappedValue: defaultHeight, "\(key)Height")
    }

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .background(WindowAccessor { window in
                window.styleMask.insert(.resizable)
            })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                guard
                    let window = notification.object as? NSWindow,
                    window.isSheet else { return }

                width = window.frame.width
                height = window.frame.height
            }
    }
}

// MARK: - Window Accessor

/// Helper to access the underlying NSWindow of a SwiftUI view
private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                callback(window)
            }
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Makes this view's sheet resizable and persists its size between presentations
    /// - Parameters:
    ///   - key: A unique key for storing the window size in UserDefaults
    ///   - defaultWidth: The default width when no saved size exists
    ///   - defaultHeight: The default height when no saved size exists
    /// - Returns: A view that is resizable with persisted dimensions
    func resizable(
        key: String,
        defaultWidth: CGFloat = 700,
        defaultHeight: CGFloat = 500
    ) -> some View {
        modifier(ResizableWindowModifier(
            key: key,
            defaultWidth: defaultWidth,
            defaultHeight: defaultHeight
        ))
    }
}
