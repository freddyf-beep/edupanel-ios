import SwiftUI

/// Botón + diálogo de conflictos para empujar las notas de una evaluación al
/// módulo de Calificaciones. La acción devuelve el resultado; si requiere
/// confirmación (ya hay notas distintas), pide sobrescribir.
struct SincronizarCalificacionesButton: View {
    let accion: (_ sobrescribir: Bool) async throws -> SyncCalificacionesResultado

    @State private var sincronizando = false
    @State private var mensaje: String?
    @State private var esError = false
    @State private var pendiente: SyncCalificacionesResultado?
    @State private var mostrarConfirmacion = false

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(
                    title: "Calificaciones",
                    subtitle: "Env\u{00ED}a las notas calculadas al libro de notas del curso.",
                    icon: "arrow.triangle.2.circlepath"
                )

                Button {
                    Task { await ejecutar(sobrescribir: false) }
                } label: {
                    HStack(spacing: 7) {
                        if sincronizando {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: 12, weight: .black))
                        }
                        Text(sincronizando ? "Sincronizando..." : "Sincronizar con Calificaciones")
                            .font(.system(size: 13, weight: .black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(EPTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sincronizando)

                if let mensaje {
                    Label(mensaje, systemImage: esError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(esError ? .orange : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Sobrescribir notas existentes", isPresented: $mostrarConfirmacion) {
            Button("Cancelar", role: .cancel) {}
            Button("Sobrescribir", role: .destructive) {
                Task { await ejecutar(sobrescribir: true) }
            }
        } message: {
            Text(mensajeConflictos)
        }
    }

    private var mensajeConflictos: String {
        guard let pendiente else { return "" }
        let detalle = pendiente.conflictos.prefix(6)
            .map { "\($0.nombre): \($0.anterior) \u{2192} \($0.nueva)" }
            .joined(separator: "\n")
        let extra = pendiente.conflictos.count > 6 ? "\n+\(pendiente.conflictos.count - 6) m\u{00E1}s" : ""
        return "Ya hay \(pendiente.conflictos.count) nota(s) distinta(s) en Calificaciones. Si contin\u{00FA}as se reemplazan:\n\n\(detalle)\(extra)"
    }

    private func ejecutar(sobrescribir: Bool) async {
        sincronizando = true
        mensaje = nil
        defer { sincronizando = false }
        do {
            let resultado = try await accion(sobrescribir)
            if resultado.requiereConfirmacion {
                pendiente = resultado
                mostrarConfirmacion = true
                return
            }
            esError = false
            var texto = "\(resultado.notasSincronizadas) nota(s) sincronizada(s)."
            if resultado.estudiantesSinNota > 0 {
                texto += " \(resultado.estudiantesSinNota) sin evaluar."
            }
            mensaje = texto
        } catch {
            esError = true
            mensaje = "No se pudo sincronizar con Calificaciones."
        }
    }
}
