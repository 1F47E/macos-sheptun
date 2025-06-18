//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "93da5400f3701052e9fb6c4e6a5c2fb3863cac82"
    static let buildDate: String = "2025-06-18 19:14"
    static let gitBranch: String = "v0.2"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
