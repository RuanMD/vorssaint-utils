// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct MenuBarOrganizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @ObservedObject private var permissions = Permissions.shared

    @AppStorage(DefaultsKey.menuBarOrganizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerSetupComplete) private var setupComplete = false
    @AppStorage(DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) private var alwaysHiddenEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowDividers) private var showDividers = false
    @AppStorage(DefaultsKey.menuBarOrganizerCapturePreviews) private var capturePreviews = true
    @AppStorage(DefaultsKey.menuBarOrganizerPresentationMode) private var presentationMode =
        MenuBarOrganizerPresentationMode.menuBar.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerRehideMode) private var rehideMode =
        MenuBarOrganizerRehideMode.afterDelay.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerRehideDelay) private var rehideDelay = 10
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnHover) private var showOnHover = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnEmptyClick) private var showOnEmptyClick = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnScroll) private var showOnScroll = false
    @AppStorage(DefaultsKey.menuBarOrganizerSmartNotchMode) private var smartNotchMode = true
    @AppStorage(DefaultsKey.menuBarOrganizerToggleShortcutEnabled) private var toggleShortcutEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerAlwaysShortcutEnabled) private var alwaysShortcutEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerSearchShortcutEnabled) private var searchShortcutEnabled = false

    @State private var editingBegun = false

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(text.pageTitle)
            }

            if enabled {
                if !setupComplete {
                    Section {
                        Label(text.setupTitle, systemImage: "menubar.rectangle")
                            .font(.headline)
                        Text(text.setupCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(text.finishSetup) {
                            setupComplete = true
                            service.completeSetup()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                permissionSection
                editorSection
                presetsSection
                behaviorSections
            }

            Section {
                Text(text.inspiredByIce)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.syncWithPreferences()
            updateEditingSession()
        }
        .onDisappear {
            if editingBegun {
                service.endEditing()
                editingBegun = false
            }
        }
        .onChange(of: enabled) { _, _ in
            service.syncWithPreferences()
            updateEditingSession()
        }
        .onChange(of: alwaysHiddenEnabled) { _, _ in service.syncWithPreferences() }
        .onChange(of: showDividers) { _, _ in service.syncWithPreferences() }
        .onChange(of: capturePreviews) { _, _ in service.refresh() }
        .onChange(of: presentationMode) { _, _ in service.syncWithPreferences() }
        .onChange(of: rehideMode) { _, _ in service.syncWithPreferences() }
        .onChange(of: rehideDelay) { _, value in
            let sanitized = MenuBarOrganizerSupport.sanitizedRehideDelay(value)
            if sanitized != value { rehideDelay = sanitized }
            service.syncWithPreferences()
        }
        .onChange(of: showOnHover) { _, _ in service.syncWithPreferences() }
        .onChange(of: showOnEmptyClick) { _, _ in service.syncWithPreferences() }
        .onChange(of: showOnScroll) { _, _ in service.syncWithPreferences() }
        .onChange(of: smartNotchMode) { _, _ in service.syncWithPreferences() }
        .onChange(of: toggleShortcutEnabled) { _, _ in service.syncWithPreferences() }
        .onChange(of: alwaysShortcutEnabled) { _, _ in service.syncWithPreferences() }
        .onChange(of: searchShortcutEnabled) { _, _ in service.syncWithPreferences() }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !permissions.accessibility || (capturePreviews && !permissions.screenRecording) {
            Section {
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                    Text(text.accessibilityCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if capturePreviews, !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                    Text(text.screenRecordingCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !service.capabilities.automaticEditorAvailable {
                    Label(text.automaticMoveUnavailable, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var editorSection: some View {
        Section {
            HStack {
                Button(text.refresh) { service.refresh() }
                Button(text.undo) { service.undoLastMove() }
                    .disabled(!service.canUndo)
                Spacer()
                Button(text.search) { service.showSearch() }
                Button(text.secondaryBar) { service.showSecondaryBar() }
            }

            organizerLane(.visible, title: text.visible)
            organizerLane(.hidden, title: text.hidden)
            if alwaysHiddenEnabled {
                organizerLane(.alwaysHidden, title: text.alwaysHidden)
            }

            Text(text.dragHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.manualHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = service.operationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .onTapGesture { service.clearOperationMessage() }
            }
        } header: {
            Text(text.sectionsTitle)
        }
    }

    private var presetsSection: some View {
        Section {
            Text(text.presetsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(MenuBarOrganizerPresetSlot.allCases) { slot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presetTitle(slot))
                        if let preset = service.presets[slot] {
                            Text(preset.savedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(text.presetUnsaved)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button(text.presetSave) { service.savePreset(slot: slot) }
                    Button(text.presetApply) { service.applyPreset(slot: slot) }
                        .disabled(service.presets[slot] == nil)
                    Button(text.presetClear, role: .destructive) {
                        service.clearPreset(slot: slot)
                    }
                    .disabled(service.presets[slot] == nil)
                }
            }
        } header: {
            Text(text.presetsTitle)
        }
    }

    @ViewBuilder
    private var behaviorSections: some View {
        Section(text.sectionsTitle) {
            Toggle(text.alwaysHiddenToggle, isOn: $alwaysHiddenEnabled)
            Toggle(text.showDividers, isOn: $showDividers)
            Toggle(text.capturePreviews, isOn: $capturePreviews)
        }

        Section(text.presentationTitle) {
            Picker(text.presentationTitle, selection: $presentationMode) {
                Text(text.presentationAutomatic).tag(MenuBarOrganizerPresentationMode.automatic.rawValue)
                Text(text.presentationMenuBar).tag(MenuBarOrganizerPresentationMode.menuBar.rawValue)
                Text(text.presentationSecondary).tag(MenuBarOrganizerPresentationMode.secondaryBar.rawValue)
            }
            .pickerStyle(.segmented)
        }

        Section(text.rehideTitle) {
            Picker(text.rehideTitle, selection: $rehideMode) {
                Text(text.rehideNever).tag(MenuBarOrganizerRehideMode.never.rawValue)
                Text(text.rehideDelay).tag(MenuBarOrganizerRehideMode.afterDelay.rawValue)
                Text(text.rehideFocusedApp).tag(MenuBarOrganizerRehideMode.focusedApp.rawValue)
            }
            if MenuBarOrganizerRehideMode.sanitized(rehideMode) == .afterDelay {
                Picker(text.rehideDelay, selection: $rehideDelay) {
                    ForEach(MenuBarOrganizerSupport.allowedRehideDelays, id: \.self) {
                        Text(String(format: text.delayFormat, $0)).tag($0)
                    }
                }
            }
        }

        Section(text.triggersTitle) {
            Toggle(text.showOnHover, isOn: $showOnHover)
            Toggle(text.showOnEmptyClick, isOn: $showOnEmptyClick)
            Toggle(text.showOnScroll, isOn: $showOnScroll)
            Toggle(text.smartNotchMode, isOn: $smartNotchMode)
            Text(text.smartNotchCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section(text.shortcutsTitle) {
            shortcutRow(title: text.toggleHiddenShortcut,
                        enabled: $toggleShortcutEnabled,
                        role: .menuBarOrganizerToggle)
            shortcutRow(title: text.toggleAlwaysShortcut,
                        enabled: $alwaysShortcutEnabled,
                        role: .menuBarOrganizerAlways)
                .disabled(!alwaysHiddenEnabled)
            shortcutRow(title: text.searchShortcut,
                        enabled: $searchShortcutEnabled,
                        role: .menuBarOrganizerSearch)
            if service.hotkeyRegistrationFailed {
                Text(L10n.shared.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func shortcutRow(title: String,
                             enabled: Binding<Bool>,
                             role: GlobalShortcutRole) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: enabled)
            ShortcutPreferenceRow(role: role, isEnabled: enabled.wrappedValue) {
                service.syncWithPreferences()
            }
            .disabled(!enabled.wrappedValue)
        }
    }

    private func presetTitle(_ slot: MenuBarOrganizerPresetSlot) -> String {
        switch slot {
        case .work: return text.presetWork
        case .home: return text.presetHome
        case .presenting: return text.presetPresenting
        case .minimal: return text.presetMinimal
        }
    }

    private func organizerLane(_ section: MenuBarOrganizerSection, title: String) -> some View {
        let laneItems = MenuBarOrganizerSupport.orderedItems(service.items, in: section)
        return VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if laneItems.isEmpty {
                        Text(text.emptySection)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 180, minHeight: 38)
                    }
                    ForEach(laneItems) { item in
                        MenuBarOrganizerEditorItem(item: item)
                            .onDrag {
                                NSItemProvider(object: item.id.storageValue as NSString)
                            }
                            .onDrop(of: [UTType.text],
                                    delegate: MenuBarOrganizerDropDelegate(
                                        section: section,
                                        target: item.id,
                                        service: service))
                            .contextMenu {
                                sectionMoveButton(for: item, to: .visible, title: text.visible)
                                sectionMoveButton(for: item, to: .hidden, title: text.hidden)
                                if alwaysHiddenEnabled {
                                    sectionMoveButton(for: item,
                                                      to: .alwaysHidden,
                                                      title: text.alwaysHidden)
                                }
                            }
                    }
                }
                .padding(7)
            }
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16)))
            .onDrop(of: [UTType.text],
                    delegate: MenuBarOrganizerDropDelegate(
                        section: section,
                        target: nil,
                        service: service))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sectionMoveButton(for item: ManagedMenuBarItem,
                                   to section: MenuBarOrganizerSection,
                                   title: String) -> some View {
        Button {
            service.move(itemID: item.id, before: nil, to: section)
        } label: {
            Label(title, systemImage: section == .visible
                  ? "eye"
                  : (section == .hidden ? "eye.slash" : "lock"))
        }
        .disabled(!item.isMovable || item.section == section)
    }

    private func updateEditingSession() {
        if enabled, !editingBegun {
            service.beginEditing()
            editingBegun = true
        } else if !enabled, editingBegun {
            service.endEditing()
            editingBegun = false
        }
    }
}

private struct MenuBarOrganizerEditorItem: View {
    let item: ManagedMenuBarItem

    var body: some View {
        HStack(spacing: 5) {
            MenuBarOrganizerItemIcon(item: item, size: 18)
            Text(item.ownerName.isEmpty ? item.title : item.ownerName)
                .font(.caption)
                .lineLimit(1)
            if !item.isMovable {
                Image(systemName: "lock.fill").font(.caption2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .help(item.displayName)
        .opacity(item.isMovable ? 1 : 0.62)
    }
}

private struct MenuBarOrganizerDropDelegate: DropDelegate {
    let section: MenuBarOrganizerSection
    let target: MenuBarItemIdentity?
    let service: MenuBarOrganizerService

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String else { return }
            DispatchQueue.main.async {
                guard let source = service.items.first(where: { $0.id.storageValue == raw }),
                      source.isMovable
                else { return }
                service.move(itemID: source.id, before: target, to: section)
            }
        }
        return true
    }
}
