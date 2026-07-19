import SwiftUI

extension AttendanceStatus {
    var tint: Color {
        switch self {
        case .present: return EPTheme.statusGreen
        case .absent: return EPTheme.statusRed
        case .late: return EPTheme.statusAmber
        case .withdrawn: return .secondary
        case .invalid: return EPTheme.statusRed
        }
    }
}

struct AttendanceContextCard: View {
    let course: String
    let subject: String
    let dateLabel: String
    let block: AttendanceBlock
    let summary: AttendanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(course)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Label(
                    block.isSigned ? "Firmado" : (summary.pending == 0 ? "Confirmado" : "Editable"),
                    systemImage: block.isSigned ? "lock.shield.fill" : "pencil.circle.fill"
                )
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    contextItem(icon: "calendar", text: dateLabel)
                    contextItem(icon: "clock.fill", text: "\(block.label) · \(block.timeRange)")
                }
                VStack(alignment: .leading, spacing: 8) {
                    contextItem(icon: "calendar", text: dateLabel)
                    contextItem(icon: "clock.fill", text: "\(block.label) · \(block.timeRange)")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous))
        .shadow(color: EPTheme.primary.opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course), \(subject), \(dateLabel), \(block.label), \(block.timeRange), \(block.isSigned ? "bloque firmado" : "bloque editable")")
    }

    private func contextItem(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(2)
    }
}

struct AttendanceProgressCard: View {
    let block: AttendanceBlock
    let summary: AttendanceSummary
    let onScanQR: () -> Void
    let onConfirmAll: () -> Void
    let onQuickMode: () -> Void

    private var confirmed: Int { max(0, block.attendance.count - summary.pending) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.isSigned ? "Lista cerrada" : (summary.pending == 0 ? "Lista confirmada" : "Lista sin confirmar"))
                        .font(.headline)
                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(confirmed)/\(block.attendance.count)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(summary.pending == 0 ? EPTheme.statusGreen : EPTheme.statusAmber)
            }

            ProgressView(value: Double(confirmed), total: Double(max(1, block.attendance.count)))
                .tint(summary.pending == 0 ? EPTheme.statusGreen : EPTheme.primary)

            if !block.isSigned {
                Button(action: onScanQR) {
                    Label("Escanear QR", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .attendancePrimaryButtonStyle()
                .accessibilityHint("Abre la cámara y valida una tarjeta antes de confirmar presencia")

                Button(action: onConfirmAll) {
                    Label("Confirmar todos presentes", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .attendanceSecondaryButtonStyle()
                .accessibilityHint("Confirma explícitamente a todo el curso como presente")

                Button(action: onQuickMode) {
                    Label("Pasar lista en modo rápido", systemImage: "hand.tap.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .attendanceSecondaryButtonStyle()
            }
        }
        .padding(16)
        .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                .stroke(EPTheme.border, lineWidth: 0.75)
        }
    }

    private var statusDescription: String {
        if block.isSigned { return "La edición está bloqueada hasta una reapertura justificada." }
        if block.attendance.isEmpty { return "No hay estudiantes cargados para este curso." }
        if summary.pending == 0 { return "Todos los registros fueron revisados." }
        return "Falta revisar \(summary.pending) estudiante\(summary.pending == 1 ? "" : "s")."
    }
}

struct AttendanceSummaryGrid: View {
    let summary: AttendanceSummary

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            metric("Presentes", value: summary.present, status: .present)
            metric("Ausentes", value: summary.absent, status: .absent)
            metric("Atrasos", value: summary.late, status: .late)
            metric("Retiros", value: summary.withdrawn, status: .withdrawn)
        }
    }

    private func metric(_ title: String, value: Int, status: AttendanceStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(status.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.title3.bold().monospacedDigit())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(status.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct AttendanceStudentRow: View {
    let student: StudentAttendance
    let blockSigned: Bool
    let onSelect: (AttendanceStatus) -> Void

    private var isConfirmed: Bool {
        AttendanceRules.isConfirmed(student, blockSigned: blockSigned)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(student.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    isConfirmed ? "Registro confirmado" : "Sin confirmar",
                    systemImage: isConfirmed ? "checkmark.seal.fill" : "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isConfirmed ? EPTheme.statusGreen : EPTheme.statusAmber)
            }

            Spacer(minLength: 8)

            if blockSigned {
                statusLabel(student.status)
            } else {
                Menu {
                    ForEach(AttendanceStatus.validCases, id: \.self) { status in
                        Button {
                            onSelect(status)
                        } label: {
                            Label(status.title, systemImage: status.systemImage)
                        }
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        statusMenuLabel(
                            title: isConfirmed ? student.status.title : "Elegir estado"
                        )
                        statusMenuLabel(
                            title: isConfirmed ? student.status.shortTitle : "Elegir"
                        )
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isConfirmed ? student.status.tint : EPTheme.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background((isConfirmed ? student.status.tint : EPTheme.primary).opacity(0.1), in: Capsule())
                }
                .accessibilityLabel("Cambiar estado de \(student.name)")
                .accessibilityValue(isConfirmed ? student.status.title : "Sin confirmar")
                .accessibilityHint("Abre las opciones Presente, Ausente, Atraso y Retirado")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isConfirmed ? EPTheme.border : EPTheme.statusAmber.opacity(0.5), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusLabel(_ status: AttendanceStatus) -> some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(status.tint.opacity(0.1), in: Capsule())
            .accessibilityLabel("Estado: \(status.title)")
    }

    private func statusMenuLabel(title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: student.status.systemImage)
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.bold())
        }
    }
}

struct AttendanceLessonCard: View {
    let block: AttendanceBlock
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.pages.fill")
                    .font(.title3)
                    .foregroundStyle(EPTheme.primary)
                    .frame(width: 40, height: 40)
                    .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Objetivo y actividad")
                        .font(.headline)
                    Text(lessonDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)
                Image(systemName: block.isSigned ? "lock.fill" : "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(block.isSigned ? "Muestra el leccionario guardado" : "Permite editar los datos necesarios para firmar")
    }

    private var lessonDescription: String {
        let objective = block.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = block.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        if objective.isEmpty && activity.isEmpty { return "Completa estos datos antes de firmar el bloque." }
        if objective.isEmpty { return "Falta el objetivo. Actividad: \(activity)" }
        if activity.isEmpty { return "Objetivo: \(objective). Falta la actividad." }
        return "Objetivo: \(objective)"
    }
}

struct AttendanceSaveBadge: View {
    let state: AttendanceSaveState

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.1), in: Capsule())
            .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .idle: return "Cambios sin guardar"
        case .saving: return "Guardando"
        case .saved: return "Guardado"
        case .pendingSync: return "Pendiente de sincronización"
        case .failed: return "Error de guardado"
        }
    }

    private var icon: String {
        switch state {
        case .idle: return "circle.dotted"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle.fill"
        case .pendingSync: return "icloud.slash.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .idle, .saving: return EPTheme.statusBlue
        case .saved: return EPTheme.statusGreen
        case .pendingSync: return EPTheme.statusAmber
        case .failed: return EPTheme.statusRed
        }
    }
}

struct AttendanceLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: index == 0 ? EPTheme.heroRadius : EPTheme.cardRadius)
                    .fill(EPTheme.card)
                    .frame(height: index == 0 ? 150 : 82)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando asistencia")
    }
}

private struct AttendancePrimaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            content
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .glassEffect(
                    .regular.tint(EPTheme.primary).interactive(),
                    in: .rect(cornerRadius: 15)
                )
        } else {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 15))
                .tint(EPTheme.primary)
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 15))
            .tint(EPTheme.primary)
    }
}

private struct AttendanceSecondaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            content
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 15))
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 15))
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 15))
    }
}

extension View {
    func attendancePrimaryButtonStyle() -> some View {
        modifier(AttendancePrimaryButtonModifier())
    }

    func attendanceSecondaryButtonStyle() -> some View {
        modifier(AttendanceSecondaryButtonModifier())
    }
}
