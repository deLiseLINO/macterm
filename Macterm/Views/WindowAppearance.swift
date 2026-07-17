import AppKit
import SwiftUI

extension NSView {
    /// Recursively finds the first descendant view whose class name (as a string)
    /// matches `name`. Used to reach into AppKit's private titlebar view tree —
    /// the only known way to colorize the titlebar to match a transparent
    /// window background. Lifted from Ghostty's NSView+Extension.swift.
    func firstDescendant(withClassName name: String) -> NSView? {
        for subview in subviews {
            if String(describing: type(of: subview)) == name {
                return subview
            }
            if let found = subview.firstDescendant(withClassName: name) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Color helpers

extension NSColor {
    /// Perceptual luminance in 0...1, computed in sRGB. Returns 0 for colors
    /// that can't be converted to an RGB space (e.g. pattern colors).
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    var isLightColor: Bool { luminance > 0.5 }
}

// MARK: - Private CGS blur SPI

/// `CGSSetWindowBackgroundBlurRadius` is a private CoreGraphics API that
/// every macOS terminal (Terminal.app, iTerm, Ghostty) uses to blur the
/// content behind a translucent window. It's undocumented but stable;
/// libghostty exposes the same call.
private let cgsConnectionFnPtr: @convention(c) () -> Int32 = {
    let handle = dlopen(nil, RTLD_NOW)
    guard let sym = dlsym(handle, "CGSDefaultConnectionForThread") else {
        fatalError("CGSDefaultConnectionForThread symbol not found")
    }
    return unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
}()

private let cgsSetBlurFnPtr: @convention(c) (Int32, Int, Int32) -> Int32 = {
    let handle = dlopen(nil, RTLD_NOW)
    guard let sym = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else {
        fatalError("CGSSetWindowBackgroundBlurRadius symbol not found")
    }
    return unsafeBitCast(sym, to: (@convention(c) (Int32, Int, Int32) -> Int32).self)
}()

@MainActor
func setWindowBackgroundBlur(_ window: NSWindow, radius: Int) {
    _ = cgsSetBlurFnPtr(cgsConnectionFnPtr(), window.windowNumber, Int32(radius))
}

// MARK: - Window styling

/// Encapsulates the window-styling work needed to make the titlebar blend
/// with a transparent terminal background. AppKit gives us two surface areas —
/// the content view and a separate, system-owned titlebar view tree — that don't
/// compose visually with a single `backgroundColor` setting. To make them look
/// uniform we reach into the private titlebar hierarchy and override its layer
/// color directly.
@MainActor
enum WindowAppearance {
    /// Apply the current opacity/blur settings to `window`. Safe to call any
    /// time — re-applies idempotently. Should be called after the window is
    /// onscreen, on theme changes, and on focus changes.
    static func sync(window: NSWindow) {
        let opacity = Preferences.shared.windowOpacity
        let blurRadius = Preferences.shared.windowBlurRadius
        let bg = GhosttyApp.shared.backgroundColor
        let isTransparent = opacity < 1.0

        // Native fullscreen draws its own opaque grey background; widgets show
        // through any transparency we apply, so force opaque while fullscreened.
        let forceOpaque = window.styleMask.contains(.fullScreen)
        let effectiveTransparent = isTransparent && !forceOpaque

        if effectiveTransparent {
            window.isOpaque = false
            window.backgroundColor = bg.withAlphaComponent(opacity)
            // Apply blur unconditionally; passing 0 clears any previous blur.
            setWindowBackgroundBlur(window, radius: blurRadius)
        } else {
            window.isOpaque = true
            window.backgroundColor = bg
            // Make sure a previous blur is cleared when going opaque.
            setWindowBackgroundBlur(window, radius: 0)
        }

        // Override the titlebar's private background layer so its color
        // matches the terminal background (or stays transparent when the window is).
        syncTitlebar(window: window, isTransparent: effectiveTransparent)

        syncToolbar(window: window)
    }

    /// Lock the toolbar to icon-only rendering. SwiftUI's NavigationSplitView
    /// toolbar doesn't survive the label display modes: picking "Icon and
    /// Text" from the toolbar's context menu makes AppKit fold the system
    /// sidebar-toggle item into the overflow (») menu at the trailing edge
    /// and grows the titlebar without showing any useful labels. Disabling
    /// display-mode customization removes those context-menu items; forcing
    /// `.iconOnly` repairs a mode picked before the lock existed.
    private static func syncToolbar(window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        if toolbar.displayMode != .iconOnly { toolbar.displayMode = .iconOnly }
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }
    }

    /// Update any glass-specific state when the window gains/loses key status.
    /// No-op in this build because liquid glass is disabled for SDK compatibility.
    static func syncKeyStatus(window: NSWindow) {
        _ = window
    }

    /// Liquid glass (`NSGlassEffectView`) is disabled for this build because
    /// the CI SDK does not expose the required AppKit symbols.
    static var glassSupported: Bool { false }

    private static func syncTitlebar(window: NSWindow, isTransparent: Bool) {
        guard let container = titlebarContainer(in: window) else { return }

        if let titlebarView = container.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true
            // Keep the titlebar transparent so the NavigationSplitView's
            // sidebar material shows through consistently with the content area.
            titlebarView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // NSTitlebarBackgroundView has subviews that force their own background
        // colors; hide it only when transparent, so the default opaque-mode
        // chrome stays intact.
        container.firstDescendant(withClassName: "NSTitlebarBackgroundView")?.isHidden = isTransparent
    }

    private static func titlebarContainer(in window: NSWindow) -> NSView? {
        // The titlebar container lives on the window's content view's root in
        // normal mode, and on a separate NSToolbarFullScreenWindow in native
        // fullscreen. We don't support native fullscreen tab bars, so the
        // first path suffices for Macterm.
        guard let contentView = window.contentView else { return nil }
        var root: NSView = contentView
        while let s = root.superview {
            root = s
        }
        if String(describing: type(of: root)) == "NSTitlebarContainerView" { return root }
        return root.firstDescendant(withClassName: "NSTitlebarContainerView")
    }
}
