import AppKit
import SwiftUI

private let supportDirectory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("DynamicIsland", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

private func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
    guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent(file)) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

private func save<T: Encodable>(_ value: T, to file: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? data.write(to: supportDirectory.appendingPathComponent(file), options: .atomic)
}

// MARK: - Полка временных файлов

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var addedAt = Date()

    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Полка хранит ссылки на файлы: перетащил сюда, а позже вытащил туда, куда нужно.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    init() {
        items = (load([ShelfItem].self, from: "shelf.json") ?? []).filter(\.exists)
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let fresh = urls.filter { !known.contains($0) }.map { ShelfItem(url: $0) }
        guard !fresh.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            items.insert(contentsOf: fresh, at: 0)
        }
        persist()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            items.removeAll { $0.id == item.id }
        }
        persist()
    }

    func removeAll() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items.removeAll() }
        persist()
    }

    private func persist() { save(items, to: "shelf.json") }
}

// MARK: - Заметки

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var updatedAt = Date()

    var title: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? "Новая заметка" : first
    }
}

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private var saveWork: DispatchWorkItem?

    init() {
        notes = load([Note].self, from: "notes.json") ?? []
        if notes.isEmpty { notes = [Note(text: "")] }
        selectedID = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.notes.first { $0.id == id }?.text ?? "" },
            set: { [weak self] text in self?.update(id, text: text) })
    }

    func create() {
        let note = Note(text: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            notes.insert(note, at: 0)
            selectedID = note.id
        }
        persist()
    }

    func delete(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            notes.removeAll { $0.id == id }
            if notes.isEmpty { notes = [Note(text: "")] }
            if selectedID == id { selectedID = notes.first?.id }
        }
        persist()
    }

    private func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        // Пишем на диск с небольшой задержкой, чтобы не делать это на каждую букву.
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func persist() { save(notes, to: "notes.json") }
}
