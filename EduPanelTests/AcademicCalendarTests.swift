import XCTest
@testable import EduPanel

final class AcademicCalendarTests: XCTestCase {
    func testCourseDecodesAliasesAndLegacyLibreAsWorkshop() throws {
        let course = try XCTUnwrap(AcademicCourse.from(id: "legacy-workshop", dictionary: [
            "courseId": "legacy-workshop",
            "dataKey": "robotica_legacy",
            "aliasKeys": ["robotica", "robotica", "", "robotica_legacy"],
            "tipo": "libre",
            "nombre": "Robótica",
            "asignaturas": [],
            "color": "#8B5CF6",
            "estado": "active",
        ]))

        XCTAssertEqual(course.kind, .taller)
        XCTAssertEqual(course.workshopName, "Robótica")
        XCTAssertEqual(course.aliasKeys, ["robotica"])
        XCTAssertEqual(course.firestoreDictionary["tipo"] as? String, "taller")
        XCTAssertEqual(course.firestoreDictionary["aliasKeys"] as? [String], ["robotica"])
    }

    func testExactCurrentNameWinsOverAnotherCoursesAliasRegardlessOfCatalogOrder() {
        let aliasOwner = course(
            id: "course-old",
            name: "Taller anterior",
            dataKey: "taller_anterior",
            aliases: ["robotica"]
        )
        let exactCourse = course(
            id: "course-current",
            name: "Robótica",
            dataKey: "robotica_course_current"
        )
        let snapshot = dashboardSnapshot(courses: [aliasOwner, exactCourse])

        XCTAssertEqual(snapshot.course(id: nil, named: "Robótica")?.courseID, "course-current")
        XCTAssertEqual(
            AcademicContract.resolveCourse(in: [aliasOwner, exactCourse], named: "Robótica").course?.courseID,
            "course-current"
        )
    }

    func testAmbiguousAliasDoesNotResolveSilently() {
        let first = course(
            id: "course-a",
            name: "Coro inicial",
            dataKey: "coro_a",
            aliases: ["coro_historico"]
        )
        let second = course(
            id: "course-b",
            name: "Coro vespertino",
            dataKey: "coro_b",
            aliases: ["coro histórico"]
        )

        XCTAssertEqual(
            AcademicContract.resolveCourse(in: [second, first], named: "Coro histórico"),
            .ambiguous(courseIDs: ["course-a", "course-b"])
        )
        XCTAssertNil(dashboardSnapshot(courses: [second, first]).course(id: nil, named: "Coro histórico"))
    }

    func testRosterCandidatesKeepCanonicalOrderAndDeduplicateAliases() throws {
        let value = course(
            id: "course-new",
            name: "Robótica Nueva",
            dataKey: "robotica_actual",
            aliases: ["robotica_actual", "robotica_anterior", "robotica_anterior"]
        )

        let candidates = DashboardRepository.rosterDocumentCandidates(for: value)

        XCTAssertEqual(Array(candidates.prefix(2)), ["robotica_actual", "course-new"])
        XCTAssertEqual(candidates.count, Set(candidates).count)
        let canonicalIndex = try XCTUnwrap(candidates.firstIndex(of: "robotica_actual"))
        let aliasIndex = try XCTUnwrap(candidates.firstIndex(of: "robotica_anterior"))
        XCTAssertLessThan(canonicalIndex, aliasIndex)
    }

    func testLegacyRosterCandidatesKeepCurrentNormalizerBeforeHistoricalKey() {
        XCTAssertEqual(
            DashboardRepository.legacyRosterDocumentCandidates(for: "8° Básico A"),
            ["8_basico_a", "8__b_sico_a"]
        )
        XCTAssertEqual(
            DashboardRepository.legacyRosterDocumentCandidates(for: "Coro"),
            ["coro"]
        )
    }

    func testEmptyAliasesAreWrittenSoFirestoreMergeCanClearThem() {
        let value = course(
            id: "course-no-alias",
            name: "Taller vigente",
            dataKey: "taller_vigente",
            aliases: []
        )

        XCTAssertEqual(value.firestoreDictionary["aliasKeys"] as? [String], [])
    }

    func testSchoolHolidaySuppressesRecurringScheduleWithoutCreatingClasses() throws {
        let date = try date("2026-09-18T15:00:00Z")
        let period = publishedPeriod(blocks: [block(id: "regular", courseID: "course-a")])
        let holiday = AcademicCalendarEvent(
            id: "independencia",
            title: "Fiestas Patrias",
            kind: .holiday,
            startDateKey: "2026-09-18",
            endDateKey: "2026-09-18"
        )

        let resolved = AcademicCalendarResolver.effectiveSchedule(
            periods: [period],
            legacy: [],
            events: [holiday],
            for: date
        )

        XCTAssertTrue(resolved.isEmpty)
    }

    func testCourseSuspensionDoesNotRemoveOtherAcademicSpaces() throws {
        let date = try date("2026-08-17T15:00:00Z")
        let period = publishedPeriod(blocks: [
            block(id: "course-a", courseID: "course-a", start: "08:00"),
            block(id: "workshop-b", courseID: "workshop-b", start: "10:00"),
        ])
        let suspension = AcademicCalendarEvent(
            id: "suspension-a",
            title: "Suspensión del curso",
            kind: .suspension,
            startDateKey: "2026-08-17",
            endDateKey: "2026-08-17",
            courseID: "course-a"
        )

        let resolved = AcademicCalendarResolver.effectiveSchedule(
            periods: [period],
            legacy: [],
            events: [suspension],
            for: date
        )

        XCTAssertEqual(resolved.map(\.id), ["workshop-b"])
    }

    func testScheduleExceptionReplacesOnlyItsAcademicSpace() throws {
        let date = try date("2026-08-17T15:00:00Z")
        let period = publishedPeriod(blocks: [
            block(id: "course-a-regular", courseID: "course-a", start: "08:00"),
            block(id: "course-b-regular", courseID: "course-b", start: "09:00"),
        ])
        let replacement = block(id: "course-a-exception", courseID: "course-a", start: "12:00")
        let exception = AcademicCalendarEvent(
            id: "exception-a",
            title: "Cambio de jornada",
            kind: .scheduleException,
            startDateKey: "2026-08-17",
            endDateKey: "2026-08-17",
            courseID: "course-a",
            replacementBlocks: [replacement]
        )

        let resolved = AcademicCalendarResolver.effectiveSchedule(
            periods: [period],
            legacy: [],
            events: [exception],
            for: date
        )

        XCTAssertEqual(Set(resolved.map(\.id)), ["course-a-exception", "course-b-regular"])
        XCTAssertFalse(resolved.contains { $0.id == "course-a-regular" })
    }

    private func publishedPeriod(blocks: [ClaseHorario]) -> SchedulePeriod {
        SchedulePeriod(
            periodID: "year-2026",
            name: "Año académico 2026",
            startDateKey: "2026-03-01",
            endDateKey: "2026-12-31",
            status: .published,
            timeZone: AcademicContract.timeZoneIdentifier,
            blocks: blocks
        )
    }

    private func block(
        id: String,
        courseID: String,
        start: String = "08:00"
    ) -> ClaseHorario {
        ClaseHorario(
            id: id,
            resumen: courseID,
            dia: "Lunes",
            horaInicio: start,
            horaFin: start == "12:00" ? "12:45" : "10:45",
            colorHex: "#EC4899",
            tipo: .clase,
            asignatura: "Música",
            courseID: courseID
        )
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func course(
        id: String,
        name: String,
        dataKey: String,
        aliases: [String] = []
    ) -> AcademicCourse {
        AcademicCourse(
            courseID: id,
            dataKey: dataKey,
            aliasKeys: aliases,
            kind: .taller,
            name: name,
            level: nil,
            section: nil,
            workshopName: name,
            subjects: [],
            colorHex: "#8B5CF6",
            status: .active,
            archivedAt: nil,
            deleteEligibleAt: nil
        )
    }

    private func dashboardSnapshot(courses: [AcademicCourse]) -> DashboardSnapshot {
        DashboardSnapshot(
            date: Date(),
            profile: .empty,
            school: .empty,
            preferences: .empty,
            horario: [],
            classState: [:],
            studentCounts: [:],
            studentsByCourse: [:],
            nivelMapping: [:],
            cursoTipos: [:],
            courseCatalog: courses
        )
    }
}
