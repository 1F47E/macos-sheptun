//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "738803e2051278237d8318a24571d24b588485f6"
    static let buildDate: String = "2025-06-19 10:45"
    static let gitBranch: String = "v0.2"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
