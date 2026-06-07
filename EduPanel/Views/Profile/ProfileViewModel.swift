import Observation
import SwiftUI

enum ProfileSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case error

    var title: String {
        switch self {
        case .idle: return ""
        case .saving: return "Guardando"
        case .saved: return "Guardado"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .saving: return .blue
        case .saved: return .green
        case .error: return .red
        }
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    var snapshot: DashboardSnapshot?
    var draftProfile = PerfilUsuario.empty
    var draftSchool = InfoColegio.empty
    var draftPreferences = PreferenciasUsuario.empty
    var draftNivelMapping: [String: String] = [:]
    var draftCursoTipos: [String: TipoCurricular] = [:]
    var isLoading = false
    var errorMessage: String?
    var saveProfileStatus: ProfileSaveStatus = .idle
    var saveSchoolStatus: ProfileSaveStatus = .idle
    var savePreferencesStatus: ProfileSaveStatus = .idle
    var saveMappingStatus: ProfileSaveStatus = .idle

    let repository: DashboardRepository

    init(repository: DashboardRepository) {
        self.repository = repository
    }

    func load() async {
        guard snapshot == nil else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            snapshot = next
            draftProfile = next.profile
            draftSchool = next.school
            draftPreferences = next.preferences
            draftNivelMapping = next.nivelMapping
            draftCursoTipos = next.cursoTipos
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveProfile() async {
        saveProfileStatus = .saving
        do {
            try await repository.saveProfile(draftProfile)
            if var snapshot {
                snapshot.profile = draftProfile
                self.snapshot = snapshot
            }
            saveProfileStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveProfileStatus = .error
        }
    }

    func saveSchool() async {
        saveSchoolStatus = .saving
        do {
            try await repository.saveSchool(draftSchool)
            if var snapshot {
                snapshot.school = draftSchool
                self.snapshot = snapshot
            }
            saveSchoolStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveSchoolStatus = .error
        }
    }

    func savePreferences() async {
        savePreferencesStatus = .saving
        do {
            try await repository.savePreferences(draftPreferences)
            if var snapshot {
                snapshot.preferences = draftPreferences
                self.snapshot = snapshot
            }
            savePreferencesStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            savePreferencesStatus = .error
        }
    }

    func saveLevelMapping() async {
        saveMappingStatus = .saving
        do {
            try await repository.saveLevelMapping(draftNivelMapping, cursoTipos: draftCursoTipos)
            if var snapshot {
                snapshot.nivelMapping = draftNivelMapping
                snapshot.cursoTipos = draftCursoTipos
                self.snapshot = snapshot
            }
            saveMappingStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveMappingStatus = .error
        }
    }

    func toggleConnection(type: String, isConnected: Bool) async {
        var calConn = draftPreferences.googleCalendarConnected
        var drvConn = draftPreferences.googleDriveConnected

        if type == "calendar" {
            calConn = isConnected
        } else if type == "drive" {
            drvConn = isConnected
        }

        do {
            try await repository.saveConnections(googleCalendarConnected: calConn, googleDriveConnected: drvConn)
            draftPreferences.googleCalendarConnected = calConn
            draftPreferences.googleDriveConnected = drvConn
            if var snapshot {
                snapshot.preferences = draftPreferences
                self.snapshot = snapshot
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension ProfileViewModel {
    func courseSummaries(for snapshot: DashboardSnapshot) -> [ProfileCourseSummary] {
        snapshot.courses.map { course in
            let blocks = snapshot.academicClasses.filter { $0.resumen == course }
            let minutes = blocks.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }
            let students = snapshot.studentsByCourse[course] ?? []
            let subjects = Array(Set(blocks.compactMap(\.asignatura))).sorted()
            let type = snapshot.cursoTipos[course] ?? .oficial
            return ProfileCourseSummary(
                name: course,
                colorHex: blocks.first?.colorHex ?? "#EC4899",
                blocks: blocks.count,
                minutes: minutes,
                students: students.count,
                pie: students.filter(\.pie).count,
                level: snapshot.nivelMapping[course],
                type: type,
                subjects: subjects,
                weeklyBlocks: blocks.sorted {
                    let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                    let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                    if leftDay != rightDay { return leftDay < rightDay }
                    return $0.horaInicio < $1.horaInicio
                },
                studentsList: students.sorted { $0.orden < $1.orden }
            )
        }
    }
}
