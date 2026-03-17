/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * BreakpointStore.swift
 * Persists breakpoints for .ttl macro files.
 * Stores breakpoint line numbers in a JSON file alongside the macro
 * (e.g. myscript.ttl → myscript.ttl.breakpoints.json).
 */

import Foundation

// MARK: - BreakpointStore

final class BreakpointStore {

    /// File extension appended to the .ttl path for the breakpoint config.
    private static let suffix = ".breakpoints.json"

    // MARK: - Persistence Path

    /// Returns the breakpoint config file path for a given .ttl script path.
    static func configPath(for scriptPath: String) -> String {
        return scriptPath + suffix
    }

    // MARK: - Save

    /// Save breakpoints (0-based line indices) for the given script path.
    /// Converts to 1-based line numbers for the JSON file.
    static func save(breakpoints: Set<Int>, for scriptPath: String) {
        let path = configPath(for: scriptPath)

        // If no breakpoints, remove the config file
        if breakpoints.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
            return
        }

        // Convert 0-based to 1-based and sort
        let lineNumbers = breakpoints.map { $0 + 1 }.sorted()
        let data: [String: Any] = [
            "version": 1,
            "scriptPath": (scriptPath as NSString).lastPathComponent,
            "breakpoints": lineNumbers
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Load

    /// Load breakpoints for the given script path.
    /// Returns 0-based line indices (converted from 1-based in the file).
    static func load(for scriptPath: String) -> Set<Int> {
        let path = configPath(for: scriptPath)

        guard FileManager.default.fileExists(atPath: path),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let lineNumbers = dict["breakpoints"] as? [Int] else {
            return []
        }

        // Convert 1-based to 0-based
        return Set(lineNumbers.map { max(0, $0 - 1) })
    }

    // MARK: - Delete

    /// Remove the breakpoint config file for the given script path.
    static func delete(for scriptPath: String) {
        let path = configPath(for: scriptPath)
        try? FileManager.default.removeItem(atPath: path)
    }
}
