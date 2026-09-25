import SwiftUI
import ClaudeMonitorCore

#if DEBUG
/// Renders the popover to PNGs for visual review: `ClaudeMonitor --snapshot <dir>`.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = args[i + 1]

        let states: [(String, UsageStore, CodexStore)] = [
            ("low", store(34, week: 51), codexStore(20)),
            ("mid", store(72, week: 88), codexStore(55)),
            ("high", store(94, week: 96), codexStore(91)),
            ("waiting", UsageStore(), CodexStore()),
        ]
        for (name, st, cx) in states {
            let view = MenuBarView(store: st, codexStore: cx)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/popover-\(name).png"))
                FileHandle.standardError.write(Data("wrote popover-\(name).png\n".utf8))
            }
        }
        return true
    }

    private static func store(_ percent: Int, week: Int?) -> UsageStore {
        let s = UsageStore()
        s.injectSample(Usage(
            sessionPercent: percent,
            sessionResetAt: Date().addingTimeInterval(2 * 3600),
            weekPercent: week,
            weekResetAt: Date().addingTimeInterval(3 * 24 * 3600)
        ))
        return s
    }

    private static func codexStore(_ percent: Int) -> CodexStore {
        let s = CodexStore()
        s.injectSample(CodexUsage(
            windows: [CodexWindow(
                usedPercent: percent,
                resetsAt: Date().addingTimeInterval(12 * 24 * 3600),
                windowMinutes: 43800
            )],
            planType: "team",
            observedAt: Date()
        ))
        return s
    }
}
#endif
