import AVFoundation
import Foundation
import Observation
import Speech
import UIKit

enum DictadoState: Equatable {
    case idle
    case requestingPermission
    case recording
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isBusy: Bool {
        self == .requestingPermission || isRecording
    }
}

/// Borrador local de una futura observación docente. En fase 1 no se persiste
/// ni se envía a servicios de análisis.
enum ClassFeedbackReviewStatus: String, Equatable, Sendable {
    case drafting
    case reviewed
    case approvedForFutureContext
}

struct ClassFeedbackDraft: Equatable, Sendable {
    var schoolID: String?
    var courseID: String?
    var subjectID: String?
    var blockID: String?
    var classDate: Date?
    var originalText: String
    var editedText: String
    var reviewStatus: ClassFeedbackReviewStatus
}

struct DictationTranscriptBuffer: Equatable {
    private(set) var confirmed = ""
    private(set) var partial = ""

    var displayedText: String {
        [confirmed, partial]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: confirmed.isEmpty || partial.isEmpty ? "" : " ")
    }

    mutating func accept(_ text: String, isFinal: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            partial = ""
            appendConfirmed(clean)
        } else {
            partial = clean
        }
    }

    mutating func userEdited(_ text: String) {
        confirmed = text
        partial = ""
    }

    mutating func clear() {
        confirmed = ""
        partial = ""
    }

    private mutating func appendConfirmed(_ text: String) {
        guard !text.isEmpty else { return }
        if confirmed.isEmpty { confirmed = text; return }
        // Algunos reinicios entregan nuevamente el final anterior. Solo se
        // descarta cuando el segmento coincide completo, nunca por similitud.
        guard confirmed != text, !confirmed.hasSuffix(" \(text)") else { return }
        confirmed += confirmed.last?.isWhitespace == true ? text : " \(text)"
    }
}

enum DictationPermissionResult: Equatable {
    case authorized
    case denied
    case restricted
}

protocol DictationPermissionProviding {
    func requestSpeechPermission() async -> DictationPermissionResult
    func requestMicrophonePermission() async -> Bool
}

protocol DictationRecognizing: AnyObject {
    var localeIdentifier: String { get }
    var usesOnDeviceRecognition: Bool { get }
    var contextualStrings: [String] { get set }
    func start(
        onResult: @escaping (String, Bool) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (Error) -> Void
    ) throws
    func cancel()
}

struct AppleDictationPermissions: DictationPermissionProviding {
    func requestSpeechPermission() async -> DictationPermissionResult {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: continuation.resume(returning: .authorized)
                case .restricted: continuation.resume(returning: .restricted)
                case .denied, .notDetermined: continuation.resume(returning: .denied)
                @unknown default: continuation.resume(returning: .denied)
                }
            }
        }
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}

final class AppleDictationRecognizer: DictationRecognizing {
    private let recognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    let localeIdentifier: String
    private(set) var usesOnDeviceRecognition = false
    var contextualStrings: [String] = []

    init?() {
        let preferred = SFSpeechRecognizer(locale: Locale(identifier: "es-CL"))
        let fallback = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        guard let selected = preferred ?? fallback else { return nil }
        recognizer = selected
        localeIdentifier = selected.locale.identifier
    }

    func start(
        onResult: @escaping (String, Bool) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (Error) -> Void
    ) throws {
        cancel()
        guard recognizer.isAvailable else { throw DictationEngineError.unavailable }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let nextRequest = SFSpeechAudioBufferRecognitionRequest()
        nextRequest.shouldReportPartialResults = true
        nextRequest.taskHint = .dictation
        nextRequest.contextualStrings = contextualStrings
        if #available(iOS 16.0, *) { nextRequest.addsPunctuation = true }
        if recognizer.supportsOnDeviceRecognition {
            nextRequest.requiresOnDeviceRecognition = true
            usesOnDeviceRecognition = true
        } else {
            usesOnDeviceRecognition = false
        }
        request = nextRequest

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            onLevel(Self.level(from: buffer))
        }
        tapInstalled = true

        task = recognizer.recognitionTask(with: nextRequest) { result, error in
            if let result { onResult(result.bestTranscription.formattedString, result.isFinal) }
            if let error { onFailure(error) }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func cancel() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit { cancel() }

    private static func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        return max(0, min(1, sqrt(sum / Float(buffer.frameLength)) * 5))
    }
}

enum DictationEngineError: LocalizedError {
    case unavailable

    var errorDescription: String? { "El reconocimiento de voz no está disponible en este momento." }
}

@Observable
@MainActor
final class DictadoService {
    var state: DictadoState = .idle
    private(set) var transcribedText = ""
    private(set) var audioLevel: Float = 0
    private(set) var localeIdentifier = "es-CL"
    private(set) var usesOnDeviceRecognition = false

    var privacyDescription: String {
        usesOnDeviceRecognition
            ? "La transcripción se procesa en este dispositivo y no se guarda."
            : "La nota no se guarda ni se envía a EduPanel; iOS puede usar el servicio de dictado de Apple."
    }

    private let permissions: DictationPermissionProviding
    private let recognizer: DictationRecognizing?
    private var buffer = DictationTranscriptBuffer()
    private var generation = UUID()
    private var restartAttempts = 0
    private var observers: [NSObjectProtocol] = []

    init(
        contextualStrings: [String] = [],
        permissions: DictationPermissionProviding = AppleDictationPermissions(),
        recognizer: DictationRecognizing? = AppleDictationRecognizer()
    ) {
        self.permissions = permissions
        self.recognizer = recognizer
        recognizer?.contextualStrings = Array(Set(
            contextualStrings + ["Mineduc", "EduPanel", "leccionario", "planificación", "retroalimentación", "apoderado", "PIE"]
        )).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        localeIdentifier = recognizer?.localeIdentifier ?? "es-CL"
        observeLifecycle()
    }

    func toggleDictado() {
        guard state != .requestingPermission else { return }
        state.isRecording ? stopDictado() : startDictado()
    }

    func startDictado() {
        guard !state.isBusy else { return }
        guard recognizer != nil else {
            state = .error("Este dispositivo no ofrece reconocimiento de voz en español.")
            return
        }
        state = .requestingPermission
        Task { await authorizeAndStart() }
    }

    func stopDictado() {
        generation = UUID()
        recognizer?.cancel()
        restartAttempts = 0
        audioLevel = 0
        state = .idle
    }

    func updateText(_ text: String) {
        buffer.userEdited(text)
        transcribedText = buffer.displayedText
        if state.isRecording { restartAfterManualEdit() }
    }

    func clearText() {
        buffer.clear()
        transcribedText = ""
        if state.isRecording { restartAfterManualEdit() }
    }

    private func authorizeAndStart() async {
        switch await permissions.requestSpeechPermission() {
        case .authorized: break
        case .denied:
            state = .error("Activa Reconocimiento de voz en Ajustes para usar Dictado.")
            return
        case .restricted:
            state = .error("El reconocimiento de voz está restringido en este dispositivo.")
            return
        }
        guard await permissions.requestMicrophonePermission() else {
            state = .error("Activa el micrófono en Ajustes para usar Dictado.")
            return
        }
        restartAttempts = 0
        beginRecognition()
    }

    private func beginRecognition() {
        guard let recognizer else { return }
        let currentGeneration = UUID()
        generation = currentGeneration
        do {
            try recognizer.start(
                onResult: { [weak self] text, isFinal in
                    Task { @MainActor in self?.receive(text, isFinal: isFinal, generation: currentGeneration) }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        guard self?.generation == currentGeneration else { return }
                        self?.audioLevel = level
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in self?.handleFailure(error, generation: currentGeneration) }
                }
            )
            usesOnDeviceRecognition = recognizer.usesOnDeviceRecognition
            state = .recording
        } catch {
            state = .error("No se pudo iniciar el dictado: \(error.localizedDescription)")
        }
    }

    private func receive(_ text: String, isFinal: Bool, generation: UUID) {
        guard self.generation == generation, state.isRecording else { return }
        buffer.accept(text, isFinal: isFinal)
        transcribedText = buffer.displayedText
        if isFinal { scheduleRestart(generation: generation) }
    }

    private func handleFailure(_ error: Error, generation: UUID) {
        guard self.generation == generation, state.isRecording else { return }
        scheduleRestart(generation: generation, terminalMessage: error.localizedDescription)
    }

    private func scheduleRestart(generation: UUID, terminalMessage: String? = nil) {
        guard self.generation == generation, restartAttempts < 3 else {
            state = .error(terminalMessage ?? "El dictado se interrumpió. Toca el micrófono para continuar.")
            recognizer?.cancel()
            return
        }
        restartAttempts += 1
        recognizer?.cancel()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard self.generation == generation, self.state.isRecording else { return }
            self.beginRecognition()
        }
    }

    private func restartAfterManualEdit() {
        let old = generation
        recognizer?.cancel()
        restartAttempts = 0
        guard generation == old, state.isRecording else { return }
        beginRecognition()
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopDictado() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                self?.stopDictado()
                self?.state = .error("El dictado se pausó porque otra app necesita el audio.")
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.state.isRecording == true else { return }
                self?.restartAfterManualEdit()
            }
        })
    }
}
