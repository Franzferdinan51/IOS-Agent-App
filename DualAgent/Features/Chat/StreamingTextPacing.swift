//
//  StreamingTextPacing.swift
//  DualAgent
//
//  Pure helpers for paced streaming of assistant text. Mirrors Hermes's
//  StreamingWordDrain / StreamingTextFade pipeline (issues #212, #220).
//  Tokens arrive in bursts; the composer for replies visibly thrashes when
//  a "delta" event dumps 200+ chars at once. Instead we accumulate a
//  single user-visible buffer with a target cadence (30ms cadence per
//  drainable unit, default), revealing text gradually and reporting
//  `complete` once it catches up to the live stream within the lag bound.
//
//  The buffer is thread-safe; consume it via `AsyncStream<String>`.
//
//  Backend-neutral: the OpenClaw gateway's `chat` event stream and Hermes's
//  SSE both produce `UnifiedChatEvent.token(String)` deltas — this helper
//  doesn't care which one.
//

import Foundation

/// Pure helpers for pacing streamed assistant text at a word cadence.
///
/// A drainable "unit" is one word plus its trailing whitespace; leading
/// whitespace attaches to the first unit, and a trailing in-progress word
/// counts as a unit so buffers without whitespace still drain. Splitting
/// walks grapheme clusters, so emoji/ZWJ sequences and combining marks
/// are never split: `head + tail == text` always.
enum StreamingWordDrain {
    /// Number of drainable word units in `text`.
    static func unitCount(in text: String) -> Int {
        var count = 0
        var hasSeenNonWhitespace = false
        var previousWasWhitespace = false
        for character in text {
            let isWhitespace = character.isWhitespace
            if count == 0 {
                count = 1
            } else if previousWasWhitespace, !isWhitespace, hasSeenNonWhitespace {
                count += 1
            }
            if !isWhitespace { hasSeenNonWhitespace = true }
            previousWasWhitespace = isWhitespace
        }
        return count
    }

    /// Splits `text` after its first `unitCount` units; `head + tail == text`.
    static func splitAtUnitBoundary(_ text: String, unitCount: Int) -> (head: String, tail: String) {
        guard unitCount > 0, !text.isEmpty else { return ("", text) }
        var unitsSeen = 0
        var hasSeenNonWhitespace = false
        var previousWasWhitespace = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWhitespace = character.isWhitespace
            if unitsSeen == 0 {
                unitsSeen = 1
            } else if previousWasWhitespace, !isWhitespace, hasSeenNonWhitespace {
                unitsSeen += 1
                if unitsSeen > unitCount {
                    return (String(text[..<index]), String(text[index...]))
                }
            }
            if !isWhitespace { hasSeenNonWhitespace = true }
            previousWasWhitespace = isWhitespace
            index = text.index(after: index)
        }
        return (text, "")
    }

    /// Units to drain on one cadence tick. Normally one word; if the backlog
    /// would take longer than `maxLagNanoseconds` at `cadenceNanoseconds` per
    /// word, scales proportionally so display catches up within the bound.
    static func drainQuota(
        backlogUnitCount: Int,
        cadenceNanoseconds: UInt64,
        maxLagNanoseconds: UInt64
    ) -> Int {
        guard backlogUnitCount > 1 else { return 1 }
        guard cadenceNanoseconds > 0, maxLagNanoseconds > 0 else { return backlogUnitCount }
        let drainNanoseconds = Double(backlogUnitCount) * Double(cadenceNanoseconds)
        let quota = Int((drainNanoseconds / Double(maxLagNanoseconds)).rounded(.up))
        return min(backlogUnitCount, max(1, quota))
    }
}

/// Paced drainer. Hold one per assistant-message in flight, call `append`
/// from any thread as new tokens arrive, and consume `stream` to render
/// at the cadence.
final class StreamingTextPacer: @unchecked Sendable {
    private struct State {
        var target: String = ""
        var rendered: String = ""
    }

    private let lock = NSLock()
    private var state = State()
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<String>.Continuation?
    private(set) lazy var stream: AsyncStream<String> = AsyncStream { continuation in
        self.continuation = continuation
    }

    /// Default cadence: ~30ms per word, max 250ms of lag.
    static let defaultCadenceNs: UInt64 = 30_000_000
    static let defaultMaxLagNs: UInt64 = 250_000_000

    private let cadenceNs: UInt64
    private let maxLagNs: UInt64

    init(
        cadenceNanoseconds: UInt64 = StreamingTextPacer.defaultCadenceNs,
        maxLagNanoseconds: UInt64 = StreamingTextPacer.defaultMaxLagNs
    ) {
        self.cadenceNs = cadenceNanoseconds
        self.maxLagNs = maxLagNanoseconds
    }

    /// Append a new live token to the buffer. Idempotent against ordering
    /// within the same thread; coalesces concurrent calls.
    func append(_ piece: String) {
        lock.lock()
        state.target += piece
        let backlog = StreamingWordDrain.unitCount(in: drainable(target: state.target, already: state.rendered))
        lock.unlock()
        if backlog > 0 {
            scheduleTick()
        }
    }

    /// Mark the stream complete; one final flush ensures everything is
    /// rendered before `stream` finishes.
    func complete() {
        lock.lock()
        state.target += ""   // no-op; ensures last drainable tail surfaces
        lock.unlock()
        scheduleTick(final: true)
    }

    /// Cancel the pacer (e.g. on stop/cancel). Does not finish `stream`.
    func cancel() {
        lock.lock()
        state = State()
        lock.unlock()
        task?.cancel()
        task = nil
    }

    private func drainable(target: String, already: String) -> String {
        // Already-rendered prefix is the "already" slice; we want to find the
        // common prefix between (target) and (already). If (already) isn't a
        // prefix of (target), fall back to flushing whatever is left in target.
        if target.hasPrefix(already) {
            return String(target.dropFirst(already.count))
        }
        return target
    }

    private func scheduleTick(final: Bool = false) {
        lock.lock()
        if let task, !task.isCancelled, !final {
            // A tick is already pending; let it cover the new arrival.
            lock.unlock()
            return
        }
        let cadence = self.cadenceNs
        let maxLag = self.maxLagNs
        lock.unlock()

        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: cadence) } catch { return }
            self?.tick(final: final, cadence: cadence, maxLag: maxLag)
        }
    }

    private func tick(final: Bool, cadence: UInt64, maxLag: UInt64) {
        lock.lock()
        let tail = drainable(target: state.target, already: state.rendered)
        let backlogUnits = StreamingWordDrain.unitCount(in: tail)
        if backlogUnits == 0 {
            lock.unlock()
            if final { continuation?.finish() }
            return
        }
        let quota = final
            ? backlogUnits
            : StreamingWordDrain.drainQuota(
                backlogUnitCount: backlogUnits,
                cadenceNanoseconds: cadence,
                maxLagNanoseconds: maxLag
            )
        let (head, _) = StreamingWordDrain.splitAtUnitBoundary(tail, unitCount: quota)
        guard !head.isEmpty else {
            lock.unlock()
            // Nothing to drain this tick; reschedule only if there's still a backlog.
            if !final && !Task.isCancelled {
                scheduleTick(cadence: cadence, maxLag: maxLag)
            }
            return
        }
        state.rendered += head
        lock.unlock()
        continuation?.yield(head)
        if !final {
            scheduleTick(cadence: cadence, maxLag: maxLag)
        } else if StreamingWordDrain.unitCount(in: drainable(target: state.target, already: state.rendered)) == 0 {
            continuation?.finish()
        }
    }

    /// Reschedule via stored cadence/maxLag.
    private func scheduleTick(cadence: UInt64, maxLag: UInt64) {
        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: cadence) } catch { return }
            self?.tick(final: false, cadence: cadence, maxLag: maxLag)
        }
    }
}
