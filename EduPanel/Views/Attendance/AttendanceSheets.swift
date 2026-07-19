import SwiftUI
import UIKit

enum AttendanceSheetDestination: String, Identifiable {
    case quickMode
    case signReview
    case reopen
    case date
    case lesson

    var id: String { rawValue }
}

struct AttendanceSheetHost: View {
    let destination: AttendanceSheetDestination
    let model: AttendanceViewModel

    @ViewBuilder
    var body: some View {
        switch destination {
        case .quickMode:
            AttendanceQuickModeSheet(model: model)
        case .signReview:
            AttendanceSignReviewSheet(model: model)
        case .reopen:
            AttendanceReopenSheet(model: model)
        case .date:
            AttendanceDateSheet(model: model)
        case .lesson:
            AttendanceLessonSheet(model: model)
        }
    }
}

private struct AttendanceQuickModeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AttendanceViewModel

    @State private var index = 0

    private var students: [StudentAttendance] { model.activeBlock?.attendance ?? [] }
    private var student: StudentAttendance? {
        students.indices.contains(index) ? students[index] : nil
    }

    init(model: AttendanceViewModel) {
        self.model = model
        let students = model.activeBlock?.attendance ?? []
        let firstPending = students.firstIndex {
            !AttendanceRules.isConfirmed($0, blockSigned: model.activeBlock?.isSigned == true)
        } ?? 0
        _index = State(initialValue: firstPending)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let student {
                    ScrollView {
                        VStack(spacing: 22) {
                            progressHeader
                            studentHeader(student)
                            statusGrid(student)
                            navigationControls
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        "Sin estudiantes",
                        systemImage: "person.3.fill",
                        description: Text("Carga la nómina del curso antes de pasar asistencia.")
                    )
                }
            }
            .background(EPTheme.background)
            .navigationTitle("Modo rápido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Estudiante \(min(index + 1, students.count)) de \(students.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.summary.confirmedTotal)/\(students.count) confirmados")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.summary.confirmedTotal), total: Double(max(1, students.count)))
                .tint(EPTheme.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func studentHeader(_ student: StudentAttendance) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(EPTheme.primary)
            Text(student.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
            Label(
                AttendanceRules.isConfirmed(student) ? student.status.title : "Aún sin confirmar",
                systemImage: AttendanceRules.isConfirmed(student)
                    ? student.status.systemImage
                    : "exclamationmark.circle.fill"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AttendanceRules.isConfirmed(student) ? student.status.tint : EPTheme.statusAmber)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(student.name), \(AttendanceRules.isConfirmed(student) ? student.status.title : "sin confirmar")")
    }

    private func statusGrid(_ student: StudentAttendance) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 12) {
            ForEach(AttendanceStatus.validCases, id: \.self) { status in
                Button {
                    model.mark(studentID: student.id, as: status)
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(student.name), \(status.title), confirmado"
                    )
                    if index < students.count - 1 {
                        withAnimation(EPTheme.spring) { index += 1 }
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: status.systemImage)
                            .font(.title2.bold())
                        Text(status.title)
                            .font(.headline)
                    }
                    .foregroundStyle(status.tint)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(status.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                AttendanceRules.isConfirmed(student) && student.status == status
                                    ? status.tint
                                    : status.tint.opacity(0.25),
                                lineWidth: AttendanceRules.isConfirmed(student) && student.status == status ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Marcar a \(student.name) como \(status.title)")
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(EPTheme.spring) { index = max(0, index - 1) }
            } label: {
                Label("Anterior", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .attendanceSecondaryButtonStyle()
            .disabled(index == 0)

            if index >= students.count - 1 {
                Button {
                    dismiss()
                } label: {
                    Label("Finalizar", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .attendancePrimaryButtonStyle()
            } else {
                Button {
                    withAnimation(EPTheme.spring) { index = min(students.count - 1, index + 1) }
                } label: {
                    Label("Siguiente", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .attendanceSecondaryButtonStyle()
            }
        }
    }
}

private struct AttendanceLessonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AttendanceViewModel

    var body: some View {
        NavigationStack {
            Form {
                if model.activeBlock?.isSigned == true {
                    Section("Objetivo") {
                        Text(model.objective.isEmpty ? "Sin objetivo registrado" : model.objective)
                            .foregroundStyle(model.objective.isEmpty ? .secondary : .primary)
                    }
                    Section("Actividad") {
                        Text(model.activity.isEmpty ? "Sin actividad registrada" : model.activity)
                            .foregroundStyle(model.activity.isEmpty ? .secondary : .primary)
                    }
                } else {
                    Section {
                        TextEditor(text: $model.objective)
                            .frame(minHeight: 110)
                            .accessibilityLabel("Objetivo de la clase")
                    } header: {
                        Text("Objetivo")
                    } footer: {
                        Text("Describe qué se esperaba lograr durante este bloque.")
                    }

                    Section {
                        TextEditor(text: $model.activity)
                            .frame(minHeight: 150)
                            .accessibilityLabel("Actividad realizada")
                    } header: {
                        Text("Actividad")
                    } footer: {
                        Text("Registra brevemente el inicio, desarrollo o cierre realizado.")
                    }
                }
            }
            .navigationTitle(model.activeBlock?.isSigned == true ? "Leccionario" : "Objetivo y actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AttendanceSignReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AttendanceViewModel
    @State private var isSigning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("La firma bloqueará la edición hasta registrar una reapertura justificada.", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    AttendanceSummaryGrid(summary: model.summary)

                    VStack(alignment: .leading, spacing: 12) {
                        reviewText("Objetivo", value: model.activeBlock?.objective ?? "")
                        Divider()
                        reviewText("Actividad", value: model.activeBlock?.activity ?? "")
                        Divider()
                        HStack {
                            Text("Pendientes")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(model.summary.pending)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(model.summary.pending == 0 ? EPTheme.statusGreen : EPTheme.statusRed)
                        }
                    }
                    .padding(16)
                    .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))

                    Button {
                        isSigning = true
                        Task {
                            if await model.signActiveBlock() { dismiss() }
                            isSigning = false
                        }
                    } label: {
                        HStack {
                            if isSigning { ProgressView().tint(.white) }
                            Label(isSigning ? "Firmando" : "Confirmar firma", systemImage: "signature")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .attendancePrimaryButtonStyle()
                    .disabled(isSigning || !model.canSignActiveBlock)
                }
                .padding(20)
            }
            .background(EPTheme.background)
            .navigationTitle("Revisar y firmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Volver") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isSigning)
        .presentationDetents([.large])
    }

    private func reviewText(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.bold())
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AttendanceReopenSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AttendanceViewModel

    @State private var reason = ""
    @State private var isReopening = false
    @FocusState private var reasonFocused: Bool

    private var cleanReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "La firma anterior se conservará junto con esta justificación.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Motivo breve") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 110)
                        .focused($reasonFocused)
                        .accessibilityLabel("Motivo de reapertura")
                }

                Section {
                    Button {
                        isReopening = true
                        Task {
                            if await model.reopenActiveBlock(reason: cleanReason) { dismiss() }
                            isReopening = false
                        }
                    } label: {
                        HStack {
                            if isReopening { ProgressView() }
                            Text(isReopening ? "Reabriendo" : "Confirmar reapertura")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(cleanReason.count < 5 || isReopening)
                } footer: {
                    Text("Escribe al menos cinco caracteres. Por ejemplo: corregir atraso informado después del cierre.")
                }
            }
            .navigationTitle("Reabrir bloque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { reasonFocused = true }
        }
        .interactiveDismissDisabled(isReopening)
        .presentationDetents([.medium, .large])
    }
}

private struct AttendanceDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AttendanceViewModel

    @State private var selectedDate: Date
    @State private var isChanging = false

    init(model: AttendanceViewModel) {
        self.model = model
        _selectedDate = State(initialValue: model.date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DatePicker(
                    "Fecha de asistencia",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(EPTheme.primary)
                .padding(.horizontal)

                Text("Al cambiar la fecha se guardarán primero los cambios actuales.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer(minLength: 0)

                Button {
                    isChanging = true
                    Task {
                        if await model.changeDate(to: selectedDate) { dismiss() }
                        isChanging = false
                    }
                } label: {
                    HStack {
                        if isChanging { ProgressView().tint(.white) }
                        Text(isChanging ? "Cambiando fecha" : "Usar esta fecha")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .attendancePrimaryButtonStyle()
                .disabled(isChanging)
                .padding()
            }
            .background(EPTheme.background)
            .navigationTitle("Cambiar fecha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isChanging)
        .presentationDetents([.large])
    }
}
