import CoreGraphics
import ScreenCaptureKit

/// Filter and config are created per window and handed to exactly one capture task, never shared.
private struct CaptureJob: @unchecked Sendable {
    let filter: SCContentFilter
    let config: SCStreamConfiguration
}

/// One-shot window screenshots, sized to the panel's thumbnail box. Nothing is cached.
enum Thumbnails {
    static func capture(ids: [UInt32], size: CGSize, scale: CGFloat,
                        deliver: @escaping @MainActor @Sendable (Int, CGImage) -> Void) -> Task<Void, Never> {
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            await withTaskGroup(of: Void.self) { group in
                for (i, id) in ids.enumerated() {
                    guard let win = byID[id], win.frame.width > 0, win.frame.height > 0 else { continue }
                    let fit = min(size.width / win.frame.width, size.height / win.frame.height)
                    let cfg = SCStreamConfiguration()
                    cfg.width = max(1, Int(win.frame.width * fit * scale))
                    cfg.height = max(1, Int(win.frame.height * fit * scale))
                    cfg.showsCursor = false
                    let job = CaptureJob(filter: SCContentFilter(desktopIndependentWindow: win), config: cfg)
                    group.addTask {
                        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: job.filter,
                                                                                   configuration: job.config),
                              !Task.isCancelled else { return }
                        await deliver(i, img)
                    }
                }
            }
        }
    }
}
