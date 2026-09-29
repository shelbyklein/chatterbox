import Foundation

/// Writes to a non-blocking descriptor without ever blocking the host: whatever the reader
/// hasn't taken yet waits here until the descriptor is writable again. One slow client or a
/// child that stops reading stdin can't stall everyone else.
final class OutputBuffer {
    let fd: Int32
    private let queue: DispatchQueue
    private var pending = Data()
    private var source: DispatchSourceWrite?
    private var sourceRunning = false
    private(set) var failed = false
    /// Called once when the other end goes away.
    var onFailure: (() -> Void)?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    var pendingBytes: Int { pending.count }

    func write(_ data: Data) {
        guard !failed, !data.isEmpty else { return }
        pending.append(data)
        flush()
    }

    private func flush() {
        while !pending.isEmpty {
            let written = pending.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                pending.removeFirst(written)
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                break
            } else {
                fail()
                return
            }
        }
        setWaiting(!pending.isEmpty)
    }

    private func setWaiting(_ waiting: Bool) {
        if waiting, source == nil {
            let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.flush() }
            self.source = source
        }
        guard let source, waiting != sourceRunning else { return }
        sourceRunning = waiting
        if waiting { source.resume() } else { source.suspend() }
    }

    private func fail() {
        failed = true
        pending = Data()
        onFailure?()
        onFailure = nil
    }

    /// Stops watching the descriptor. The owner closes it.
    func cancel() {
        guard let source else { return }
        if !sourceRunning { source.resume() }
        source.cancel()
        self.source = nil
        sourceRunning = false
    }
}
