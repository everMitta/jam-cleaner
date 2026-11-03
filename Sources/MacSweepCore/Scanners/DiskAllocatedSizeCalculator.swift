import Darwin
import Foundation

/// Summary of physical disk blocks, file count, and modification date for a path or directory subtree.
public struct DirectorySizeMetrics: Sendable {
    public let allocatedBytes: UInt64
    public let fileCount: Int
    public let latestModified: Date?

    public init(allocatedBytes: UInt64, fileCount: Int, latestModified: Date?) {
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.latestModified = latestModified
    }
}

/// High-throughput POSIX `fts_open` physical disk block calculator (`st_blocks * 512`) with hard-link inode deduplication.
/// Never follows symbolic links (`FTS_PHYSICAL`) and respects protected components from `RuleKnowledgeBase`.
public enum DiskAllocatedSizeCalculator {
    private struct InodeKey: Hashable {
        let dev: dev_t
        let ino: ino_t
    }

    /// Computes physical allocated bytes (`st_blocks * 512`) for a file or directory without following symlinks.
    /// Strictly skips any file or directory that is not owned or deletable by the current user.
    public static func measure(
        path: String,
        protectedComponentNames: Set<String> = [],
        effectiveUID: uid_t = geteuid()
    ) -> DirectorySizeMetrics {
        let standardized = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        var rootStat = stat()
        guard lstat(standardized, &rootStat) == 0 else {
            return DirectorySizeMetrics(allocatedBytes: 0, fileCount: 0, latestModified: nil)
        }

        let mode = rootStat.st_mode & S_IFMT
        if mode == S_IFLNK {
            return DirectorySizeMetrics(allocatedBytes: 0, fileCount: 0, latestModified: nil)
        }

        guard SafetyGuardEngine.isPathUserDeletable(standardized) else {
            return DirectorySizeMetrics(allocatedBytes: 0, fileCount: 0, latestModified: nil)
        }

        if mode == S_IFREG {
            let bytes = UInt64(max(0, rootStat.st_blocks)) * 512
            let modDate = Date(timeIntervalSince1970: TimeInterval(rootStat.st_mtimespec.tv_sec))
            return DirectorySizeMetrics(allocatedBytes: bytes, fileCount: 1, latestModified: modDate)
        }

        guard mode == S_IFDIR else {
            return DirectorySizeMetrics(allocatedBytes: 0, fileCount: 0, latestModified: nil)
        }

        let cPath = strdup(standardized)
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]

        let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)!
        defer { fts_close(fts) }

        let currentUID = effectiveUID
        let blockedFlags = UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) | 0x0008_0000
        let requiredDirOwnerPerms = mode_t(S_IRUSR | S_IWUSR | S_IXUSR)

        var totalBytes: UInt64 = 0
        var fileCount: Int = 0
        var maxModTime: time_t = rootStat.st_mtimespec.tv_sec
        var seenHardLinks = Set<InodeKey>()

        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)

            if info == FTS_D {
                if entry.pointee.fts_level > 0 {
                    let name = withUnsafePointer(to: &entry.pointee.fts_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.fts_namelen) + 1) {
                            String(cString: $0)
                        }
                    }
                    if protectedComponentNames.contains(name) {
                        fts_set(fts, entry, FTS_SKIP)
                        continue
                    }
                    if let statp = entry.pointee.fts_statp {
                        if (statp.pointee.st_flags & blockedFlags) != 0 {
                            fts_set(fts, entry, FTS_SKIP)
                            continue
                        }
                        if currentUID != 0 {
                            if statp.pointee.st_uid != currentUID
                                || (statp.pointee.st_mode & requiredDirOwnerPerms) != requiredDirOwnerPerms
                            {
                                fts_set(fts, entry, FTS_SKIP)
                                continue
                            }
                        }
                    }
                }
            } else if info == FTS_F {
                if let statp = entry.pointee.fts_statp {
                    if (statp.pointee.st_flags & blockedFlags) != 0 {
                        continue
                    }
                    if currentUID != 0 && statp.pointee.st_uid != currentUID {
                        continue
                    }
                    if statp.pointee.st_nlink > 1 {
                        let key = InodeKey(dev: statp.pointee.st_dev, ino: statp.pointee.st_ino)
                        if !seenHardLinks.insert(key).inserted {
                            continue
                        }
                    }
                    let blocks = UInt64(max(0, statp.pointee.st_blocks))
                    totalBytes += blocks * 512
                    fileCount += 1
                    let mtime = statp.pointee.st_mtimespec.tv_sec
                    if mtime > maxModTime {
                        maxModTime = mtime
                    }
                }
            }
        }

        let latestDate = Date(timeIntervalSince1970: TimeInterval(maxModTime))
        return DirectorySizeMetrics(
            allocatedBytes: totalBytes,
            fileCount: fileCount,
            latestModified: latestDate
        )
    }
}
