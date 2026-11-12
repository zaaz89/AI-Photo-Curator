import AppKit
import CuratorCore
import Quartz

/// The system Quick Look panel on the original files (read-only). Space opens and closes it;
/// the panel's own arrows move through the photos currently shown in the grid.
@MainActor final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var urls: [URL] = []

    func toggle(_ photos: [Photo], at index: Int) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        guard !photos.isEmpty else { return }
        urls = photos.map(\.fileURL)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Keeps the panel on the photo under the grid's cursor.
    func follow(_ index: Int) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible, index >= 0, index < urls.count else { return }
        panel.currentPreviewItemIndex = index
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
