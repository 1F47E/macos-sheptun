//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "60b7802124c5fa39a23bfded99fdf9145caa7a25"
    static let buildDate: String = "2025-06-21 19:28"
    static let gitBranch: String = "v0.2"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
