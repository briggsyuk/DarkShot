import AppKit
import ScreenCaptureKit

struct CapturedDisplay {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
final class CaptureService {
    func capture() async throws -> [CapturedDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        // Start all display requests together; never keep a recording stream running in the background.
        return try await withThrowingTaskGroup(of: CapturedDisplay?.self) { group in
            for display in content.displays {
                guard let screen = screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
                }) else { continue }
                let scale = screen.backingScaleFactor
                let width = Int(screen.frame.width * scale)
                let height = Int(screen.frame.height * scale)
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.width = width
                    configuration.height = height
                    configuration.showsCursor = false
                    configuration.captureResolution = .best
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: configuration)
                    return CapturedDisplay(screen: screen, image: image)
                }
            }
            var captures: [CapturedDisplay] = []
            for try await capture in group {
                if let capture { captures.append(capture) }
            }
            return captures
        }
    }
}
