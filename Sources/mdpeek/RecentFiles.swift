import Foundation

@MainActor
final class RecentFiles {
    private static let defaultsKey = "recentFiles"
    private static let datesKey = "recentFileDates"
    private static let limit = 50

    private(set) var urls: [URL]
    private var dates: [String: Date]
    var onChange: (() -> Void)?

    init() {
        urls = (UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        dates = UserDefaults.standard.dictionary(forKey: Self.datesKey) as? [String: Date] ?? [:]
    }

    /// When the file was last opened in mdpeek (unknown for entries recorded by older versions).
    func lastOpened(_ url: URL) -> Date? {
        dates[url.path]
    }

    func add(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(Self.limit))
        dates[url.path] = Date()
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    private func save() {
        let paths = urls.map(\.path)
        dates = dates.filter { paths.contains($0.key) }
        UserDefaults.standard.set(paths, forKey: Self.defaultsKey)
        UserDefaults.standard.set(dates, forKey: Self.datesKey)
        onChange?()
    }
}
