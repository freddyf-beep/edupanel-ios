import SwiftUI

protocol EstudianteEvaluable: Identifiable {
    var estudianteId: String { get }
    var nombre: String { get }
    var hasPie: Bool { get }
    var completado: Bool { get }
}

extension EstudianteListaCotejo: EstudianteEvaluable {}
extension EstudianteRubrica: EstudianteEvaluable {}

struct SelectorGruposEvaluacion: View {
    let grupos: [(id: String, nombre: String, esAusentes: Bool, count: Int)]
    let activo: Int
    let disabled: Bool
    let onSelect: (Int) -> Void
    let onAgregarGrupo: () -> Void
    let onAusentes: () -> Void
    @Binding var mostrarDistribucion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(grupos.enumerated()), id: \.element.id) { index, grupo in
                        Button {
                            onSelect(index)
                        } label: {
                            HStack(spacing: 5) {
                                if grupo.esAusentes {
                                    Image(systemName: "person.fill.xmark")
                                        .font(.system(size: 9, weight: .black))
                                }
                                Text(grupo.nombre)
                                    .font(.system(size: 12, weight: .black))
                                Text("\(grupo.count)")
                                    .font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(activo == index ? 0.25 : 0.0), in: Capsule())
                            }
                            .foregroundStyle(activo == index ? .white : (grupo.esAusentes ? .orange : .secondary))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                activo == index
                                    ? AnyShapeStyle(grupo.esAusentes ? Color.orange : EPTheme.primary)
                                    : AnyShapeStyle(Color(.systemGray6)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                BotonAccionGrupo(titulo: "Agregar grupo", icono: "plus", disabled: disabled, accion: onAgregarGrupo)
                BotonAccionGrupo(titulo: "Ausentes", icono: "person.fill.xmark", disabled: disabled, accion: onAusentes)
                BotonAccionGrupo(titulo: "Distribucion", icono: "shuffle", disabled: disabled) {
                    withAnimation(EPTheme.spring) { mostrarDistribucion.toggle() }
                }
            }
        }
    }
}

struct DistribucionGruposCard: View {
    @Binding var distribucionPorCantidad: Bool
    @Binding var cantidadGrupos: Int
    @Binding var tamanoGrupo: Int
    let disabled: Bool
    let distribuir: () -> Void

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Distribucion rapida",
                    subtitle: "Reparte al azar los estudiantes en grupos. Los ausentes no se mueven.",
                    icon: "shuffle"
                )

                Picker("Modo", selection: $distribucionPorCantidad) {
                    Text("Por tamano").tag(false)
                    Text("Cantidad de grupos").tag(true)
                }
                .pickerStyle(.segmented)

                if distribucionPorCantidad {
                    Stepper(value: $cantidadGrupos, in: 1...12) {
                        Text("\(cantidadGrupos) grupos")
                            .font(.system(size: 13, weight: .bold))
                    }
                } else {
                    Stepper(value: $tamanoGrupo, in: 2...10) {
                        Text("\(tamanoGrupo) estudiantes por grupo")
                            .font(.system(size: 13, weight: .bold))
                    }
                }

                Button(action: distribuir) {
                    Label("Distribuir ahora", systemImage: "wand.and.stars")
                        .font(.system(size: 12.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(EPTheme.primary, in: Capsule())
                }
                .disabled(disabled)
            }
        }
    }
}

struct SelectorAlumnosEvaluacion<E: EstudianteEvaluable>: View {
    let estudiantes: [E]
    let grupoVacio: Bool
    let gruposDestino: [(index: Int, nombre: String)]
    let puedeMover: Bool
    @Binding var alumnoActivo: String?
    let onMove: (String, Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(estudiantes, id: \.estudianteId) { estudiante in
                    Button {
                        alumnoActivo = estudiante.estudianteId
                    } label: {
                        HStack(spacing: 5) {
                            if estudiante.completado {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .black))
                            }
                            Text(estudiante.nombre)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            if estudiante.hasPie {
                                Text("PIE")
                                    .font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                        .foregroundStyle(alumnoActivo == estudiante.estudianteId ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            alumnoActivo == estudiante.estudianteId
                                ? AnyShapeStyle(EPTheme.rose)
                                : AnyShapeStyle(EPTheme.card),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color(.separator).opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if puedeMover, !gruposDestino.isEmpty {
                            Menu("Mover a...") {
                                ForEach(gruposDestino, id: \.index) { destino in
                                    Button(destino.nombre) {
                                        onMove(estudiante.estudianteId, destino.index)
                                    }
                                }
                            }
                        }
                    }
                }

                if grupoVacio {
                    Text("Grupo vacio - manten presionado un alumno de otro grupo para moverlo aqui.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
        }
    }
}

struct BotonAccionGrupo: View {
    let titulo: String
    let icono: String
    var disabled = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Image(systemName: icono)
                    .font(.system(size: 10, weight: .black))
                Text(titulo)
                    .font(.system(size: 11.5, weight: .black))
            }
            .foregroundStyle(disabled ? .secondary : EPTheme.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background((disabled ? Color.secondary : EPTheme.primary).opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct BotonSiNo: View {
    let titulo: String
    let activo: Bool
    let tint: Color
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 11.5, weight: .black))
                .foregroundStyle(activo ? .white : tint)
                .frame(minWidth: 38)
                .padding(.vertical, 8)
                .background(activo ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: activo)
    }
}
