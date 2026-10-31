import Foundation

struct StateStore: Sendable {
    private var stateURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return support
            .appendingPathComponent("MediaDock", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder.mediaDock.decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) throws {
        let folder = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.mediaDock.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var mediaDock: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var mediaDock: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
