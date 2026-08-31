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
    @AppStorage(DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
    private var alwaysHiddenEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowDividers) private var showDividers = false
    @AppStorage(DefaultsKey.menuBarOrganizerPresentationMode) private var presentationMode =
        MenuBarOrganizerPresentationMode.automatic.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerAutoRehidePolicy) private var autoRehidePolicy =
        MenuBarRehidePolicy.afterSeconds(MenuBarRehidePolicy.defaultDelay).storageValue
    @AppStorage(DefaultsKey.menuBarOrganizerCustomRehideSeconds) private var customRehideSeconds =
        MenuBarRehidePolicy.defaultDelay
    @AppStorage(DefaultsKey.menuBarOrganizerHoverRevealEnabled) private var hoverReveal = false
    @AppStorage(DefaultsKey.menuBarOrganizerEmptyAreaRevealEnabled) private var emptyAreaReveal = false
    @AppStorage(DefaultsKey.menuBarOrganizerScrollRevealEnabled) private var scrollReveal = false
    @AppStorage(DefaultsKey.menuBarOrganizerSpacingPreset) private var spacingPreset =
        MenuBarSpacingPreset.standard.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerCustomSpacing) private var customSpacing =
        MenuBarSpacingPreset.standard.defaultValue
    @AppStorage(DefaultsKey.menuBarOrganizerSecondaryBarPinned) private var secondaryBarPinned = false
    @State private var editingBegun = false

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    private var advancedText: MenuBarOrganizerAdvancedStrings {
        FeatureStrings.menuBarOrganizerAdvanced(l10n.language)
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
                conflictSection
                permissionSection
                if service.isRunning {
                    if !setupComplete {
                        setupSection
                    }
                    editorSection
                    behaviorSection
                    advancedBehaviorSection
                }
            }

            Section {
                Text(text.attribution)
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
            endEditingIfNeeded()
        }
        .onChange(of: enabled) { _, _ in
            service.syncWithPreferences()
            updateEditingSession()
        }
        .onChange(of: service.isRunning) { _, _ in
            updateEditingSession()
        }
        .onChange(of: preferenceSignature) { _, _ in
            service.syncWithPreferences()
        }
    }

    @ViewBuilder
    private var conflictSection: some View {
        if !service.conflictingManagers.isEmpty {
            Section {
                Label(text.conflictTitle, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(
                    format: text.conflictFormat,
                    service.conflictingManagers.map(\.name).joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(text.retry) { service.retryStart() }
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if service.conflictingManagers.isEmpty, !permissions.accessibility {
            Section {
                PermissionRow(kind: .accessibility)
                Text(text.accessibilityCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupSection: some View {
        Section {
            Label(text.setupTitle, systemImage: "menubar.rectangle")
                .font(.headline)
            Text(text.setupCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(text.finishSetup) {
                setupComplete = true
                service.completeSetup()
                editingBegun = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.items.isEmpty)
        }
    }

    private var editorSection: some View {
        Section {
            HStack {
                Button(text.refresh) { service.refresh() }
                Button(text.undo) { service.undoLastMove() }
                    .disabled(!service.canUndo)
                Spacer()
                Button(advancedText.search) { service.openSearch() }
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
            if service.capabilities.unresolvedItemCount > 0 {
                Label(String(
                    format: text.unresolvedCountFormat,
                    service.capabilities.unresolvedItemCount),
                      systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !service.capabilities.automaticEditorAvailable {
                Label(text.automaticMoveUnavailable,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
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

    private var behaviorSection: some View {
        Section {
            Toggle(text.alwaysHiddenToggle, isOn: $alwaysHiddenEnabled)
            Toggle(text.showDividers, isOn: $showDividers)
            Picker(text.presentationTitle, selection: $presentationMode) {
                Text(text.presentationAutomatic)
                    .tag(MenuBarOrganizerPresentationMode.automatic.rawValue)
                Text(text.presentationMenuBar)
                    .tag(MenuBarOrganizerPresentationMode.menuBar.rawValue)
                Text(text.presentationSecondary)
                    .tag(MenuBarOrganizerPresentationMode.secondaryBar.rawValue)
            }
            .pickerStyle(.segmented)
            Text(text.presentationCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(text.behaviorTitle)
        }
    }

    private var advancedBehaviorSection: some View {
        Section {
            Picker(advancedText.autoRehide, selection: rehideSelection) {
                Text(advancedText.rehideNever).tag(MenuBarRehidePolicy.never.storageValue)
                Text(advancedText.rehideClickOutside).tag(MenuBarRehidePolicy.clickOutside.storageValue)
                ForEach(MenuBarRehidePolicy.allowedDelays, id: \.self) { seconds in
                    Text(String(format: advancedText.rehideSeconds, seconds))
                        .tag(MenuBarRehidePolicy.afterSeconds(seconds).storageValue)
                }
                Text(advancedText.rehideCustom).tag("custom")
            }
            if isCustomRehide {
                TextField(advancedText.rehideCustom, value: $customRehideSeconds, format: .number)
                    .onChange(of: customRehideSeconds) { _, value in
                        customRehideSeconds = MenuBarRehidePolicy.sanitizeDelay(value)
                        autoRehidePolicy = MenuBarRehidePolicy.afterSeconds(customRehideSeconds).storageValue
                    }
            }
            Toggle(advancedText.hoverReveal, isOn: $hoverReveal)
            Toggle(advancedText.emptyAreaReveal, isOn: $emptyAreaReveal)
            Toggle(advancedText.scrollReveal, isOn: $scrollReveal)
            Picker(advancedText.spacing, selection: $spacingPreset) {
                Text(advancedText.spacingCompact).tag(MenuBarSpacingPreset.compact.rawValue)
                Text(advancedText.spacingStandard).tag(MenuBarSpacingPreset.standard.rawValue)
                Text(advancedText.spacingSpacious).tag(MenuBarSpacingPreset.spacious.rawValue)
                Text(advancedText.spacingCustom).tag(MenuBarSpacingPreset.custom.rawValue)
            }
            if spacingPreset == MenuBarSpacingPreset.custom.rawValue {
                Slider(value: $customSpacing,
                       in: MenuBarOrganizerAdvancedSupport.minimumSpacing...MenuBarOrganizerAdvancedSupport.maximumSpacing,
                       step: 1) {
                    Text(advancedText.customSpacing)
                }
                Text(String(format: "%.0f px", customSpacing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(advancedText.pinned, isOn: $secondaryBarPinned)
        } header: {
            Text(advancedText.title)
        }
    }

    private var preferenceSignature: String {
        "\(alwaysHiddenEnabled)|\(showDividers)|\(presentationMode)|\(autoRehidePolicy)|\(customRehideSeconds)|\(hoverReveal)|\(emptyAreaReveal)|\(scrollReveal)|\(spacingPreset)|\(customSpacing)|\(secondaryBarPinned)"
    }

    private var isCustomRehide: Bool {
        guard case .afterSeconds(let seconds) = MenuBarRehidePolicy.fromStorage(autoRehidePolicy)
        else { return false }
        return !MenuBarRehidePolicy.allowedDelays.contains(seconds)
    }

    private var rehideSelection: Binding<String> {
        Binding(
            get: { isCustomRehide ? "custom" : autoRehidePolicy },
            set: { value in
                autoRehidePolicy = value == "custom"
                    ? MenuBarRehidePolicy.afterSeconds(customRehideSeconds).storageValue
                    : value
            })
    }

    private func organizerLane(_ section: MenuBarOrganizerSection,
                               title: String) -> some View {
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
                            .onDrop(
                                of: [UTType.text],
                                delegate: MenuBarOrganizerDropDelegate(
                                    section: section,
                                    target: item.id,
                                    service: service))
                            .contextMenu {
                                sectionMoveButton(for: item,
                                                  to: .visible,
                                                  title: text.visible)
                                sectionMoveButton(for: item,
                                                  to: .hidden,
                                                  title: text.hidden)
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
            .onDrop(
                of: [UTType.text],
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
        if enabled, service.isRunning, !editingBegun {
            service.beginEditing()
            editingBegun = true
        } else if (!enabled || !service.isRunning), editingBegun {
            service.endEditing()
            editingBegun = false
        }
    }

    private func endEditingIfNeeded() {
        guard editingBegun else { return }
        service.endEditing()
        editingBegun = false
    }
}

private struct MenuBarOrganizerEditorItem: View {
    @ObservedObject private var l10n = L10n.shared
    let item: ManagedMenuBarItem

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    var body: some View {
        HStack(spacing: 5) {
            MenuBarOrganizerItemIcon(item: item, size: 18)
            Text(item.sourceName.isEmpty ? item.title : item.sourceName)
                .font(.caption)
                .lineLimit(1)
            if item.identityState == .provisional {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if !item.isMovable {
                Image(systemName: "lock.fill").font(.caption2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .help(item.identityState == .provisional
              ? text.unresolvedItem
              : (item.isProtected ? text.protectedItem : item.displayName))
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
                guard let source = service.items.first(where: {
                    $0.id.storageValue == raw
                }), source.isMovable
                else { return }
                service.move(itemID: source.id, before: target, to: section)
            }
        }
        return true
    }
}
