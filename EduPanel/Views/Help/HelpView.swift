import SwiftUI

struct HelpView: View {
    @State private var faqAbierta: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard

                ProfileSection(title: "Preguntas frecuentes", icon: "questionmark.circle.fill", hint: nil) {
                    VStack(spacing: 8) {
                        ForEach(faqs) { faq in
                            faqRow(faq)
                        }
                    }
                }

                ProfileSection(title: "Crea tu primera planificación", icon: "book.closed.fill", hint: "Guía rápida") {
                    VStack(alignment: .leading, spacing: 10) {
                        pasoRow(1, "Configura tu horario en Mi Perfil → Mi Semana con bloques tipo \"clase\".")
                        pasoRow(2, "Abre la pestaña Planificar y entra al curso que quieras trabajar.")
                        pasoRow(3, "Crea unidades con el formulario inline: nombre, tipo y listo.")
                        pasoRow(4, "Toca \"Ver\" en una unidad para seleccionar OAs, armar el cronograma y planificar cada clase.")
                    }
                }

                ProfileSection(title: "Configura tu horario", icon: "calendar", hint: "Guía rápida") {
                    VStack(alignment: .leading, spacing: 10) {
                        pasoRow(1, "Ve a Mi Perfil → Mi Semana y toca \"Nuevo bloque\".")
                        pasoRow(2, "El asistente te guía en 4 pasos: tipo, días, horario y detalles.")
                        pasoRow(3, "Los bloques tipo clase crean cursos automáticamente; los no lectivos (almuerzo, recreo) solo se muestran en tu semana.")
                        pasoRow(4, "Asocia cada curso a un nivel curricular en la pestaña Asignaturas.")
                    }
                }

                ProfileSection(title: "Contacto y soporte", icon: "lifepreserver.fill", hint: nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        contactoRow(
                            icon: "envelope.fill",
                            titulo: "Escríbenos",
                            detalle: "soporte@edupanel.cl",
                            url: "mailto:soporte@edupanel.cl?subject=Ayuda%20EduPanel%20iOS",
                            tint: .green
                        )
                        contactoRow(
                            icon: "globe",
                            titulo: "EduPanel web",
                            detalle: "Toda tu información sincronizada",
                            url: "https://edupanel.cl",
                            tint: .blue
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ayuda")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lifepreserver.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            Text("¿Cómo te ayudamos?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Guías rápidas y respuestas para sacarle el máximo a EduPanel en tu iPhone.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .shadow(color: EPTheme.primary.opacity(0.25), radius: 14, y: 7)
    }

    private struct FAQ: Identifiable {
        let pregunta: String
        let respuesta: String

        var id: String { pregunta }
    }

    private let faqs: [FAQ] = [
        FAQ(
            pregunta: "¿Mis datos se sincronizan con la web?",
            respuesta: "Sí. La app lee y escribe los mismos documentos de Firestore que EduPanel web: horario, planificaciones, unidades, cronogramas y estudiantes."
        ),
        FAQ(
            pregunta: "¿Qué diferencia hay entre modo Simple y Detallado?",
            respuesta: "El modo Simple muestra solo lo esencial para uso rápido en el celular. El Detallado muestra toda la información, igual que la web. Cámbialo con el ícono de ojo o en Configuración."
        ),
        FAQ(
            pregunta: "¿Por qué no veo mis cursos?",
            respuesta: "Los cursos nacen de tu horario. Crea bloques tipo \"clase\" en Mi Perfil → Mi Semana y aparecerán en toda la app."
        ),
        FAQ(
            pregunta: "¿Cómo marco una clase como dictada?",
            respuesta: "En Inicio, dentro del timeline de hoy, toca el círculo a la derecha de cada clase. Las pendientes quedan en la pestaña Pendientes."
        ),
        FAQ(
            pregunta: "¿Puedo importar mi lista de estudiantes?",
            respuesta: "Sí. En Mi Perfil → Mis Cursos abre \"Importación masiva\": acepta listas de nombres o un JSON generado con IA desde una foto de tu lista."
        )
    ]

    private func faqRow(_ faq: FAQ) -> some View {
        let abierta = faqAbierta == faq.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EPTheme.spring) {
                    faqAbierta = abierta ? nil : faq.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(faq.pregunta)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(EPTheme.primary)
                        .rotationEffect(.degrees(abierta ? 180 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if abierta {
                Text(faq.respuesta)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pasoRow(_ numero: Int, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(numero)")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(EPTheme.primary, in: Circle())

            Text(texto)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contactoRow(icon: String, titulo: String, detalle: String, url: String, tint: Color) -> some View {
        Group {
            if let destino = URL(string: url) {
                Link(destination: destino) {
                    HStack(spacing: 11) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 30, height: 30)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(titulo)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(detalle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
