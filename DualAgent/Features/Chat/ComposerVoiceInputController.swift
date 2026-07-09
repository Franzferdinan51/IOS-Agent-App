//
//  ComposerVoiceInputController.swift
//  DualAgent
//
//  Backend-neutral dictation controller for the chat composer. Port of the
//  spirit of Hermex's `ComposerVoiceInputController` (issues #212, #338)
//  trimmed down for DualAgent's single composer surface.
//
//  What this does:
//    - Requests Speech + Mic permission on first activation.
//    - Streams partial transcripts into the composer via an `updateDraft`
//      callback (so the live text appears as the user speaks).
//    - Stops on toggle, on submit, or when the user clears the field.
//    - Honors Reduce Motion: we don't pulse the icon, just display state.
//    - When the backend is Hermes, the dictation fills the composer and the
//      user can still hit send; the dictation never posts directly.
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
@Observable
final class ComposerVoiceInputController {

    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript: String = ""

    /// Optional override for tests / previews.
    var speechRecognizerFactory: () -> AnyObject? = {
        #if canImport(Speech)
        return SFSpeechRecognizer(locale: Locale.current)
        #else
        return nil
        #endif
    }

    private let audioEngineFactory: () -> AnyObject
    private var audioEngine: AnyObject?
    private var recognitionRequest: AnyObject?
    private var recognitionTask: AnyObject?

    private var updateDraft: ((String) -> Void)?
    private var activatedAudioSession = false
    private var audioTapInstalled = false

    init(audioEngineFactory: @escaping () -> AnyObject = {
        #if canImport(AVFoundation)
        return AVAudioEngine()
        #else
        return NSObject()
        #endif
    }) {
        self.audioEngineFactory = audioEngineFactory
    }

    var isListening: Bool { state == .listening }

    /// Tap-to-toggle entry point used by the composer mic button.
    func toggle(currentDraft: String, updateDraft: @escaping (String) -> Void) async {
        if isListening {
            stopKeepingTranscript()
        } else {
            await start(currentDraft: currentDraft, updateDraft: updateDraft)
        }
    }

    /// Stop without losing the draft (user pressed the same mic button again).
    func stopKeepingTranscript() {
        stopAudio(cancelTask: false)
        state = .idle
    }

    /// Stop before submitting. Cancels any in-flight recognition to free the mic.
    func stopBeforeSubmitting() {
        stopAudio(cancelTask: true)
        state = .idle
    }

    // MARK: - Lifecycle

    private func start(currentDraft: String, updateDraft: @escaping (String) -> Void) async {
        guard state == .idle else { return }
        liveTranscript = ""
        self.updateDraft = updateDraft
        state = .requestingPermission

        #if canImport(Speech)
        let speechRecognizer = speechRecognizerFactory() as? SFSpeechRecognizer
        guard let speechRecognizer else {
            state = .error("Speech recognition is not available for the current locale.")
            return
        }
        guard speechRecognizer.isAvailable else {
            state = .error("Speech recognition is temporarily unavailable.")
            return
        }
        #else
        state = .error("Speech recognition is not available on this platform.")
        return
        #endif

        let speechStatus: Int = await withCheckedContinuation { cont in
            #if canImport(Speech)
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status.rawValue)
            }
            #else
            cont.resume(returning: 0)
            #endif
        }
        guard state == .requestingPermission else { return }
        guard speechStatus == SFSpeechRecognizerAuthorizationStatus.authorized.rawValue else {
            state = .error("Speech recognition access is disabled. Enable it in Settings.")
            return
        }

        let micGranted = await requestMicrophonePermission()
        guard state == .requestingPermission else { return }
        guard micGranted else {
            state = .error("Microphone access is disabled. Enable it in Settings to use voice input.")
            return
        }

        do {
            #if canImport(AVFoundation) && canImport(Speech)
            try startRecognition(speechRecognizer: speechRecognizer, baseDraft: currentDraft)
            state = .listening
            #else
            state = .error("Voice input is not supported on this platform.")
            #endif
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            #if canImport(AVFoundation)
            let session = AVAudioSession.sharedInstance()
            session.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
            #else
            cont.resume(returning: false)
            #endif
        }
    }

    #if canImport(AVFoundation) && canImport(Speech)
    private func startRecognition(speechRecognizer: SFSpeechRecognizer, baseDraft: String) throws {
        stopAudio(cancelTask: true)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        activatedAudioSession = true

        guard let audioEngine = audioEngineFactory() as? AVAudioEngine else {
            throw NSError(domain: "ComposerVoice", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio engine unavailable"])
        }
        self.audioEngine = audioEngine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Capture the initial commit so partial results append to the base draft.
        var composedDraft = baseDraft

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    if !transcript.isEmpty {
                        composedDraft = Self.composedDraft(baseDraft: baseDraft, transcript: transcript)
                        self.liveTranscript = transcript
                        self.updateDraft?(composedDraft)
                    }
                    if result.isFinal {
                        self.stopKeepingTranscript()
                    }
                }
                if let error {
                    // Some failures are expected after stop; ignore if we're already idle.
                    if self.isListening {
                        self.state = .error(error.localizedDescription)
                        self.stopKeepingTranscript()
                    }
                }
            }
        }
        self.recognitionTask = task
    }
    #endif

    private func stopAudio(cancelTask: Bool) {
        #if canImport(AVFoundation) && canImport(Speech)
        if cancelTask, let task = recognitionTask as? SFSpeechRecognitionTask {
            task.cancel()
        }
        recognitionTask = nil
        if let request = recognitionRequest as? SFSpeechAudioBufferRecognitionRequest {
            request.endAudio()
        }
        recognitionRequest = nil
        if audioTapInstalled, let engine = audioEngine as? AVAudioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        audioTapInstalled = false
        if let engine = audioEngine as? AVAudioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        if activatedAudioSession {
            #if canImport(AVFoundation)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            activatedAudioSession = false
        }
        #endif
    }

    // MARK: - Helpers

    /// Compose a base draft with a live transcript, preserving the user's
    /// original draft and only appending new transcript content.
    /// Mirrors Hermex's `ComposerVoiceDraftComposer.composedDraft` semantics:
    /// blank base + blank transcript = blank; non-blank base + transcript =
    /// "<base> <transcript>"; blank base + transcript = "<transcript>".
    static func composedDraft(baseDraft: String, transcript: String) -> String {
        let base = baseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return text }
        if text.isEmpty { return base }
        return "\(base) \(text)"
    }
}
