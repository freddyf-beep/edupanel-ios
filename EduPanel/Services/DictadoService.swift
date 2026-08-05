import AVFoundation
import CryptoKit
import Foundation
import Observation
import Speech
import UIKit

enum VoiceDictationMode: String, Codable, CaseIterable, Identifiable {
    case rapido
    case guiado

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rapido: return "Dictado rápido"
        case .guiado: return "Dictado guiado"
        }
    }
}

enum VoiceNoteStatus: String, Codable {
    case sinVincular
    case pendienteSincronizacion
    case vinculada

    var title: String {
        switch self {
        case .sinVincular: return "Sin vincular"
        case .pendienteSincronizacion: return "Pendiente de guardar"
        case .vinculada: return "Vinculada"
        }
    }
}

enum VoiceObservationScope: String, Codable, CaseIterable, Identifiable {
    case general
    case individual
    case grupal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .individual: return "Individual"
        case .grupal: return "Grupal"
        }
    }
}

struct VoiceNoteContext: Codable, Equatable, Hashable {
    var courseID: String?
    var courseName: String?
    var courseKind: AcademicCourseKind?
    var subjectID: String?
    var subjectName: String?
    var classID: String?
    var classTitle: String?
    var dateKey: String?
    var unitID: String?
    var unitName: String?
    var activityID: String?
    var observationScope: VoiceObservationScope = .general
    var studentIDs: [String] = []
    var topic: String?
    var observationType: String?
    var outcome: String?
    var nextStep: String?
    var classSummary: String?

    var isLinkedToClass: Bool {
        !(classID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var contextLabel: String {
        let parts = [courseName, subjectName, unitName]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? nil : clean
            }
        return parts.isEmpty ? "Sin contexto" : parts.joined(separator: " · ")
    }

    /// Los nombres de estudiantes y antecedentes PIE nunca forman parte del
    /// contexto de reconocimiento ni de futuros payloads de IA.
    var safeContextualStrings: [String] {
        [courseName, subjectName, unitName, topic]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Contexto persistible junto al leccionario. Mantiene los identificadores
    /// separados del texto visible y evita tener que volver a inferirlos desde
    /// una transcripción libre.
    var attendanceMetadata: AttendanceVoiceNoteMetadata {
        AttendanceVoiceNoteMetadata(
            observationScope: observationScope.rawValue,
            studentIDs: studentIDs,
            topic: topic,
            observationType: observationType,
            outcome: outcome,
            nextStep: nextStep,
            summary: classSummary
        )
    }
}

enum VoiceNoteLinkingError: LocalizedError, Equatable {
    case contentChanged

    var errorDescription: String? {
        switch self {
        case .contentChanged:
            return "Esta nota ya existe en la clase con otro contenido. Conservamos tu corrección; puedes guardarla como una nota nueva."
        }
    }
}

struct VoiceNoteDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var mode: VoiceDictationMode
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var status: VoiceNoteStatus
    var context: VoiceNoteContext

    init(
        id: UUID = UUID(),
        mode: VoiceDictationMode,
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: VoiceNoteStatus = .sinVincular,
        context: VoiceNoteContext = VoiceNoteContext()
    ) {
        self.id = id
        self.mode = mode
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.context = context
    }

    var hasMeaningfulContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum VoiceNoteDraftStoreError: LocalizedError {
    case invalidOwner

    var errorDescription: String? {
        "No hay una sesión válida para guardar esta nota."
    }
}

actor VoiceNoteDraftStore {
    static let shared = VoiceNoteDraftStore()

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load(ownerID: String) throws -> [VoiceNoteDraft] {
        let fileURL = try fileURL(ownerID: ownerID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([VoiceNoteDraft].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func upsert(_ draft: VoiceNoteDraft, ownerID: String) throws -> VoiceNoteDraft {
        guard draft.hasMeaningfulContent else {
            try delete(id: draft.id, ownerID: ownerID)
            return draft
        }
        var value = draft
        value.updatedAt = Date()
        var items = try load(ownerID: ownerID)
        if let index = items.firstIndex(where: { $0.id == value.id }) {
            items[index] = value
        } else {
            items.append(value)
        }
        try write(items, ownerID: ownerID)
        return value
    }

    func delete(id: UUID, ownerID: String) throws {
        let items = try load(ownerID: ownerID).filter { $0.id != id }
        try write(items, ownerID: ownerID)
    }

    /// Reemplaza atómicamente la identidad local de un borrador. Se usa
    /// cuando el servidor confirma que el UUID anterior ya representa otra
    /// versión: la corrección queda como una nota nueva sin dejar dos borradores.
    @discardableResult
    func reidentify(_ draft: VoiceNoteDraft, ownerID: String) throws -> VoiceNoteDraft {
        var replacement = draft
        let previousID = replacement.id
        replacement.id = UUID()
        replacement.updatedAt = Date()

        var items = try load(ownerID: ownerID)
        if let index = items.firstIndex(where: { $0.id == previousID }) {
            items[index] = replacement
        } else {
            items.append(replacement)
        }
        try write(items, ownerID: ownerID)
        return replacement
    }

    private func write(_ items: [VoiceNoteDraft], ownerID: String) throws {
        let fileURL = try fileURL(ownerID: ownerID)
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        if items.isEmpty {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
            return
        }
        let data = try encoder.encode(items.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private func fileURL(ownerID: String) throws -> URL {
        let clean = ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VoiceNoteDraftStoreError.invalidOwner }
        let digest = SHA256.hash(data: Data(clean.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("EduPanel", isDirectory: true)
            .appendingPathComponent("VoiceNotes", isDirectory: true)
    }
}

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
    private var lastLevelEmission = 0.0
    private let levelLock = NSLock()

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
        do {
            guard recognizer.isAvailable else { throw DictationEngineError.unavailable }

            let session = AVAudioSession.sharedInstance()
#if compiler(>=6.2)
            let bluetoothOption: AVAudioSession.CategoryOptions = .allowBluetoothHFP
#else
            let bluetoothOption: AVAudioSession.CategoryOptions = .allowBluetooth
#endif
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, bluetoothOption])
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
            levelLock.lock()
            lastLevelEmission = 0
            levelLock.unlock()
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.request?.append(buffer)
                let now = ProcessInfo.processInfo.systemUptime
                self.levelLock.lock()
                let shouldEmitLevel = now - self.lastLevelEmission >= 0.08
                if shouldEmitLevel { self.lastLevelEmission = now }
                self.levelLock.unlock()
                guard shouldEmitLevel else { return }
                onLevel(Self.level(from: buffer))
            }
            tapInstalled = true

            task = recognizer.recognitionTask(with: nextRequest) { result, error in
                if let result { onResult(result.bestTranscription.formattedString, result.isFinal) }
                if let error { onFailure(error) }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            // `audioEngine.start()` puede fallar después de instalar el tap y
            // crear la solicitud. La limpieza debe ocurrir antes de propagar
            // el error para no dejar el micrófono o la sesión activos.
            cancel()
            throw error
        }
    }

    func cancel() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        levelLock.lock()
        lastLevelEmission = 0
        levelLock.unlock()
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
            ? "EduPanel no añade nombres ni datos PIE como contexto. La transcripción se procesa en este dispositivo."
            : "EduPanel no añade nombres ni datos PIE como contexto. Apple puede procesar lo que pronuncies según tus ajustes de Dictado."
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
            contextualStrings + ["Mineduc", "EduPanel", "leccionario", "planificación", "retroalimentación", "apoderado"]
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
        let authorizationGeneration = UUID()
        generation = authorizationGeneration
        state = .requestingPermission
        Task { await authorizeAndStart(generation: authorizationGeneration) }
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

    func updateContextualStrings(_ values: [String]) {
        recognizer?.contextualStrings = Array(Set(
            values + ["Mineduc", "EduPanel", "leccionario", "planificación", "retroalimentación", "apoderado"]
        )).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func authorizeAndStart(generation authorizationGeneration: UUID) async {
        let speechPermission = await permissions.requestSpeechPermission()
        guard generation == authorizationGeneration, state == .requestingPermission else { return }

        switch speechPermission {
        case .authorized: break
        case .denied:
            state = .error("Activa Reconocimiento de voz en Ajustes para usar Dictado.")
            return
        case .restricted:
            state = .error("El reconocimiento de voz está restringido en este dispositivo.")
            return
        }

        let hasMicrophonePermission = await permissions.requestMicrophonePermission()
        guard generation == authorizationGeneration, state == .requestingPermission else { return }
        guard hasMicrophonePermission else {
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
            recognizer.cancel()
            audioLevel = 0
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
