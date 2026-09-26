// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Routes `applications.*`, `users.*`, and `agents.*` method channel calls to the native
/// management API. Resources cross the channel as JSON maps, encoded and decoded with the
/// native models' own `Codable` conformance.
@MainActor
enum ManagementMethodHandler {
    static func handles(_ method: String) -> Bool {
        ["applications", "users", "agents"].contains(method.split(separator: ".").first.map(String.init) ?? "")
    }

    static func handle(method: String, args: [String: Any], client: ThunderIDClient) async throws -> Any? {
        let id = args["id"] as? String ?? ""
        let limit = args["limit"] as? Int
        let offset = args["offset"] as? Int
        switch method {
        case "applications.list":
            return try encode(try await client.applications.list(limit: limit, offset: offset))
        case "applications.get":
            return try encode(try await client.applications.get(id: id))
        case "applications.create":
            return try encode(try await client.applications.create(decode(args["payload"])))
        case "applications.update":
            return try encode(try await client.applications.update(id: id, decode(args["payload"])))
        case "applications.delete":
            try await client.applications.delete(id: id)
            return nil
        default:
            return try await handleUsersAndAgents(method: method, args: args, client: client)
        }
    }

    private static func handleUsersAndAgents(
        method: String,
        args: [String: Any],
        client: ThunderIDClient
    ) async throws -> Any? {
        let id = args["id"] as? String ?? ""
        let limit = args["limit"] as? Int
        let offset = args["offset"] as? Int
        switch method {
        case "users.list":
            let filter = args["filter"] as? String
            return try encode(try await client.users.list(limit: limit, offset: offset, filter: filter))
        case "users.get":
            return try encode(try await client.users.get(id: id))
        case "users.create":
            return try encode(try await client.users.create(decode(args["payload"])))
        case "users.update":
            return try encode(try await client.users.update(id: id, decode(args["payload"])))
        case "users.delete":
            try await client.users.delete(id: id)
            return nil
        case "agents.list":
            return try encode(try await client.agents.list(limit: limit, offset: offset))
        case "agents.get":
            return try encode(try await client.agents.get(id: id))
        case "agents.create":
            return try encode(try await client.agents.create(decode(args["payload"])))
        case "agents.update":
            return try encode(try await client.agents.update(id: id, decode(args["payload"])))
        case "agents.delete":
            try await client.agents.delete(id: id)
            return nil
        default:
            throw ThunderIDError(code: .unknownError, message: "Unknown method: \(method)")
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private static func decode<T: Decodable>(_ value: Any?) throws -> T {
        guard let value, JSONSerialization.isValidJSONObject(value) else {
            throw ThunderIDError(code: .invalidInput, message: "A payload is required")
        }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
