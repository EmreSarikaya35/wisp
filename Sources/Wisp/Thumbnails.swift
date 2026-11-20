import CoreGraphics
import ScreenCaptureKit

/// Each filter and configuration is handed to just one screenshot task.
private struct CaptureJob: @unchecked Sendable {
    let filter: SCContentFilter
    let config: SCStreamConfiguration
}

@MainActor enum Thumbnails {
    private static var previousCapture: Task<Void, Never>?

    static func capture(targets: [(index: Int, id: UInt32)], size: CGSize, scale: CGFloat,
                        deliver: @escaping @MainActor @Sendable (Int, CGImage) -> Void) -> Task<Void, Never>? {
        guard !targets.isEmpty else { return nil }
        let previous = previousCapture
        let task = Task {
            // A screenshot request already inside ScreenCaptureKit may outlive cancellation.
            await previous?.value
            guard !Task.isCancelled,
                  let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
                  !Task.isCancelled else { return }
            let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for (index, id) in targets {
                    guard !Task.isCancelled else { break }
                    guard let window = windows[id], window.frame.width > 0, window.frame.height > 0 else { continue }
                    if inFlight == 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    let fit = min(size.width / window.frame.width, size.height / window.frame.height)
                    let config = SCStreamConfiguration()
                    config.width = max(1, Int(window.frame.width * fit * scale))
                    config.height = max(1, Int(window.frame.height * fit * scale))
                    config.showsCursor = false
                    let job = CaptureJob(filter: SCContentFilter(desktopIndependentWindow: window), config: config)
                    if group.addTaskUnlessCancelled(operation: {
                        guard !Task.isCancelled,
                              let image = try? await SCScreenshotManager.captureImage(contentFilter: job.filter,
                                                                                     configuration: job.config),
                              !Task.isCancelled else { return }
                        await MainActor.run {
                            if !Task.isCancelled { deliver(index, image) }
                        }
                    }) {
                        inFlight += 1
                    }
                }
            }
        }
        previousCapture = task
        return task
    }
}
