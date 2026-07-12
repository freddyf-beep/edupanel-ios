import SwiftUI

struct PruebaResponseEditor: View {
    let item: PruebaItem
    let number: Int
    let response: PruebaResponseDraft?
    let isDisabled: Bool
    let onChange: (PruebaResponseDraft) -> Void

    private var currentResponse: PruebaResponseDraft? {
        response ?? PruebaResponseDraft.empty(for: item)
    }

    private var score: Double {
        PruebaScoring.score(item: item, response: response)
    }

    private var incompatibilityMessage: String? {
        guard let itemId = item.sourceId, !itemId.isEmpty else {
            return "Esta pregunta no tiene un ID web estable. Su respuesta no se puede guardar sin riesgo."
        }
        guard !item.kind.isUnknown, PruebaEditorItemType.resolve(item.rawType) != nil else {
            return "Este tipo de pregunta proviene de una versi\u{00F3}n futura. Se conserva intacto y no se puede corregir aqu\u{00ED}."
        }
        guard let response else { return nil }
        guard response.id == itemId else {
            return "La respuesta est\u{00E1} asociada a otra pregunta. Se conserva intacta para evitar mezclar datos."
        }
        guard !response.isUnknown, PruebaEditorItemType.resolve(response.type) != nil else {
            return "La respuesta usa un formato web futuro (\(response.type.isEmpty ? "sin tipo" : response.type)). Se conserva intacta."
        }
        guard response.kind == item.kind else {
            return "La respuesta guardada es de tipo \(response.kind.label), pero la pregunta ahora es \(item.kind.label). Se conserva intacta."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !item.enunciado.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.enunciado)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let incompatibilityMessage {
                warning(incompatibilityMessage)
            } else {
                typeSpecificEditor
            }
        }
        .padding(13)
        .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.secondary.opacity(0.14), lineWidth: 1)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: item.kind.icon)
                .foregroundStyle(EPTheme.rose)
                .frame(width: 24, height: 24)
                .background(EPTheme.rose.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Pregunta \(number)")
                    .font(.caption.weight(.black))
                Text(item.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(formatted(score)) / \(formatted(item.puntaje)) pts")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(score > 0 ? EPTheme.statusGreen : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
    }

    @ViewBuilder
    private var typeSpecificEditor: some View {
        switch item.kind {
        case .seleccionMultiple:
            multipleChoiceEditor
        case .verdaderoFalso:
            trueFalseEditor
        case .pareados:
            matchingEditor
        case .ordenar:
            orderingEditor
        case .completar:
            completionEditor
        case .respuestaCorta:
            shortAnswerEditor
        case .desarrollo:
            developmentEditor
        case .unknown:
            EmptyView()
        }
    }

    // MARK: Selecci\u{00F3}n m\u{00FA}ltiple

    private var multipleChoiceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.alternativas.isEmpty {
                warning("La pregunta no contiene alternativas legibles.")
            }

            ForEach(item.alternativas) { alternative in
                let selected = alternative.sourceId == currentResponse?.alternativaId
                let revealsCorrection = response != nil
                Button {
                    guard let alternativeId = alternative.sourceId, !alternativeId.isEmpty else { return }
                    update { $0.alternativaId = alternativeId }
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? EPTheme.rose : .secondary)
                        Text(alternative.texto.isEmpty
                             ? "Alternativa \(alternative.originalIndex + 1)"
                             : alternative.texto)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if revealsCorrection, alternative.esCorrecta {
                            Text("Correcta")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(9)
                    .background(
                        selected
                            ? (alternative.esCorrecta ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            : (revealsCorrection && alternative.esCorrecta ? Color.green.opacity(0.05) : Color.gray.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(alternative.sourceId?.isEmpty != false)
            }

            if item.alternativas.contains(where: { $0.sourceId?.isEmpty != false }) {
                warning("Hay alternativas sin ID web; se muestran, pero no se pueden seleccionar.")
            }
            if let selectedId = currentResponse?.alternativaId,
               !selectedId.isEmpty,
               !item.alternativas.contains(where: { $0.sourceId == selectedId }) {
                warning("La alternativa guardada ya no existe en la pregunta. El valor heredado se conserva hasta que elijas otra.")
            }
        }
    }

    // MARK: Verdadero o falso

    private var trueFalseEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                truthButton(title: "Verdadero", value: true, icon: "checkmark")
                truthButton(title: "Falso", value: false, icon: "xmark")
            }

            if let expected = item.respuestaCorrecta {
                Text("Respuesta correcta: \(expected ? "Verdadero" : "Falso")")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if item.pideJustificacion {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Justificaci\u{00F3}n")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Escribe la justificaci\u{00F3}n", text: responseBinding(\.justificacion, fallback: ""), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            }
        }
    }

    private func truthButton(title: String, value: Bool, icon: String) -> some View {
        let selected = currentResponse?.valor == value
        return Button {
            update { $0.valor = value }
        } label: {
            Label(title, systemImage: selected ? "\(icon).circle.fill" : "\(icon).circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? EPTheme.primaryForeground : .primary)
                .background(selected ? EPTheme.rose : .secondary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pareados

    private var matchingEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            if item.columnaA.isEmpty || item.columnaB.isEmpty {
                warning("Las columnas de t\u{00E9}rminos pareados est\u{00E1}n incompletas.")
            }

            ForEach(item.columnaA) { entryA in
                VStack(alignment: .leading, spacing: 5) {
                    Text(entryA.texto.isEmpty
                         ? "Elemento A\(entryA.originalIndex + 1)"
                         : entryA.texto)
                        .font(.subheadline.weight(.semibold))

                    if let aId = entryA.sourceId, !aId.isEmpty {
                        Picker("Pareja", selection: pairingBinding(for: aId)) {
                            Text("Sin respuesta").tag("")

                            if let stored = currentResponse?.emparejamientos[aId],
                               !stored.isEmpty,
                               !item.columnaB.contains(where: { $0.sourceId == stored }) {
                                Text("Valor heredado no disponible").tag(stored)
                            }

                            ForEach(item.columnaB) { entryB in
                                if let bId = entryB.sourceId, !bId.isEmpty {
                                    Text(entryB.texto.isEmpty
                                         ? "Elemento B\(entryB.originalIndex + 1)"
                                         : entryB.texto)
                                        .tag(bId)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let correct = item.columnaB.first(where: { $0.correctaParaAId == aId }) {
                            Text("Correcta: \(correct.texto.isEmpty ? "opción \(correct.originalIndex + 1)" : correct.texto)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        warning("Este elemento de la columna A no tiene ID web y no puede recibir una pareja.")
                    }
                }
                .padding(9)
                .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            if item.columnaB.contains(where: { $0.sourceId?.isEmpty != false }) {
                warning("Hay opciones de la columna B sin ID web; se conservar\u{00E1}n visibles, pero no son seleccionables.")
            }
            if hasDuplicateIds(item.columnaA.compactMap(\.sourceId)) ||
                hasDuplicateIds(item.columnaB.compactMap(\.sourceId)) {
                warning("La pregunta contiene IDs repetidos en sus columnas. Revisa la prueba antes de guardar correcciones.")
            }

            let validAIds = Set(item.columnaA.compactMap(\.sourceId))
            if currentResponse?.emparejamientos.keys.contains(where: { !validAIds.contains($0) }) == true {
                warning("La respuesta incluye parejas de una versi\u{00F3}n anterior. Permanecer\u{00E1}n preservadas.")
            }
        }
    }

    // MARK: Ordenar

    private var orderingEditor: some View {
        let order = currentResponse?.orden ?? []
        let placedIds = Set(order)
        let availableSteps = uniqueSteps.filter { step in
            guard let id = step.sourceId else { return false }
            return !placedIds.contains(id)
        }
        let validIds = Set(uniqueSteps.compactMap(\.sourceId))
        let hasUnknownTokens = order.contains { !validIds.contains($0) }

        return VStack(alignment: .leading, spacing: 9) {
            Text("Orden registrado")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if order.isEmpty {
                Text("A\u{00FA}n no hay pasos ordenados. Agr\u{00E9}galos en la secuencia entregada por el estudiante.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(Array(order.enumerated()), id: \.offset) { index, stepId in
                let step = item.pasos.first(where: { $0.sourceId == stepId })
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .monospacedDigit()
                        .frame(width: 25, height: 25)
                        .background(EPTheme.rose.opacity(0.1), in: Circle())

                    Text(step.map { stepTitle($0) } ?? "Paso heredado (\(stepId))")
                        .font(.subheadline)
                        .foregroundStyle(step == nil ? .orange : .primary)
                        .lineLimit(3)

                    if let step {
                        Text("\(step.originalIndex + 1)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Posición correcta \(step.originalIndex + 1)")
                    }

                    Spacer(minLength: 4)

                    Button { moveOrder(from: index, to: index - 1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button { moveOrder(from: index, to: index + 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index + 1 == order.count)

                    if step != nil {
                        Button(role: .destructive) { removeOrderEntry(at: index) } label: {
                            Image(systemName: "xmark.circle")
                        }
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Paso heredado protegido")
                    }
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            if !availableSteps.isEmpty {
                Menu {
                    ForEach(availableSteps) { step in
                        if let stepId = step.sourceId {
                            Button(stepTitle(step)) { appendOrder(stepId) }
                        }
                    }
                } label: {
                    Label("Agregar paso", systemImage: "plus.circle")
                        .font(.caption.weight(.bold))
                }
            }

            if item.pasos.contains(where: { $0.sourceId?.isEmpty != false }) {
                warning("Hay pasos sin ID web; se muestran en la prueba, pero no se pueden incorporar a la respuesta.")
            }
            if hasDuplicateIds(item.pasos.compactMap(\.sourceId)) || order.count != Set(order).count {
                warning("La secuencia contiene IDs repetidos. Puedes retirar las repeticiones conocidas sin perder los valores futuros.")
            }
            if hasUnknownTokens {
                warning("La secuencia contiene pasos de una versi\u{00F3}n anterior. Se muestran bloqueados y se conservan al reordenar.")
            }
        }
    }

    private var uniqueSteps: [PruebaPaso] {
        var seen = Set<String>()
        return item.pasos.filter { step in
            guard let id = step.sourceId, !id.isEmpty else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: Completar

    private var completionEditor: some View {
        let storedCount = currentResponse?.respuestas.count ?? 0
        let expectedCount = item.respuestasCorrectas.count
        let count = max(storedCount, expectedCount)

        return VStack(alignment: .leading, spacing: 9) {
            if let text = item.textoConBlancos,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.subheadline)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            if count == 0 {
                warning("La pregunta no declara espacios de respuesta legibles.")
            } else {
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Respuesta \(index + 1)", text: completionBinding(at: index))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Respuesta para el espacio \(index + 1)")
                        if item.respuestasCorrectas.indices.contains(index) {
                            Text("Esperada: \(item.respuestasCorrectas[index])")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !item.bancoPalabras.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Banco de palabras")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(item.bancoPalabras.joined(separator: "  \u{00B7}  "))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if storedCount > expectedCount {
                warning("Hay respuestas posicionales heredadas adicionales. Se mantienen visibles para no desplazarlas ni perderlas.")
            }
        }
    }

    // MARK: Respuesta corta

    private var shortAnswerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            responseTextEditor(minHeight: 78)

            if let expected = item.respuestaEsperada,
               !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                referenceBox(title: "Respuesta esperada", text: expected)
            }

            PruebaNullableScoreControl(
                title: "Puntaje manual",
                value: currentResponse?.puntajeManual,
                maximum: item.puntaje,
                isDisabled: isDisabled,
                onChange: { value in update { $0.puntajeManual = value } }
            )
        }
    }

    // MARK: Desarrollo

    private var developmentEditor: some View {
        let manualOverride = currentResponse?.puntajeManual != nil
        let validCriterionIds = Set(item.criterios.compactMap(\.sourceId))
        let hasPreservedCriteria = currentResponse?.puntajePorCriterio.keys.contains {
            !validCriterionIds.contains($0)
        } == true

        return VStack(alignment: .leading, spacing: 10) {
            responseTextEditor(minHeight: max(110, CGFloat(item.lineasRespuesta ?? 4) * 20))

            if let guide = item.pautaCorreccion,
               !guide.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                referenceBox(title: "Pauta de correcci\u{00F3}n", text: guide)
            }

            if !item.criterios.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Puntaje por criterio")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(item.criterios) { criterion in
                        if let criterionId = criterion.sourceId, !criterionId.isEmpty {
                            PruebaNullableScoreControl(
                                title: criterion.texto.isEmpty
                                    ? "Criterio \(criterion.originalIndex + 1)"
                                    : criterion.texto,
                                value: currentResponse?.puntajePorCriterio[criterionId],
                                maximum: criterion.puntaje,
                                isDisabled: isDisabled || manualOverride,
                                onChange: { value in
                                    update { draft in
                                        if let value {
                                            draft.puntajePorCriterio[criterionId] = value
                                        } else {
                                            draft.puntajePorCriterio.removeValue(forKey: criterionId)
                                        }
                                    }
                                }
                            )
                        } else {
                            warning("Un criterio no tiene ID web; su puntaje no puede asociarse de forma segura.")
                        }
                    }
                }
                .padding(10)
                .background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            }

            PruebaNullableScoreControl(
                title: "Puntaje manual total",
                value: currentResponse?.puntajeManual,
                maximum: item.puntaje,
                isDisabled: isDisabled,
                onChange: { value in update { $0.puntajeManual = value } }
            )

            if manualOverride {
                Label("El puntaje manual reemplaza la suma de criterios; sus valores permanecen guardados.",
                      systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if hasPreservedCriteria {
                warning("Existen puntajes de criterios que ya no aparecen en la prueba. Se conservar\u{00E1}n intactos.")
            }
        }
    }

    // MARK: Controles compartidos

    private func responseTextEditor(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Respuesta del estudiante")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: responseBinding(\.texto, fallback: ""))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: minHeight)
                .background(.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                }
        }
    }

    private func referenceBox(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EPTheme.statusBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func responseBinding<Value>(
        _ keyPath: WritableKeyPath<PruebaResponseDraft, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { currentResponse?[keyPath: keyPath] ?? fallback },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }

    private func pairingBinding(for aId: String) -> Binding<String> {
        Binding(
            get: { currentResponse?.emparejamientos[aId] ?? "" },
            set: { bId in
                update { draft in
                    // La web conserva la clave del elemento A incluso al volver a
                    // "Sin respuesta"; mantener el string vacío replica ese contrato.
                    draft.emparejamientos[aId] = bId
                }
            }
        )
    }

    private func completionBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let answers = currentResponse?.respuestas, answers.indices.contains(index) else { return "" }
                return answers[index]
            },
            set: { value in
                update { draft in
                    while draft.respuestas.count <= index { draft.respuestas.append("") }
                    draft.respuestas[index] = value
                }
            }
        )
    }

    private func appendOrder(_ stepId: String) {
        update { $0.orden.append(stepId) }
    }

    private func moveOrder(from source: Int, to destination: Int) {
        update { draft in
            guard draft.orden.indices.contains(source), draft.orden.indices.contains(destination) else { return }
            draft.orden.swapAt(source, destination)
        }
    }

    private func removeOrderEntry(at index: Int) {
        update { draft in
            guard draft.orden.indices.contains(index) else { return }
            draft.orden.remove(at: index)
        }
    }

    private func update(_ mutation: (inout PruebaResponseDraft) -> Void) {
        guard !isDisabled, incompatibilityMessage == nil,
              var updated = response ?? PruebaResponseDraft.empty(for: item) else { return }
        mutation(&updated)
        onChange(updated)
    }

    private func stepTitle(_ step: PruebaPaso) -> String {
        step.texto.isEmpty ? "Paso \(step.originalIndex + 1)" : step.texto
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func hasDuplicateIds(_ ids: [String]) -> Bool {
        let nonEmpty = ids.filter { !$0.isEmpty }
        return nonEmpty.count != Set(nonEmpty).count
    }
}

private struct PruebaNullableScoreControl: View {
    let title: String
    let value: Double?
    let maximum: Double
    let isDisabled: Bool
    let onChange: (Double?) -> Void

    private var safeMaximum: Double {
        maximum.isFinite ? max(0, maximum) : 0
    }

    private var clampedValue: Double {
        guard let value, value.isFinite else { return 0 }
        return min(safeMaximum, max(0, value))
    }

    private var step: Double {
        safeMaximum <= 2 ? 0.1 : 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if value != nil {
                HStack(spacing: 8) {
                    Stepper(
                        value: Binding(
                            get: { clampedValue },
                            set: { onChange(min(safeMaximum, max(0, $0))) }
                        ),
                        in: 0...safeMaximum,
                        step: step
                    ) {
                        Text("\(formatted(clampedValue)) / \(formatted(safeMaximum)) pts")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .disabled(isDisabled || safeMaximum == 0)

                    Button {
                        onChange(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .accessibilityLabel("Quitar puntaje")
                }

                if let value, (!value.isFinite || value < 0 || value > safeMaximum) {
                    Label("El valor heredado est\u{00E1} fuera de rango; solo se normalizar\u{00E1} si modificas este control.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Button {
                    onChange(0)
                } label: {
                    Label("Asignar puntaje", systemImage: "plus.circle")
                        .font(.caption.weight(.bold))
                }
                .disabled(isDisabled || safeMaximum == 0)
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
