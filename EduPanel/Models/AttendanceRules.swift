import Foundation

enum AttendanceRulesError: LocalizedError, Equatable {
    case incompleteBlock
    case missingReopeningReason

    var errorDescription: String? {
        switch self {
        case .incompleteBlock:
            return "Completa objetivo, actividad y asistencia antes de firmar el bloque."
        case .missingReopeningReason:
            return "Indica un motivo breve para reabrir el bloque firmado."
        }
    }
}

enum AttendanceRules {
    static func newBlocks(
        course: String,
        courseID: String? = nil,
        subjectID: String? = nil,
        dateKey: String,
        schedule: [AttendanceScheduleBlock],
        students: [AttendanceRosterStudent]
    ) -> [AttendanceBlock] {
        let weekday = weekdayName(for: dateKey)
        let scheduled = schedule
            .filter { item in
                let courseMatches = courseID.flatMap { id in item.courseID.map { $0 == id } } ?? (item.course == course)
                let subjectMatches = subjectID.flatMap { id in item.subjectID.map { $0 == id } } ?? true
                return courseMatches && subjectMatches && item.weekday == weekday && !item.isFree
            }
            .sorted { lhs, rhs in
                lhs.startTime == rhs.startTime ? lhs.id < rhs.id : lhs.startTime < rhs.startTime
            }
        let source = scheduled.isEmpty
            ? [AttendanceScheduleBlock(
                id: "\(course)-\(dateKey)-1",
                course: course,
                weekday: weekday,
                startTime: "08:30",
                endTime: "09:15",
                isFree: false
            )]
            : scheduled

        return source.enumerated().map { index, item in
            AttendanceBlock(
                id: item.id,
                label: "Bloque \(index + 1)",
                startTime: item.startTime,
                endTime: item.endTime,
                objective: "",
                activity: "",
                isSigned: false,
                attendance: students.map {
                    StudentAttendance(
                        id: $0.id,
                        name: $0.name,
                        status: .present,
                        confirmed: false,
                        method: nil,
                        markedAt: nil
                    )
                },
                attendanceSchemaVersion: 2,
                signedAt: nil,
                signedByUID: nil,
                reopenedAt: nil,
                reopenedByUID: nil,
                reopeningReason: nil
            )
        }
    }

    static func isConfirmed(_ attendance: StudentAttendance, blockSigned: Bool = false) -> Bool {
        attendance.confirmed == true || (blockSigned && attendance.confirmed != false)
    }

    static func mark(
        _ attendance: StudentAttendance,
        status: AttendanceStatus,
        method: AttendanceMethod,
        markedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> StudentAttendance {
        var updated = attendance
        updated.status = status
        updated.confirmed = true
        updated.method = method
        updated.markedAt = markedAt
        return updated
    }

    static func confirmAll(
        _ attendance: [StudentAttendance],
        as status: AttendanceStatus = .present,
        markedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> [StudentAttendance] {
        attendance.map { mark($0, status: status, method: .bulk, markedAt: markedAt) }
    }

    static func copyForConfirmation(_ attendance: [StudentAttendance]) -> [StudentAttendance] {
        attendance.map { item in
            var copy = item
            copy.confirmed = false
            copy.method = .copied
            copy.markedAt = nil
            return copy
        }
    }

    static func applyQR(
        to block: AttendanceBlock,
        studentID: String,
        allowingConfirmedException: Bool = false,
        markedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> AttendanceQRApplicationResult {
        guard !block.isSigned else { return .signedBlock }
        guard let index = block.attendance.firstIndex(where: { $0.id == studentID }) else {
            return .studentNotFound
        }

        let student = block.attendance[index]
        if isConfirmed(student) {
            if student.status == .present {
                return .duplicate(studentName: student.name)
            }
            if !allowingConfirmedException {
                return .requiresConfirmation(
                    studentID: student.id,
                    studentName: student.name,
                    previousStatus: student.status
                )
            }
        }

        var updated = block
        updated.attendance[index] = mark(
            student,
            status: .present,
            method: .qr,
            markedAt: markedAt
        )
        return .applied(block: updated, studentName: student.name)
    }

    static func reconcileAttendance(
        saved: [StudentAttendance],
        currentStudents: [AttendanceRosterStudent]
    ) -> [StudentAttendance] {
        guard !currentStudents.isEmpty || saved.isEmpty else { return saved }
        let savedByID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return currentStudents.map { student in
            guard var stored = savedByID[student.id] else {
                return StudentAttendance(
                    id: student.id,
                    name: student.name,
                    status: .present,
                    confirmed: false,
                    method: nil,
                    markedAt: nil
                )
            }
            stored.name = student.name
            if !stored.status.isValid {
                stored.confirmed = false
            }
            return stored
        }
    }

    static func reconcileBlocks(
        saved: [AttendanceBlock]?,
        course: String,
        courseID: String? = nil,
        subjectID: String? = nil,
        dateKey: String,
        schedule: [AttendanceScheduleBlock],
        students: [AttendanceRosterStudent]
    ) -> [AttendanceBlock] {
        let planned = newBlocks(course: course, courseID: courseID, subjectID: subjectID, dateKey: dateKey, schedule: schedule, students: students)
        guard let saved, !saved.isEmpty else { return planned }

        let plannedByID = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })
        let savedIDs = Set(saved.map(\.id))
        var result = saved.enumerated().map { index, stored -> AttendanceBlock in
            guard !stored.isSigned else { return stored }
            let matching = plannedByID[stored.id]
            var updated = stored
            updated.label = matching?.label ?? (stored.label.isEmpty ? "Bloque \(index + 1)" : stored.label)
            updated.startTime = matching?.startTime ?? stored.startTime
            updated.endTime = matching?.endTime ?? stored.endTime
            updated.attendanceSchemaVersion = 2
            updated.attendance = reconcileAttendance(saved: stored.attendance, currentStudents: students)
            return updated
        }
        result.append(contentsOf: planned.filter { !savedIDs.contains($0.id) })
        return result
    }

    static func canSign(_ block: AttendanceBlock) -> Bool {
        !block.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !block.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !block.attendance.isEmpty
            && block.attendance.allSatisfy(\.status.isValid)
            && block.attendance.allSatisfy { isConfirmed($0, blockSigned: block.isSigned) }
    }

    static func sign(
        _ block: AttendanceBlock,
        uid: String?,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> AttendanceBlock {
        guard canSign(block) else { throw AttendanceRulesError.incompleteBlock }
        var signed = block
        signed.isSigned = true
        signed.signedAt = timestamp
        if let uid, !uid.isEmpty { signed.signedByUID = uid }
        return signed
    }

    static func reopen(
        _ block: AttendanceBlock,
        reason: String,
        uid: String?,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> AttendanceBlock {
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanReason.count >= 5 else { throw AttendanceRulesError.missingReopeningReason }
        guard block.isSigned else { return block }

        var reopened = block
        reopened.isSigned = false
        reopened.reopenedAt = timestamp
        reopened.reopeningReason = cleanReason
        if let uid, !uid.isEmpty { reopened.reopenedByUID = uid }
        return reopened
    }

    static func summary(for block: AttendanceBlock) -> AttendanceSummary {
        block.attendance.reduce(into: AttendanceSummary()) { result, item in
            guard item.status.isValid else {
                result.invalid += 1
                result.pending += 1
                return
            }
            guard isConfirmed(item, blockSigned: block.isSigned) else {
                result.pending += 1
                return
            }

            result.confirmedTotal += 1
            switch item.status {
            case .present: result.present += 1
            case .absent: result.absent += 1
            case .late: result.late += 1
            case .withdrawn: result.withdrawn += 1
            case .invalid: break
            }
        }
    }

    static func aggregate(_ books: [AttendanceBook]) -> [StudentAttendanceAggregate] {
        var result: [String: StudentAttendanceAggregate] = [:]
        for book in books {
            for block in book.blocks {
                for attendance in block.attendance where isConfirmed(attendance, blockSigned: block.isSigned) {
                    guard attendance.status.isValid else { continue }
                    var aggregate = result[attendance.id]
                        ?? StudentAttendanceAggregate(id: attendance.id, name: attendance.name)
                    aggregate.name = attendance.name
                    switch attendance.status {
                    case .present: aggregate.present += 1
                    case .absent: aggregate.absent += 1
                    case .late: aggregate.late += 1
                    case .withdrawn: aggregate.withdrawn += 1
                    case .invalid: break
                    }
                    result[attendance.id] = aggregate
                }
            }
        }
        return result.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func weekdayName(for dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "es_CL")
        formatter.timeZone = TimeZone(identifier: "America/Santiago")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: "\(dateKey) 12:00") else { return "" }
        formatter.dateFormat = "EEEE"
        let name = formatter.string(from: date)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
