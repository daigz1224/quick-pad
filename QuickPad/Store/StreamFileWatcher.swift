import Foundation
import CoreServices

/// Watches `~/.quickpad/stream.md` for external edits via FSEvents and
/// invokes `onChange` on the main queue after a short debounce window.
///
/// ## Why FSEvents instead of DispatchSource.FileSystemObject
///
/// The obvious Swift-native choice would be
/// `DispatchSource.makeFileSystemObjectSource(fileDescriptor:...)`, but
/// it watches a **file descriptor**, not a path. Atomic-save editors —
/// vim with its default `backupcopy=auto`, Emacs, most IDEs — write to
/// a temporary file and `rename(2)` it over the original. That unhooks
/// the fd-based watcher completely: it still points at the old inode,
/// which is now unlinked, and it goes silent forever.
///
/// FSEvents is path-based, survives rename + create + unlink, and is
/// the same API Finder uses under the hood. It also debounces across
/// the whole parent directory, which is exactly what we want since we
/// only care about one file.
final class StreamFileWatcher {

    /// Fired on the main queue whenever an FSEvents burst touches
    /// `stream.md` inside the watched directory, after a debounce
    /// window. Safe to call `StreamViewModel.load()` from here.
    var onChange: (() -> Void)?

    private let directory: URL
    private let fileName: String

    /// FSEvents delivers events on this queue. We debounce and then
    /// hop to `DispatchQueue.main` before invoking `onChange`.
    private let callbackQueue = DispatchQueue(
        label: "dev.quickpad.file-watcher",
        qos: .utility
    )
    private var stream: FSEventStreamRef?
    private var pendingFire: DispatchWorkItem?

    /// `100ms` matched with the FSEvents `latency` parameter — vim's
    /// atomic save fires `create` + `write` + `rename` in bursts under
    /// 10 ms, and we'd rather reload once than three times.
    private let debounceInterval: TimeInterval = 0.1

    /// When QuickPad itself writes to stream.md (edit, delete, append),
    /// the FSEvents callback would fire and cause a redundant reload that
    /// can interrupt an in-progress inline edit. The suppression window
    /// tells the watcher to ignore events until this date passes.
    private var suppressUntil: Date?

    /// Call before any programmatic write to stream.md so the watcher
    /// doesn't reload and interrupt the user.
    func suppressNextChange(for interval: TimeInterval = 0.3) {
        suppressUntil = Date().addingTimeInterval(interval)
    }

    init(fileURL: URL = MarkdownFileStore.streamFileURL) {
        self.directory = fileURL.deletingLastPathComponent()
        self.fileName = fileURL.lastPathComponent
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard stream == nil else { return }

        // FSEvents on a nonexistent path silently does nothing, so
        // make sure `~/.quickpad/` exists before we register.
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [directory.path] as CFArray
        let flags: UInt32 = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagFileEvents
        )

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, _, _) in
            guard let clientInfo else { return }
            let watcher = Unmanaged<StreamFileWatcher>
                .fromOpaque(clientInfo)
                .takeUnretainedValue()

            // With `kFSEventStreamCreateFlagUseCFTypes`, `eventPaths`
            // is actually a CFArrayRef of CFStringRefs. Bridge via
            // NSArray → [String].
            let cfArray = Unmanaged<NSArray>
                .fromOpaque(eventPaths)
                .takeUnretainedValue()
            guard let paths = cfArray as? [String] else { return }

            watcher.handle(paths: paths)
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            flags
        ) else {
            NSLog("QuickPad: FSEventStreamCreate failed for \(directory.path)")
            return
        }

        FSEventStreamSetDispatchQueue(created, callbackQueue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        pendingFire?.cancel()
        pendingFire = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - Event handling

    /// Called on `callbackQueue`. Filters for our target file, then
    /// schedules a debounced hop to main.
    private func handle(paths: [String]) {
        // If we're inside a suppression window (our own write just
        // happened), skip the event entirely.
        if let until = suppressUntil, Date() < until { return }

        let hit = paths.contains { path in
            (path as NSString).lastPathComponent == fileName
        }
        guard hit else { return }

        pendingFire?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        pendingFire = work
        callbackQueue.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }
}
