//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "a55be9dfd9f22857b297006482824798086c758b"
    static let buildDate: String = "2025-06-18 19:23"
    static let gitBranch: String = "v0.2"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
