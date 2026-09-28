import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: String

    init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var items: [Bookmark] = []
    private let key = "CleanBrowserPro.Bookmarks"

    private init() {
        load()
    }

    func add(title: String, url: String) {
        guard !url.isEmpty else { return }
        if items.contains(where: { $0.url == url }) { return }
        items.append(Bookmark(title: title.isEmpty ? url : title, url: url))
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard items.indices.contains(index) else { continue }
            items.remove(at: index)
        }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }
}
