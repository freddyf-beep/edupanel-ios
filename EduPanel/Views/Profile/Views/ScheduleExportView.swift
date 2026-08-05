import SwiftUI
import UIKit

// MARK: - Printable Schedule Grid View

/// Off-screen SwiftUI view that draws a classic school/university
/// weekly timetable grid for PDF export.
struct ScheduleExportView: View {
    let horario: [ClaseHorario]
    let teacherName: String
    let generatedDate: Date
    var isLandscape: Bool = false

    private var pageWidth: CGFloat { isLandscape ? 792 : 612 }
    private var pageHeight: CGFloat { isLandscape ? 612 : 792 }
    private let margin: CGFloat = 32
    private let hourColumnWidth: CGFloat = 52
    private let headerRowHeight: CGFloat = 34
    private var rowHeight: CGFloat {
        let totalHours = CGFloat(max(1, hourRange.max - hourRange.min))
        let availableGridHeight = pageHeight - margin * 2 - headerRowHeight - 95
        let ideal: CGFloat = isLandscape ? 38 : 44
        return max(24, min(ideal, availableGridHeight / totalHours))
    }

    private var workdays: [String] {
        let present = Set(horario.map(\.dia))
        return DateHelpers.scheduleDays.filter { present.contains($0) }
    }

    private var dayColumnWidth: CGFloat {
        (pageWidth - margin * 2 - hourColumnWidth) / CGFloat(workdays.count)
    }

    private var hourRange: (min: Int, max: Int) {
        guard !horario.isEmpty else { return (8, 18) }
        let minM = max(0, (horario.map { DateHelpers.minutes(from: $0.horaInicio) }.min() ?? 480) - 15)
        let maxM = min(1440, (horario.map { DateHelpers.minutes(from: $0.horaFin) }.max() ?? 1080) + 15)
        return (max(0, minM / 60), min(24, Int(ceil(Double(maxM) / 60.0))))
    }

    private var gridHeight: CGFloat {
        CGFloat(hourRange.max - hourRange.min) * rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            headerSection
                .padding(.bottom, 14)

            // --- Grid ---
            VStack(spacing: 0) {
                dayHeaderRow
                gridBody
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
            )

            Spacer(minLength: 4)

            // --- Footer ---
            footerSection
        }
        .padding(margin)
        .frame(width: pageWidth, height: pageHeight)
        .background(Color.white)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(EPTheme.color(hex: "#F03E6E"))
                Text("EduPanel")
                    .font(.title3.weight(.black))
                    .foregroundStyle(EPTheme.color(hex: "#F03E6E"))
            }

            Text("MI HORARIO SEMANAL")
                .font(.system(size: isLandscape ? 20 : 18, weight: .black, design: .rounded))
                .foregroundStyle(.black)

            if !teacherName.isEmpty {
                Text(teacherName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Day Header Row

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Text("HORA")
                .font(.system(size: 9.5, weight: .black))
                .foregroundStyle(.white)
                .frame(width: hourColumnWidth, height: headerRowHeight, alignment: .center)
                .background(EPTheme.color(hex: "#F03E6E"))

            ForEach(workdays, id: \.self) { day in
                Text(String(day.prefix(3)).uppercased())
                    .font(.system(size: 10.5, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: dayColumnWidth, height: headerRowHeight, alignment: .center)
                    .background(EPTheme.color(hex: "#F03E6E"))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1)
                    }
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8,
                style: .continuous
            )
        )
    }

    // MARK: - Grid Body

    private var gridBody: some View {
        ZStack(alignment: .topLeading) {
            // Background rows with 30-min dividers
            VStack(spacing: 0) {
                ForEach(Array(hourRange.min..<hourRange.max), id: \.self) { hour in
                    VStack(spacing: 0) {
                        // First 30 mins (:00 to :30)
                        Rectangle()
                            .fill(hour % 2 == 0 ? Color.white : Color.gray.opacity(0.03))
                            .frame(height: rowHeight / 2)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.20))
                                    .frame(height: 0.5)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.08))
                                    .frame(height: 0.5)
                            }

                        // Second 30 mins (:30 to :00)
                        Rectangle()
                            .fill(hour % 2 == 0 ? Color.white : Color.gray.opacity(0.03))
                            .frame(height: rowHeight / 2)
                    }
                }
            }

            // Hour and half-hour labels
            VStack(spacing: 0) {
                ForEach(Array(hourRange.min..<hourRange.max), id: \.self) { hour in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%d:00", hour))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: hourColumnWidth, height: rowHeight / 2, alignment: .topLeading)
                            .padding(.top, 2)

                        Text(String(format: "%d:30", hour))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: hourColumnWidth, height: rowHeight / 2, alignment: .topLeading)
                            .padding(.top, 2)
                    }
                    .padding(.leading, 5)
                }
            }

            // Vertical column dividers
            ForEach(0..<workdays.count, id: \.self) { i in
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 0.5, height: gridHeight)
                    .offset(x: hourColumnWidth + dayColumnWidth * CGFloat(i))
            }

            // Class blocks
            ForEach(horario) { item in
                classBlock(item)
            }
        }
        .frame(width: pageWidth - margin * 2, height: gridHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    // MARK: - Class Block

    private func classBlock(_ item: ClaseHorario) -> some View {
        let startMin = DateHelpers.minutes(from: item.horaInicio)
        let endMin = DateHelpers.minutes(from: item.horaFin)
        let dayIndex = workdays.firstIndex(of: item.dia) ?? 0

        let topOffset = CGFloat(startMin - hourRange.min * 60) / 60.0 * rowHeight
        let blockHeight = max(16, CGFloat(endMin - startMin) / 60.0 * rowHeight - 1.5)
        let leftOffset = hourColumnWidth + dayColumnWidth * CGFloat(dayIndex) + 1.5

        let vertPadding: CGFloat = blockHeight < 32 ? 2 : 4
        let titleFontSize: CGFloat = blockHeight < 28 ? 8 : (isLandscape ? 9.5 : 9)

        return VStack(alignment: .leading, spacing: 1) {
            Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                .font(.system(size: titleFontSize, weight: .black))
                .lineLimit(blockHeight < 32 ? 1 : 2)

            if let asignatura = item.asignatura, !asignatura.isEmpty, blockHeight >= 36 {
                Text(asignatura)
                    .font(.system(size: isLandscape ? 8 : 7.5, weight: .bold))
                    .lineLimit(1)
                    .opacity(0.9)
            }

            if blockHeight >= 46 {
                Text(item.timeRange)
                    .font(.system(size: isLandscape ? 7.5 : 7, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, vertPadding)
        .frame(width: max(10, dayColumnWidth - 3), alignment: .topLeading)
        .frame(height: blockHeight)
        .background(
            Color(profileHex: item.colorHex),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .offset(x: leftOffset, y: topOffset + 1)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Generado el \(generatedDate.formatted(date: .long, time: .shortened))")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("edupanel.cl")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(EPTheme.color(hex: "#F03E6E"))
        }
    }
}

@MainActor
struct ScheduleExporter {

    /// Renders the schedule grid to a PDF file at a specific URL.
    static func renderToFile(
        horario: [ClaseHorario],
        teacherName: String,
        isLandscape: Bool,
        outputURL: URL
    ) {
        let view = ScheduleExportView(
            horario: horario,
            teacherName: teacherName,
            generatedDate: Date(),
            isLandscape: isLandscape
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // Retina quality

        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(outputURL as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
    }

    /// Renders the schedule grid to a PDF and presents the iOS share sheet.
    static func exportAndShare(
        horario: [ClaseHorario],
        teacherName: String,
        isLandscape: Bool = false,
        from sourceView: UIView? = nil
    ) {
        let nameSlug = teacherName.isEmpty ? "Profesor" : teacherName.replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Horario_\(nameSlug).pdf")

        renderToFile(
            horario: horario,
            teacherName: teacherName,
            isLandscape: isLandscape,
            outputURL: url
        )

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let root = windowScene.windows.first?.rootViewController {
            var topVC = root
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = sourceView ?? topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            }
            topVC.present(activityVC, animated: true)
        }
    }
}
