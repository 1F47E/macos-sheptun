#!/bin/bash

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to VersionInfo.swift
VERSION_INFO_FILE="${SCRIPT_DIR}/sheptun/VersionInfo.swift"

# Get git information
GIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date +"%Y-%m-%d %H:%M")

# Create the VersionInfo.swift file
cat > "${VERSION_INFO_FILE}" << EOF
//
//  VersionInfo.swift
//  sheptun
//
//  Generated automatically at build time
//

import Foundation

struct VersionInfo {
    static let gitHash: String = "${GIT_HASH}"
    static let buildDate: String = "${BUILD_DATE}"
    static let gitBranch: String = "${GIT_BRANCH}"
    static let shortHash: String = {
        let hash = gitHash
        return String(hash.prefix(7))
    }()
    
    static var versionString: String {
        return "\(shortHash) • \(buildDate)"
    }
}
EOF

echo "Updated VersionInfo.swift with:"
echo "  Git Hash: ${GIT_HASH}"
echo "  Git Branch: ${GIT_BRANCH}"
echo "  Build Date: ${BUILD_DATE}"