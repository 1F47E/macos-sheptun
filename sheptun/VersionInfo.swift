//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "8d80dff9b23fbdb5b7001b805423cc930ee96a0a"
    static let buildDate: String = "2025-06-18 19:32"
    static let gitBranch: String = "v0.2"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
