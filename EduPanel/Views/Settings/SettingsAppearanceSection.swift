import SwiftUI

struct SettingsAppearanceSection: View {
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    var body: some View {
        ProfileSection(title: "Apariencia", icon: "paintbrush.fill", hint: nil) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tema")
                        .profileFieldLabel()
                    Picker("Tema", selection: $appThemeRaw) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

struct SettingsTabBarSection: View {
    @AppStorage(TabBarPreferences.storageKey)
    private var visibleTabsRaw = TabBarPreferences.defaultValue

    private var selectedTabs: [AppTab] {
        TabBarPreferences.decode(visibleTabsRaw)
    }

    private var availableTabs: [AppTab] {
        AppTab.allCases.filter { !selectedTabs.contains($0) }
    }

    var body: some View {
        ProfileSection(title: "Barra inferior", icon: "rectangle.bottomthird.inset.filled", hint: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Elige entre 3 y 5 accesos. Usa las flechas para decidir el orden en que aparecerán.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(Array(selectedTabs.enumerated()), id: \.element.id) { index, tab in
                        selectedRow(tab, index: index)
                    }
                }

                if !availableTabs.isEmpty {
                    Divider()

                    Text("Otros accesos")
                        .profileFieldLabel()

                    VStack(spacing: 8) {
                        ForEach(availableTabs) { tab in
                            availableRow(tab)
                        }
                    }
                }

                Button {
                    save(TabBarPreferences.defaultTabs)
                } label: {
                    Label("Restaurar barra predeterminada", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.bold))
                }
                .buttonStyle(.borderless)
                .tint(EPTheme.primary)
                .disabled(selectedTabs == TabBarPreferences.defaultTabs)
            }
        }
    }

    private func selectedRow(_ tab: AppTab, index: Int) -> some View {
        HStack(spacing: 10) {
            tabIcon(tab, tint: EPTheme.primary)

            Text(tab.title)
                .font(.footnote.weight(.bold))

            Spacer(minLength: 6)

            Button {
                moveTab(from: index, offset: -1)
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .accessibilityLabel("Mover \(tab.title) hacia la izquierda")

            Button {
                moveTab(from: index, offset: 1)
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(index == selectedTabs.count - 1)
            .accessibilityLabel("Mover \(tab.title) hacia la derecha")

            Button {
                remove(tab)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(selectedTabs.count <= TabBarPreferences.minimumCount)
            .accessibilityLabel("Quitar \(tab.title) de la barra")
        }
        .padding(9)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func availableRow(_ tab: AppTab) -> some View {
        Button {
            add(tab)
        } label: {
            HStack(spacing: 10) {
                tabIcon(tab, tint: .secondary)

                Text(tab.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(EPTheme.primary)
            }
            .padding(9)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedTabs.count >= TabBarPreferences.maximumCount)
        .opacity(selectedTabs.count >= TabBarPreferences.maximumCount ? 0.5 : 1)
        .accessibilityHint(selectedTabs.count >= TabBarPreferences.maximumCount ? "Quita primero otro acceso" : "Agregar a la barra inferior")
    }

    private func tabIcon(_ tab: AppTab, tint: Color) -> some View {
        Image(systemName: tab.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func add(_ tab: AppTab) {
        guard selectedTabs.count < TabBarPreferences.maximumCount else { return }
        save(selectedTabs + [tab])
    }

    private func remove(_ tab: AppTab) {
        guard selectedTabs.count > TabBarPreferences.minimumCount else { return }
        save(selectedTabs.filter { $0 != tab })
    }

    private func moveTab(from index: Int, offset: Int) {
        let destination = index + offset
        guard selectedTabs.indices.contains(index), selectedTabs.indices.contains(destination) else { return }
        var tabs = selectedTabs
        tabs.swapAt(index, destination)
        save(tabs)
    }

    private func save(_ tabs: [AppTab]) {
        withAnimation(EPTheme.spring) {
            visibleTabsRaw = TabBarPreferences.encode(tabs)
        }
    }
}
