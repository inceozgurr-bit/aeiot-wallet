import Foundation

struct Contact: Codable, Identifiable, Hashable {
    var name: String
    var address: String
    var id: String { address }
}

@Observable @MainActor
final class AddressBook {
    private(set) var contacts: [Contact] = []
    private static let key = "addressBook"

    init() {
        if let json = Keychain.load(key: Self.key),
           let decoded = try? JSONDecoder().decode([Contact].self, from: Data(json.utf8)) {
            contacts = decoded
        }
    }

    func add(name: String, address: String) {
        contacts.removeAll { $0.address.lowercased() == address.lowercased() }
        contacts.append(Contact(name: name, address: address))
        persist()
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(contacts),
           let json = String(data: data, encoding: .utf8) {
            Keychain.save(json, key: Self.key)
        }
    }
}
