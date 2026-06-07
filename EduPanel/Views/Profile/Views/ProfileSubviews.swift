import SwiftUI
import UIKit

struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let hint: String?
    let content: Content

    init(title: String, icon: String, hint: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
                Text(title)
                    .font(.subheadline.weight(.black))
                if let hint {
                    Text(hint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
    }
}

struct ProfileKPI: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var hint: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.black))
                if let hint {
                    Text(hint)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProfilePill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.pink)
            .background(.pink.opacity(0.12), in: Capsule())
    }
}

struct AsyncUserAvatar: View {
    let user: AuthenticatedUser

    var body: some View {
        Group {
            if let url = user.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String((user.displayName ?? "P").prefix(1)).uppercased())
                .font(.title.weight(.black))
                .foregroundStyle(.white)
        }
    }
}

struct ProfileErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProfileSaveBadge: View {
    let status: ProfileSaveStatus

    var body: some View {
        if status != .idle {
            Label(status.title, systemImage: status == .saving ? "hourglass" : status == .saved ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(status.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProfileTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .profileFieldLabel()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.footnote.weight(.semibold))
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct SchoolLogoView: View {
    let base64: String?

    var body: some View {
        Group {
            if let image = decodedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: "building.2.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
        }
        .frame(width: 62, height: 62)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var decodedImage: UIImage? {
        guard let base64, !base64.isEmpty else { return nil }
        let raw = base64.components(separatedBy: ",").last ?? base64
        guard let data = Data(base64Encoded: raw) else { return nil }
        return UIImage(data: data)
    }
}

struct ConnectionStatusCard: View {
    let title: String
    let message: String
    let isConnected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.footnote.weight(.black))
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(isConnected ? "Conectado" : "Desconectado")
                .font(.caption2.weight(.black))
                .foregroundStyle(isConnected ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isConnected ? Color.green.opacity(0.14) : Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}

struct ProfileEmptyAction: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.black))
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Label(buttonTitle, systemImage: "arrow.right")
                    .font(.footnote.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProfileShortcut: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ProfileBannerPreset: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
}

let profileBannerPresets: [ProfileBannerPreset] = [
    ProfileBannerPreset(id: "rosa", title: "Rosa", colors: [.pink, .red]),
    ProfileBannerPreset(id: "oceano", title: "Océano", colors: [.cyan, .blue]),
    ProfileBannerPreset(id: "atardecer", title: "Atardecer", colors: [.orange, .pink, .purple]),
    ProfileBannerPreset(id: "esmeralda", title: "Esmeralda", colors: [.green, .teal]),
    ProfileBannerPreset(id: "indigo", title: "Indigo", colors: [.indigo, .purple]),
    ProfileBannerPreset(id: "grafito", title: "Grafito", colors: [.gray, .black]),
    ProfileBannerPreset(id: "bosque", title: "Bosque", colors: [.green, .mint]),
    ProfileBannerPreset(id: "lavanda", title: "Lavanda", colors: [.purple, .pink])
]

struct ProfileBannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(profileBannerPresets) { preset in
                        Button {
                            viewModel.draftPreferences.bannerStyle = preset.id
                            Task {
                                await viewModel.savePreferences()
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                HStack {
                                    Text(preset.title)
                                        .font(.footnote.weight(.black))
                                    Spacer()
                                    if viewModel.draftPreferences.bannerStyle == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Fondo del perfil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

enum ProfileFormat {
    static func minutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 h" }
        if minutes % 60 == 0 {
            return "\(minutes / 60) h"
        }
        return String(format: "%.1f h", Double(minutes) / 60.0)
    }
}

extension Text {
    func profileFieldLabel() -> some View {
        self.font(.system(size: 10, weight: .black))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct ProfileCourseSummary: Identifiable {
    var id: String { name }
    let name: String
    let colorHex: String
    let blocks: Int
    let minutes: Int
    let students: Int
    let pie: Int
    let level: String?
    let type: TipoCurricular
    let subjects: [String]
    let weeklyBlocks: [ClaseHorario]
    let studentsList: [EstudiantePerfil]

    var levelText: String {
        if type != .oficial {
            return type.label
        }
        return level ?? "Sin nivel"
    }

    var subjectSchedules: [ProfileSubjectSchedule] {
        let grouped = Dictionary(grouping: weeklyBlocks) { item in
            let subject = item.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return subject.isEmpty ? "Sin asignatura" : subject
        }
        let declaredSubjects = subjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let subjectNames = Set(grouped.keys).union(declaredSubjects)

        return subjectNames.map { subject in
            let blocks = grouped[subject] ?? []
            let sorted = blocks.sorted {
                let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                if leftDay != rightDay { return leftDay < rightDay }
                return $0.horaInicio < $1.horaInicio
            }
            let minutes = sorted.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }
            return ProfileSubjectSchedule(
                subject: subject,
                colorHex: sorted.first?.colorHex ?? colorHex,
                blocks: sorted,
                minutes: minutes
            )
        }
        .sorted {
            if $0.isMissingSubject { return false }
            if $1.isMissingSubject { return true }
            return $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending
        }
    }
}

struct ProfileSubjectSchedule: Identifiable {
    var id: String { subject }
    let subject: String
    let colorHex: String
    let blocks: [ClaseHorario]
    let minutes: Int

    var isMissingSubject: Bool {
        subject == "Sin asignatura"
    }
}

extension Color {
    init(profileHex: String) {
        let clean = profileHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
