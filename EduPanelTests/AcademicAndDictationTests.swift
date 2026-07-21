import AVFoundation
import UIKit
import XCTest
@testable import EduPanel

final class AcademicContractTests: XCTestCase {
    func testOfficialCourseIdentityMatchesWebContract() throws {
        XCTAssertEqual(try AcademicContract.officialCourseName(level: "5to Básico", section: "b"), "5° Básico B")
        XCTAssertEqual(AcademicContract.normalizedKey("5° Básico B"), "5_basico_b")
        XCTAssertThrowsError(try AcademicContract.officialCourseName(level: "5to Básico", section: "AA"))
    }

    func testPublishedPeriodsUseSantiagoCivilDateAndCannotOverlap() throws {
        let first = period(id: "one", start: "2026-03-01", end: "2026-07-31")
        let second = period(id: "two", start: "2026-07-31", end: "2026-12-31")

        XCTAssertThrowsError(try AcademicContract.validatePublishedPeriod(second, among: [first])) {
            XCTAssertEqual($0 as? AcademicContractError, .overlappingPublishedPeriod)
        }
        let noonUTC = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-21T02:30:00Z"))
        XCTAssertEqual(AcademicContract.dateKey(for: noonUTC), "2026-07-20")
    }

    func testScheduleBatchRejectsCollisionAndRequiresJourneyModule() throws {
        let module = JourneyModule(moduleID: "m1", name: "Primero", startTime: "08:00", endTime: "08:45", kind: .lectivo)
        let journey = JourneyConfig(version: 2, region: "CL", year: 2026, activeDays: [.monday], modulesByDay: [.monday: [module]])
        let valid = block(id: "a", start: "08:00", end: "08:45", moduleID: "m1")
        XCTAssertNoThrow(try AcademicContract.validateBatch(existing: [], candidates: [valid], journey: journey))

        let invalidModule = block(id: "b", start: "09:00", end: "09:45")
        XCTAssertThrowsError(try AcademicContract.validateBatch(existing: [], candidates: [invalidModule], journey: journey))

        let exceptional = block(id: "c", start: "09:00", end: "09:45", exceptional: true)
        XCTAssertNoThrow(try AcademicContract.validateBatch(existing: [], candidates: [exceptional], journey: journey))

        let collision = block(id: "d", start: "08:30", end: "09:00", exceptional: true)
        XCTAssertThrowsError(try AcademicContract.validateBatch(existing: [valid], candidates: [collision], journey: journey))
    }

    func testTranscriptBufferPreservesManualCorrectionsAcrossPartials() {
        var buffer = DictationTranscriptBuffer()
        buffer.accept("La clase comenzó", isFinal: false)
        XCTAssertEqual(buffer.displayedText, "La clase comenzó")
        buffer.userEdited("La clase comenzó puntualmente.")
        buffer.accept("Luego revisamos la tarea", isFinal: false)
        XCTAssertEqual(buffer.displayedText, "La clase comenzó puntualmente. Luego revisamos la tarea")
        buffer.accept("Luego revisamos la tarea.", isFinal: true)
        XCTAssertEqual(buffer.displayedText, "La clase comenzó puntualmente. Luego revisamos la tarea.")
    }

    func testDecodesV2CourseJourneyPeriodAndBlock() throws {
        let course = try XCTUnwrap(AcademicCourse.from(id: "course-id", dictionary: [
            "courseId": "course-id", "dataKey": "5_basico_b", "tipo": "oficial", "nombre": "5° Básico B",
            "nivel": "5to Básico", "seccion": "B", "asignaturas": [["id": "matematica", "label": "Matemática"]],
            "color": "#EC4899", "estado": "active",
        ]))
        XCTAssertEqual(course.courseID, "course-id")
        XCTAssertEqual(course.subjects.first?.id, "matematica")

        let journey = try XCTUnwrap(JourneyConfig.from(dictionary: [
            "version": 2, "region": "CL", "anio": 2026, "diasActivos": ["Lunes", "Sábado"],
            "modulosPorDia": ["Lunes": [["moduleId": "m1", "nombre": "Primero", "horaInicio": "10:00", "horaFin": "10:45", "tipo": "lectivo"]]],
        ]))
        XCTAssertEqual(journey.activeDays, [.monday, .saturday])

        let period = try XCTUnwrap(SchedulePeriod.from(id: "p1", dictionary: [
            "periodId": "p1", "nombre": "Segundo semestre", "inicio": "2026-07-01", "termino": "2026-12-31",
            "estado": "published", "zonaHoraria": "America/Santiago", "bloques": [[
                "uid": "b1", "resumen": "5° Básico B", "dia": "Lunes", "horaInicio": "10:00", "horaFin": "10:45",
                "color": "#EC4899", "tipo": "clase", "asignatura": "Matemática", "courseId": "course-id",
                "subjectId": "matematica", "moduleId": "m1",
            ]],
        ]))
        XCTAssertEqual(period.blocks.first?.courseID, "course-id")
        XCTAssertEqual(period.blocks.first?.moduleID, "m1")
    }

    func testScheduleResolutionFallsBackOnlyWhenNoPublishedPeriodContainsDate() throws {
        let legacy = [block(id: "legacy", start: "08:00", end: "08:45", exceptional: true)]
        let current = period(id: "current", start: "2026-03-01", end: "2026-07-31", blocks: [block(id: "v2", start: "10:00", end: "10:45", exceptional: true)])
        let july = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        let august = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T12:00:00Z"))
        XCTAssertEqual(AcademicContract.resolveSchedule([current], legacy: legacy, for: july).first?.id, "v2")
        XCTAssertEqual(AcademicContract.resolveSchedule([current], legacy: legacy, for: august).first?.id, "legacy")
    }

    func testBatchSupportsDifferentTimesAcrossDaysAndMultipleBlocksPerDay() throws {
        let candidates = [
            block(id: "mon-1", day: "Lunes", start: "10:00", end: "10:45", exceptional: true),
            block(id: "mon-2", day: "Lunes", start: "11:00", end: "11:45", exceptional: true),
            block(id: "tue", day: "Martes", start: "14:00", end: "14:45", exceptional: true),
        ]
        XCTAssertNoThrow(try AcademicContract.validateBatch(existing: [], candidates: candidates, journey: nil))
        let collision = block(id: "mon-overlap", day: "Lunes", start: "10:30", end: "11:15", exceptional: true)
        XCTAssertThrowsError(try AcademicContract.validateBatch(existing: [], candidates: candidates + [collision], journey: nil))
    }

    func testSaturdayIsOptionalAndPauseRequiresExceptionalMode() throws {
        let pause = JourneyModule(moduleID: "break", name: "Recreo", startTime: "10:00", endTime: "10:20", kind: .recreo)
        let saturday = JourneyConfig(version: 2, region: "CL", year: 2026, activeDays: [.saturday], modulesByDay: [.saturday: [pause]])
        let candidate = block(id: "sat", day: "Sábado", start: "10:00", end: "10:20", moduleID: "break")
        XCTAssertThrowsError(try AcademicContract.validateBatch(existing: [], candidates: [candidate], journey: saturday))
        let exceptional = block(id: "sat-ex", day: "Sábado", start: "10:00", end: "10:20", moduleID: "break", exceptional: true)
        XCTAssertNoThrow(try AcademicContract.validateBatch(existing: [], candidates: [exceptional], journey: saturday))
        let weekdaysOnly = JourneyConfig(version: 2, region: "CL", year: 2026, activeDays: [.monday], modulesByDay: [:])
        XCTAssertThrowsError(try AcademicContract.validateBatch(existing: [], candidates: [exceptional], journey: weekdaysOnly))
    }

    func testWorkshopHasNoCurriculumInheritanceAndArchiveGraceIsEnforced() throws {
        let workshop = AcademicCourse(
            courseID: "workshop", dataKey: "robotica_workshop", kind: .taller, name: "Robótica", level: nil,
            section: nil, workshopName: "Robótica", subjects: [], colorHex: "#8B5CF6", status: .archived,
            archivedAt: Date(), deleteEligibleAt: Date().addingTimeInterval(29 * 86_400)
        )
        XCTAssertNil(workshop.level)
        XCTAssertTrue(workshop.subjects.isEmpty)
        XCTAssertFalse(workshop.isDeleteEligible)
        var eligible = workshop
        eligible.deleteEligibleAt = Date().addingTimeInterval(-1)
        XCTAssertTrue(eligible.isDeleteEligible)
    }

    func testLegacyRepairIsIdempotentWhenExecutedTwice() throws {
        let legacy = [block(id: "legacy", start: "08:00", end: "08:45", exceptional: true)]
        let first = try AcademicContract.legacyCourseCandidates(
            schedule: legacy,
            levelMapping: ["5° Básico B": "5to Básico"],
            courseKinds: ["5° Básico B": .oficial],
            excludingDataKeys: []
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.kind, .oficial)
        let second = try AcademicContract.legacyCourseCandidates(
            schedule: legacy,
            levelMapping: ["5° Básico B": "5to Básico"],
            courseKinds: ["5° Básico B": .oficial],
            excludingDataKeys: Set(first.map(\.dataKey))
        )
        XCTAssertTrue(second.isEmpty)
    }

    @MainActor
    func testScheduleExportProducesARealPDFInTemporaryDirectory() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("edupanel-schedule-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: output) }
        ScheduleExporter.renderToFile(
            horario: [block(id: "export", start: "08:00", end: "08:45", exceptional: true)],
            teacherName: "Docente de prueba",
            isLandscape: false,
            outputURL: output
        )
        let data = try Data(contentsOf: output)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1_000)
    }

    private func period(id: String, start: String, end: String, blocks: [ClaseHorario] = []) -> SchedulePeriod {
        SchedulePeriod(periodID: id, name: id, startDateKey: start, endDateKey: end, status: .published, timeZone: AcademicContract.timeZoneIdentifier, blocks: blocks)
    }

    private func block(id: String, day: String = "Lunes", start: String, end: String, moduleID: String? = nil, exceptional: Bool = false) -> ClaseHorario {
        ClaseHorario(
            id: id,
            resumen: "5° Básico B",
            dia: day,
            horaInicio: start,
            horaFin: end,
            colorHex: "#EC4899",
            tipo: .clase,
            asignatura: "Matemática",
            courseID: "course-id",
            subjectID: "matematica",
            moduleID: moduleID,
            exceptional: exceptional
        )
    }
}

@MainActor
final class DictadoServiceTests: XCTestCase {
    func testDoubleStartIsIgnoredAndManualEditRejectsLatePartial() async {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)

        service.startDictado()
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(recognizer.startCount, 1)
        XCTAssertEqual(service.state, .recording)

        recognizer.emit(text: "Texto parcial", final: false, session: 0)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.transcribedText, "Texto parcial")

        service.updateText("Texto corregido.")
        XCTAssertEqual(recognizer.startCount, 2)
        recognizer.emit(text: "Resultado atrasado", final: false, session: 0)
        recognizer.emit(text: "Continuación", final: false, session: 1)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.transcribedText, "Texto corregido. Continuación")
        XCTAssertTrue(service.privacyDescription.contains("dispositivo"))
        service.stopDictado()
    }

    func testDeniedPermissionDoesNotStartAudio() async {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: DeniedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(recognizer.startCount, 0)
        guard case .error = service.state else { return XCTFail("Debía informar el permiso denegado") }
    }

    func testRestrictedAndUnavailableRecognizersHaveExplicitErrors() async {
        let restricted = DictadoService(
            permissions: FixedDictationPermissions(speech: .restricted, microphone: true),
            recognizer: FakeDictationRecognizer()
        )
        restricted.startDictado()
        for _ in 0..<5 { await Task.yield() }
        guard case .error(let restrictedMessage) = restricted.state else {
            return XCTFail("Debía informar el permiso restringido")
        }
        XCTAssertTrue(restrictedMessage.contains("restringido"))

        let unavailable = DictadoService(
            permissions: AllowedDictationPermissions(),
            recognizer: nil
        )
        unavailable.startDictado()
        guard case .error(let unavailableMessage) = unavailable.state else {
            return XCTFail("Debía informar reconocedor no disponible")
        }
        XCTAssertTrue(unavailableMessage.contains("no ofrece"))
    }

    func testServerFallbackIsTransparentAndKeepsSpanishLocale() async {
        let recognizer = FakeDictationRecognizer(localeIdentifier: "es-CL", usesOnDeviceRecognition: false)
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(service.localeIdentifier, "es-CL")
        XCTAssertFalse(service.usesOnDeviceRecognition)
        XCTAssertTrue(service.privacyDescription.contains("Apple"))
        service.stopDictado()
    }

    func testFinalResultRotatesRecognizerOnceAndPreservesText() async throws {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }

        recognizer.emit(text: "Hoy trabajamos fracciones.", final: true, session: 0)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(recognizer.startCount, 2)
        XCTAssertEqual(service.transcribedText, "Hoy trabajamos fracciones.")
        recognizer.emit(text: "Hoy trabajamos fracciones.", final: true, session: 1)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.transcribedText, "Hoy trabajamos fracciones.")

        service.stopDictado()
        let textAtStop = service.transcribedText
        recognizer.emit(text: "Resultado tardío", final: false, session: 1)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.transcribedText, textAtStop)
        XCTAssertEqual(service.state, .idle)
    }

    func testStopRestartBackgroundRouteChangeAndClearAreControlled() async {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        recognizer.emit(text: "Registro de la clase", final: false, session: 0)
        for _ in 0..<3 { await Task.yield() }

        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(recognizer.startCount, 2)
        XCTAssertEqual(service.transcribedText, "Registro de la clase")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcribedText, "Registro de la clase")

        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(recognizer.startCount, 3)
        service.clearText()
        XCTAssertEqual(service.transcribedText, "")
        XCTAssertEqual(recognizer.startCount, 4)
        service.stopDictado()
    }

    func testAudioInterruptionStopsImmediatelyWithoutLosingText() async {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        for _ in 0..<5 { await Task.yield() }
        recognizer.emit(text: "Observación revisable", final: false, session: 0)
        for _ in 0..<3 { await Task.yield() }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        for _ in 0..<5 { await Task.yield() }
        guard case .error(let message) = service.state else {
            return XCTFail("La interrupción debía detener el dictado")
        }
        XCTAssertTrue(message.contains("otra app"))
        XCTAssertEqual(service.transcribedText, "Observación revisable")
    }

    func testPersistentRecognizerFailureStopsAfterThreeRestarts() async throws {
        let recognizer = FakeDictationRecognizer()
        let service = DictadoService(permissions: AllowedDictationPermissions(), recognizer: recognizer)
        service.startDictado()
        try await waitForStartCount(1, recognizer: recognizer)

        for session in 0..<3 {
            recognizer.fail(session: session)
            try await waitForStartCount(session + 2, recognizer: recognizer)
        }
        XCTAssertEqual(recognizer.startCount, 4)
        recognizer.fail(session: 3)
        for _ in 0..<5 { await Task.yield() }
        guard case .error = service.state else {
            return XCTFail("Un error persistente no debe crear un bucle de reinicio")
        }
        XCTAssertEqual(recognizer.startCount, 4)
    }

    private func waitForStartCount(_ expected: Int, recognizer: FakeDictationRecognizer) async throws {
        for _ in 0..<100 {
            if recognizer.startCount >= expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("El reconocedor no alcanzó \(expected) inicios")
        throw DictationTestTimeout.timedOut
    }
}

private enum DictationTestTimeout: Error { case timedOut }

private struct AllowedDictationPermissions: DictationPermissionProviding {
    func requestSpeechPermission() async -> DictationPermissionResult { .authorized }
    func requestMicrophonePermission() async -> Bool { true }
}

private struct DeniedDictationPermissions: DictationPermissionProviding {
    func requestSpeechPermission() async -> DictationPermissionResult { .denied }
    func requestMicrophonePermission() async -> Bool { false }
}

private struct FixedDictationPermissions: DictationPermissionProviding {
    let speech: DictationPermissionResult
    let microphone: Bool

    func requestSpeechPermission() async -> DictationPermissionResult { speech }
    func requestMicrophonePermission() async -> Bool { microphone }
}

private final class FakeDictationRecognizer: DictationRecognizing {
    let localeIdentifier: String
    let usesOnDeviceRecognition: Bool
    var contextualStrings: [String] = []
    private(set) var startCount = 0
    private var resultCallbacks: [(String, Bool) -> Void] = []
    private var failureCallbacks: [(Error) -> Void] = []

    init(localeIdentifier: String = "es-CL", usesOnDeviceRecognition: Bool = true) {
        self.localeIdentifier = localeIdentifier
        self.usesOnDeviceRecognition = usesOnDeviceRecognition
    }

    func start(
        onResult: @escaping (String, Bool) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (Error) -> Void
    ) throws {
        startCount += 1
        resultCallbacks.append(onResult)
        failureCallbacks.append(onFailure)
        onLevel(0.4)
    }

    func cancel() {}

    func emit(text: String, final: Bool, session: Int) {
        resultCallbacks[session](text, final)
    }

    func fail(session: Int) {
        failureCallbacks[session](DictationEngineError.unavailable)
    }
}
