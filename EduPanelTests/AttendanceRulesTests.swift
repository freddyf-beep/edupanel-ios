import XCTest
import SwiftUI
@testable import EduPanel

final class AttendanceRulesTests: XCTestCase {
    func testNewListStartsUnconfirmedAndDoesNotCountInSummary() throws {
        let block = try XCTUnwrap(makeNewBlock())

        XCTAssertEqual(block.attendance.count, 3)
        XCTAssertTrue(block.attendance.allSatisfy { $0.status == .present })
        XCTAssertTrue(block.attendance.allSatisfy { $0.confirmed == false })
        XCTAssertEqual(AttendanceRules.summary(for: block).present, 0)
        XCTAssertEqual(AttendanceRules.summary(for: block).pending, 3)
        XCTAssertFalse(AttendanceRules.canSign(block))
    }

    func testConfirmAllPresentUsesOneTimestampAndBulkMethod() throws {
        let block = try XCTUnwrap(makeNewBlock())
        let timestamp = "2026-07-18T12:00:00Z"
        let marked = AttendanceRules.confirmAll(block.attendance, markedAt: timestamp)

        XCTAssertTrue(marked.allSatisfy { $0.confirmed == true })
        XCTAssertTrue(marked.allSatisfy { $0.method == .bulk })
        XCTAssertTrue(marked.allSatisfy { $0.markedAt == timestamp })
        XCTAssertTrue(marked.allSatisfy { $0.status == .present })
    }

    func testIndividualChangeConfirmsOnlySelectedStudent() throws {
        let block = try XCTUnwrap(makeNewBlock())
        let changed = AttendanceRules.mark(
            block.attendance[1],
            status: .absent,
            method: .manual,
            markedAt: "2026-07-18T12:01:00Z"
        )

        XCTAssertEqual(changed.status, .absent)
        XCTAssertEqual(changed.confirmed, true)
        XCTAssertEqual(changed.method, .manual)
        XCTAssertEqual(block.attendance[0].confirmed, false)
    }

    func testCopiedPreviousBlockReturnsToPendingWithoutOldTimestamp() throws {
        let block = try XCTUnwrap(makeNewBlock())
        let confirmed = block.attendance.map {
            AttendanceRules.mark($0, status: .late, method: .manual, markedAt: "old")
        }
        let copied = AttendanceRules.copyForConfirmation(confirmed)

        XCTAssertTrue(copied.allSatisfy { $0.status == .late })
        XCTAssertTrue(copied.allSatisfy { $0.confirmed == false })
        XCTAssertTrue(copied.allSatisfy { $0.method == .copied })
        XCTAssertTrue(copied.allSatisfy { $0.markedAt == nil })
    }

    func testSigningIsBlockedWhileStudentsRemainPending() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.objective = "Objetivo completo"
        block.activity = "Actividad completa"

        XCTAssertFalse(AttendanceRules.canSign(block))
        XCTAssertThrowsError(try AttendanceRules.sign(block, uid: "docente")) { error in
            XCTAssertEqual(error as? AttendanceRulesError, .incompleteBlock)
        }
    }

    func testValidSigningPreservesAttendanceAndAddsTraceability() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.objective = "Objetivo completo"
        block.activity = "Actividad completa"
        block.attendance = AttendanceRules.confirmAll(block.attendance, markedAt: "mark")

        let signed = try AttendanceRules.sign(
            block,
            uid: "uid_docente",
            timestamp: "2026-07-18T13:00:00Z"
        )

        XCTAssertTrue(signed.isSigned)
        XCTAssertEqual(signed.signedAt, "2026-07-18T13:00:00Z")
        XCTAssertEqual(signed.signedByUID, "uid_docente")
        XCTAssertEqual(signed.attendance, block.attendance)
    }

    func testReopeningRequiresReasonAndPreservesPreviousSignature() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.objective = "Objetivo"
        block.activity = "Actividad"
        block.attendance = AttendanceRules.confirmAll(block.attendance)
        let signed = try AttendanceRules.sign(
            block,
            uid: "firma_uid",
            timestamp: "2026-07-18T13:00:00Z"
        )

        XCTAssertThrowsError(try AttendanceRules.reopen(signed, reason: "no", uid: "editor"))

        let reopened = try AttendanceRules.reopen(
            signed,
            reason: "Corregir atraso informado",
            uid: "editor_uid",
            timestamp: "2026-07-18T14:00:00Z"
        )
        XCTAssertFalse(reopened.isSigned)
        XCTAssertEqual(reopened.signedAt, signed.signedAt)
        XCTAssertEqual(reopened.signedByUID, signed.signedByUID)
        XCTAssertEqual(reopened.reopenedAt, "2026-07-18T14:00:00Z")
        XCTAssertEqual(reopened.reopenedByUID, "editor_uid")
        XCTAssertEqual(reopened.reopeningReason, "Corregir atraso informado")
    }

    func testEditableLegacyAttendanceKeepsStateButRequiresReview() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.attendance[0].status = .absent
        block.attendance[0].confirmed = nil
        let current = roster
        let reconciled = AttendanceRules.reconcileAttendance(
            saved: block.attendance,
            currentStudents: current
        )

        XCTAssertEqual(reconciled[0].status, .absent)
        XCTAssertFalse(AttendanceRules.isConfirmed(reconciled[0], blockSigned: false))
    }

    func testSignedLegacyAttendanceWithoutConfirmedIsHistoricalConfirmation() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.isSigned = true
        block.attendance[0].status = .absent
        block.attendance[0].confirmed = nil

        XCTAssertTrue(AttendanceRules.isConfirmed(block.attendance[0], blockSigned: true))
        XCTAssertEqual(AttendanceRules.summary(for: block).absent, 1)
    }

    func testEmptyRosterDoesNotEraseSavedAttendance() throws {
        let block = try XCTUnwrap(makeNewBlock())
        let reconciled = AttendanceRules.reconcileAttendance(
            saved: block.attendance,
            currentStudents: []
        )
        XCTAssertEqual(reconciled, block.attendance)
    }

    func testCumulativePercentageExcludesPendingAndOnlyAbsenceSubtracts() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.attendance = [
            confirmedStudent(id: "1", name: "Antonia", status: .present),
            confirmedStudent(id: "1", name: "Antonia", status: .late),
            confirmedStudent(id: "1", name: "Antonia", status: .withdrawn),
            confirmedStudent(id: "1", name: "Antonia", status: .absent),
            StudentAttendance(
                id: "1",
                name: "Antonia",
                status: .absent,
                confirmed: false,
                method: nil,
                markedAt: nil
            )
        ]
        let book = AttendanceBook(subject: "Música", course: "5° Básico A", dateKey: "2026-07-18", blocks: [block])
        let aggregate = try XCTUnwrap(AttendanceRules.aggregate([book]).first)

        XCTAssertEqual(aggregate.total, 4)
        XCTAssertEqual(aggregate.percentage, 75.0)
    }

    func testDocumentPathsMatchPrincipalAndSecondaryV2Contract() throws {
        let principal = try AttendanceDocumentPath.path(
            uid: "uid_123",
            scope: AttendanceDataScope(schoolID: "principal", yearID: "2026"),
            subject: "Música",
            course: "5° Básico A",
            dateKey: "2026-07-18"
        )
        let secondary = try AttendanceDocumentPath.path(
            uid: "uid_123",
            scope: AttendanceDataScope(schoolID: "colegio_sur", yearID: "2026"),
            subject: "Música",
            course: "5° Básico A",
            dateKey: "2026-07-18"
        )

        XCTAssertEqual(
            principal,
            "users/uid_123/libro_clases/libro_musica_5_basico_a_2026-07-18"
        )
        XCTAssertEqual(
            secondary,
            "users/uid_123/colegios/colegio_sur/libro_clases/libro_musica_5_basico_a_2026-07-18"
        )
    }

    func testValidQRMarksPendingStudentPresentAndConfirmed() throws {
        let block = try XCTUnwrap(makeNewBlock())
        let result = AttendanceRules.applyQR(
            to: block,
            studentID: "2",
            markedAt: "2026-07-18T15:00:00Z"
        )

        guard case .applied(let updated, let studentName) = result else {
            return XCTFail("El QR válido debía aplicarse")
        }
        let student = try XCTUnwrap(updated.attendance.first { $0.id == "2" })
        XCTAssertEqual(studentName, "Benjamín")
        XCTAssertEqual(student.status, .present)
        XCTAssertEqual(student.confirmed, true)
        XCTAssertEqual(student.method, .qr)
        XCTAssertEqual(student.markedAt, "2026-07-18T15:00:00Z")
    }

    func testQRDuplicatePresentDoesNotRewriteStudent() throws {
        var block = try XCTUnwrap(makeNewBlock())
        block.attendance[0] = AttendanceRules.mark(
            block.attendance[0],
            status: .present,
            method: .manual,
            markedAt: "original"
        )

        let result = AttendanceRules.applyQR(to: block, studentID: "1", markedAt: "new")
        XCTAssertEqual(result, .duplicate(studentName: "Antonia"))
        XCTAssertEqual(block.attendance[0].method, .manual)
        XCTAssertEqual(block.attendance[0].markedAt, "original")
    }

    func testQRConfirmedExceptionsRequireTeacherAuthorization() throws {
        for status in [AttendanceStatus.absent, .late, .withdrawn] {
            var block = try XCTUnwrap(makeNewBlock())
            block.attendance[0] = AttendanceRules.mark(
                block.attendance[0],
                status: status,
                method: .manual,
                markedAt: "original"
            )

            XCTAssertEqual(
                AttendanceRules.applyQR(to: block, studentID: "1"),
                .requiresConfirmation(
                    studentID: "1",
                    studentName: "Antonia",
                    previousStatus: status
                )
            )

            let confirmed = AttendanceRules.applyQR(
                to: block,
                studentID: "1",
                allowingConfirmedException: true,
                markedAt: "qr"
            )
            guard case .applied(let updated, _) = confirmed else {
                return XCTFail("La autorización docente debía aplicar el cambio")
            }
            XCTAssertEqual(updated.attendance[0].status, .present)
            XCTAssertEqual(updated.attendance[0].method, .qr)
            XCTAssertEqual(updated.attendance[0].markedAt, "qr")
        }
    }

    func testQRDoesNotChangeSignedBlockOrMissingStudent() throws {
        var signed = try XCTUnwrap(makeNewBlock())
        signed.isSigned = true
        XCTAssertEqual(AttendanceRules.applyQR(to: signed, studentID: "1"), .signedBlock)

        let editable = try XCTUnwrap(makeNewBlock())
        XCTAssertEqual(AttendanceRules.applyQR(to: editable, studentID: "missing"), .studentNotFound)
    }

    func testAttendanceRepositoryRoundTripsQRMethod() throws {
        let original = StudentAttendance(
            id: "est_1",
            name: "Antonia",
            status: .present,
            confirmed: true,
            method: .qr,
            markedAt: "2026-07-18T15:00:00Z"
        )
        let encoded = AttendanceRepository.attendanceDictionary(original)
        let decoded = try XCTUnwrap(AttendanceRepository.parseAttendance(encoded))

        XCTAssertEqual(encoded["metodo"] as? String, "qr")
        XCTAssertEqual(decoded, original)
    }

    func testScannerCapabilityReportsDeniedAndUnsupported() {
        XCTAssertEqual(
            AttendanceQRScannerCapability.resolve(
                isSupported: true,
                isAvailable: false,
                authorization: .denied
            ),
            .denied
        )
        XCTAssertEqual(
            AttendanceQRScannerCapability.resolve(
                isSupported: false,
                isAvailable: false,
                authorization: .ready
            ),
            .unsupported
        )
    }

    private var roster: [AttendanceRosterStudent] {
        [
            AttendanceRosterStudent(id: "1", name: "Antonia"),
            AttendanceRosterStudent(id: "2", name: "Benjamín"),
            AttendanceRosterStudent(id: "3", name: "Catalina")
        ]
    }

    private func makeNewBlock() -> AttendanceBlock? {
        AttendanceRules.newBlocks(
            course: "5° Básico A",
            dateKey: "2026-07-17",
            schedule: [
                AttendanceScheduleBlock(
                    id: "bloque_1",
                    course: "5° Básico A",
                    weekday: "Viernes",
                    startTime: "08:30",
                    endTime: "09:15",
                    isFree: false
                )
            ],
            students: roster
        ).first
    }

    private func confirmedStudent(id: String, name: String, status: AttendanceStatus) -> StudentAttendance {
        StudentAttendance(
            id: id,
            name: name,
            status: status,
            confirmed: true,
            method: .manual,
            markedAt: "2026-07-18T12:00:00Z"
        )
    }
}

@MainActor
final class AttendanceQRCoordinatorTests: XCTestCase {
    func testResolverFailuresNeverModifyAttendance() async throws {
        let failures: [AttendanceQRFailure] = [
            .invalidQRCode,
            .revoked,
            .stale,
            .scopeMismatch,
            .offline,
            .timeout
        ]

        for failure in failures {
            let model = AttendanceViewModel.preview(isSigned: false, allConfirmed: false)
            let original = model.activeBlock
            let coordinator = AttendanceQRCoordinator(
                attendanceModel: model,
                resolver: StubQRResolver(result: .failure(failure)),
                scannerProvider: StubQRScannerProvider(availability: .ready)
            )

            await coordinator.prepare()
            await coordinator.process(payload: "opaque-test-payload")

            XCTAssertEqual(model.activeBlock, original, "Falló para \(failure)")
            XCTAssertEqual(coordinator.state, .failure(failure))
        }
    }

    func testValidResolvedStudentAppliesThroughCoordinator() async throws {
        let model = AttendanceViewModel.preview(isSigned: false, allConfirmed: false)
        let response = AttendanceQRResolveResponse(
            studentId: "est_4",
            studentName: "Diego Contreras",
            credentialId: "credential-4"
        )
        let coordinator = AttendanceQRCoordinator(
            attendanceModel: model,
            resolver: StubQRResolver(result: .success(response)),
            scannerProvider: StubQRScannerProvider(availability: .ready)
        )

        await coordinator.prepare()
        await coordinator.process(payload: "opaque-test-payload")

        let student = try XCTUnwrap(model.activeBlock?.attendance.first { $0.id == "est_4" })
        XCTAssertEqual(student.status, .present)
        XCTAssertEqual(student.confirmed, true)
        XCTAssertEqual(student.method, .qr)
        XCTAssertEqual(coordinator.state, .success(studentName: "Diego Contreras"))
    }

    func testScannerPausePreventsConcurrentResolution() async throws {
        let model = AttendanceViewModel.preview(isSigned: false, allConfirmed: false)
        let resolver = CountingQRResolver()
        let coordinator = AttendanceQRCoordinator(
            attendanceModel: model,
            resolver: resolver,
            scannerProvider: StubQRScannerProvider(availability: .ready)
        )

        await coordinator.prepare()
        async let first: Void = coordinator.process(payload: "first-opaque-payload")
        async let second: Void = coordinator.process(payload: "second-opaque-payload")
        _ = await (first, second)

        let callCount = await resolver.callCount()
        XCTAssertEqual(callCount, 1)
    }
}

private struct StubQRResolver: AttendanceQRResolving {
    let result: Result<AttendanceQRResolveResponse, AttendanceQRFailure>

    func resolve(
        payload: String,
        scope: AttendanceDataScope,
        course: String
    ) async throws -> AttendanceQRResolveResponse {
        try result.get()
    }
}

private actor CountingQRResolver: AttendanceQRResolving {
    private var calls = 0

    func resolve(
        payload: String,
        scope: AttendanceDataScope,
        course: String
    ) async throws -> AttendanceQRResolveResponse {
        calls += 1
        try await Task.sleep(for: .milliseconds(150))
        return AttendanceQRResolveResponse(
            studentId: "est_4",
            studentName: "Diego Contreras",
            credentialId: "credential-4"
        )
    }

    func callCount() -> Int { calls }
}

private struct StubQRScannerProvider: AttendanceQRScannerProviding {
    let availability: AttendanceQRScannerAvailability

    func currentAvailability() -> AttendanceQRScannerAvailability { availability }
    func requestPermission() async -> AttendanceQRScannerAvailability { availability }

    func scannerView(
        isPaused: Bool,
        onPayload: @escaping (String) -> Void,
        onUnavailable: @escaping (AttendanceQRScannerAvailability) -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
