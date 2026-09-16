import SwiftUI
import Foundation
import PhotosUI
import UIKit

struct ContentView: View {
    @State private var document = SchematicDocument.loadLast()
    @State private var savedDocuments = SchematicDocument.loadAll()
    @State private var canvasOffset = CGSize.zero
    @State private var canvasScale: CGFloat = 1
    @State private var panStart = CGSize.zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var targetDragStartRoutes: [UUID: [CGPoint]] = [:]
    @State private var draggingTargetID: UUID?
    @State private var segmentDragStartOffsets: [UUID: CGFloat] = [:]
    @State private var selectedSegmentSectionIndex: Int?
    @State private var segmentDragStartPoints: [UUID: [CGPoint]] = [:]
    @State private var selectedTargetIDs: [UUID] = []
    @AppStorage("targetsPanelExpanded") private var targetsPanelExpanded = true
    @State private var selectedSegmentID: UUID?
    @State private var selectedSegmentIDs: Set<UUID> = []
    @State private var selectedConnectionSlots: [UUID: Int] = [:]
    @AppStorage("infoSelectorEnabled") private var infoSelectorEnabled = false
    @AppStorage("snapToGrid") private var snapToGrid = true
    private let linePadding: CGFloat = 16
    @State private var showLibrary = false
    @State private var showLineLibrary = false
    @State private var showTargetLibrary = false
    @State private var selectedLineDefinitionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var connectionDragStartAngles: [String: Double] = [:]
    @State private var editingConnectionPoints = false
    @State private var cloudStatus = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.055, green: 0.075, blue: 0.09)
                .ignoresSafeArea()

            GeometryReader { geometry in
                schematicCanvas(in: geometry.size)
            }

            palette
                .padding(.leading, 20)
                .padding(.top, 84)

            header

            if infoSelectorEnabled && hasSelection {
                inspector
                    .padding(.trailing, 20)
                    .padding(.top, 84)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if showLibrary {
                libraryPanel
                    .padding(.top, 84)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if showLineLibrary {
                lineLibraryPanel
                    .padding(.top, 84)
                    .padding(.leading, 205)
            }

            if showTargetLibrary {
                targetLibraryPanel
                    .padding(.top, 84)
                    .padding(.leading, 205)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: document) { _, _ in
            SchematicDocument.saveLast(document)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item, let targetID = selectedTargetIDs.first else { return }
            Task { await loadTargetImage(item, targetID: targetID) }
        }
        .onAppear { if snapToGrid { snapAllTargets() } }
        .onChange(of: snapToGrid) { _, enabled in if enabled { snapAllTargets() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Easy1Line")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(1.5)
                TextField("Schematic name", text: $document.name)
                    .font(.system(size: 12, weight: .medium))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 180)
                if !cloudStatus.isEmpty {
                    Text(cloudStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { snapToGrid.toggle() } label: {
                        Text(snapToGrid ? "Snap: On" : "Snap: Off")
                    }
                    .buttonStyle(EditorButtonStyle(isActive: snapToGrid))

                    Button { canvasScale = max(0.5, canvasScale - 0.25) } label: { Text("−") }
                        .buttonStyle(EditorButtonStyle())
                    Text("\(Int(canvasScale * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 46)
                        .foregroundStyle(.white.opacity(0.75))
                    Button { canvasScale = min(2.5, canvasScale + 0.25) } label: { Text("+") }
                        .buttonStyle(EditorButtonStyle())

                    Button { showLibrary.toggle() } label: { Text("Drawings") }
                        .buttonStyle(EditorButtonStyle(isActive: showLibrary))
                    Button { showLineLibrary.toggle() } label: { Text("Lines") }
                        .buttonStyle(EditorButtonStyle(isActive: showLineLibrary))
                    Button { showTargetLibrary.toggle() } label: { Text("Targets") }
                        .buttonStyle(EditorButtonStyle(isActive: showTargetLibrary))
                    Button { saveCurrent() } label: { Text("Save") }
                        .buttonStyle(EditorButtonStyle())
                    Button { Task { await saveToCloud() } } label: { Text("Cloud save") }
                        .buttonStyle(EditorButtonStyle())
                    Button { Task { await loadFromCloud() } } label: { Text("Cloud load") }
                        .buttonStyle(EditorButtonStyle())
                    Button { connectSelection() } label: { Text("Connect") }
                        .buttonStyle(EditorButtonStyle(isActive: canConnectSelection))
                        .disabled(!canConnectSelection)
                    Button { infoSelectorEnabled.toggle() } label: { Text("Info") }
                        .buttonStyle(EditorButtonStyle(isActive: infoSelectorEnabled))
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
        }

        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                    withAnimation(.easeInOut(duration: 0.2)) { targetsPanelExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if targetsPanelExpanded {
                        Text("TARGETS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.cyan)
                    }
                    Spacer()
                    Image(systemName: targetsPanelExpanded ? "chevron.left" : "chevron.right")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(targetsPanelExpanded ? "Collapse targets" : "Expand targets")

            if targetsPanelExpanded {
                ScrollView {
                    ForEach(TargetKind.palette) { kind in
                        PaletteItem(kind: kind)
                            .draggable(kind.rawValue)
                            .onTapGesture { addTarget(kind) }
                    }
                }
                .frame(maxHeight: 460)

                Divider().overlay(.white.opacity(0.12)).padding(.vertical, 4)

                Button { addTarget(.junction) } label: {
                    Label("Add junction", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)

                Text("Drag to place\nTap to add at center")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

            }
        }
        .padding(14)
        .frame(width: targetsPanelExpanded ? 170 : 52)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1) }
    }

    private func schematicCanvas(in size: CGSize) -> some View {
        ZStack {
            GridBackground()
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture {
                    selectedTargetIDs.removeAll()
                    selectedSegmentID = nil
                    selectedSegmentIDs.removeAll()
                }

            Canvas { context, _ in
                for segment in document.segments {
                    guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
                    let path = orthogonalPath(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                    if selectedSegmentIDs.contains(segment.id) {
                        context.stroke(path, with: .color(.cyan.opacity(0.35)), style: StrokeStyle(lineWidth: segment.displayWidth + 12, lineCap: .round, lineJoin: .round))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.displayWidth, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(false)

            ForEach(document.segments) { segment in
                if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                    let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                    ForEach(0..<(points.count - 1), id: \.self) { sectionIndex in
                        SegmentHitArea(path: sectionPath(from: points[sectionIndex], to: points[sectionIndex + 1]), isSelected: selectedSegmentIDs.contains(segment.id), isSectionSelected: selectedSegmentID == segment.id && selectedSegmentSectionIndex == sectionIndex, onDrag: { translation in
                            moveSegmentSection(segment.id, sectionIndex: sectionIndex, translation: CGSize(width: translation.width / canvasScale, height: translation.height / canvasScale))
                        }, onEndDrag: {
                            segmentDragStartPoints.removeValue(forKey: segment.id)
                        }) {
                            if selectedSegmentID == segment.id {
                                selectedSegmentSectionIndex = sectionIndex
                            } else {
                                selectedSegmentIDs = [segment.id]
                                selectedSegmentID = segment.id
                                selectedSegmentSectionIndex = nil
                            }
                            selectedTargetIDs.removeAll()
                        }
                    }
                }
            }

            ForEach(document.targets) { target in
                TargetView(
                    target: target,
                    isSelected: selectedTargetIDs.contains(target.id),
                    selectionOrder: selectedTargetIDs.count > 2 ? selectedTargetIDs.firstIndex(of: target.id).map { $0 + 1 } : nil,
                    isConnectionStart: selectedTargetIDs.contains(target.id),
                    connectedColor: connectedColor(for: target.id),
                    connectedColors: connectedColors(for: target.id),
                    occupiedSlots: occupiedSlots(for: target.id),
                    selectedSlots: selectedConnectionSlots[target.id].map { Set([$0]) } ?? [],
                    onSelectConnectionPoint: { slot in
                        selectConnectionPoint(targetID: target.id, slot: slot)
                    },
                    editingConnectionPoints: editingConnectionPoints && selectedTargetIDs.contains(target.id),
                    onMoveConnectionPoint: { slot, translation in
                        moveConnectionPoint(targetID: target.id, slot: slot, translation: CGSize(width: translation.width / canvasScale, height: translation.height / canvasScale))
                    },
                    onEndConnectionPointMove: { slot in
                        connectionDragStartAngles.removeValue(forKey: connectionDragKey(target.id, slot: slot))
                    }
                )
                .position(target.position)
                .gesture(targetDragGesture(for: target, canvasSize: size))
                .onTapGesture { targetTapped(target) }
            }

            if selectedTargetIDs.count >= 2,
               let lastSelectedID = selectedTargetIDs.last,
               let lastSelectedTarget = target(with: lastSelectedID) {
                Button {
                    connectSelection()
                } label: {
                    Text("Connect")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(EditorButtonStyle(isActive: true))
                .position(x: lastSelectedTarget.position.x + 86, y: lastSelectedTarget.position.y - 52)
                .zIndex(1000)
            }
        }
        .offset(canvasOffset)
        .scaleEffect(canvasScale, anchor: .center)
        .dropDestination(for: String.self) { items, location in
            guard let rawKind = items.first, let kind = TargetKind(rawValue: rawKind) else { return false }
            let point = CGPoint(x: location.x - canvasOffset.width, y: location.y - canvasOffset.height)
            addTarget(kind, at: point)
            if let id = document.targets.last?.id { splitSegmentIfNeeded(for: id) }
            return true
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                canvasOffset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
            }
            .onEnded { _ in panStart = canvasOffset }
    }

    private func targetDragGesture(for target: SchematicTarget, canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !editingConnectionPoints else { return }
                draggingTargetID = target.id
                guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
                if dragStartPositions[target.id] == nil {
                    dragStartPositions[target.id] = document.targets[index].position
                    captureAttachedRoutes(for: target.id)
                }
                guard let start = dragStartPositions[target.id] else { return }
                let proposedPosition = CGPoint(x: start.x + value.translation.width / canvasScale, y: start.y + value.translation.height / canvasScale)
                document.targets[index].position = snapToGrid ? snappedPosition(proposedPosition) : proposedPosition
                updateAttachedRoutes(for: target.id, translation: CGSize(width: document.targets[index].position.x - start.x, height: document.targets[index].position.y - start.y))
                selectedTargetIDs = [target.id]
                selectedSegmentID = nil
                selectedSegmentIDs.removeAll()
            }
            .onEnded { _ in
                dragStartPositions.removeValue(forKey: target.id)
                targetDragStartRoutes.removeAll()
                snapTarget(target.id, canvasSize: canvasSize)
                draggingTargetID = nil
            }
    }

    private func targetTapped(_ target: SchematicTarget) {
        if selectedTargetIDs.contains(target.id) {
            cycleConnectionPoint(for: target)
            return
        }
        selectTarget(target)
    }

    private func cycleConnectionPoint(for target: SchematicTarget) {
        guard target.kind != .junction else { return }
        let freeSlots = (0..<target.maxConnections).filter { !occupiedSlots(for: target.id).contains($0) }
        let cycleSlots = freeSlots.isEmpty ? Array(0..<target.maxConnections) : freeSlots
        guard !cycleSlots.isEmpty else { return }
        let currentSlot = selectedConnectionSlots[target.id]
        let nextIndex = currentSlot.flatMap { slot in cycleSlots.firstIndex(of: slot).map { ($0 + 1) % cycleSlots.count } } ?? 0
        selectedConnectionSlots[target.id] = cycleSlots[nextIndex]
    }

    private func selectTarget(_ target: SchematicTarget) {
        selectedConnectionSlots.removeAll()
        editingConnectionPoints = false
        if let selectedIndex = selectedTargetIDs.firstIndex(of: target.id) {
            selectedTargetIDs.remove(at: selectedIndex)
        } else {
            selectedTargetIDs.append(target.id)
        }
    }

    private func selectConnectionPoint(targetID: UUID, slot: Int) {
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        if !selectedTargetIDs.contains(targetID) {
            selectedTargetIDs.append(targetID)
        }
        selectedConnectionSlots[targetID] = slot
    }

    private func connectSelectedTargets() {
        let ids = Array(selectedTargetIDs)
        guard ids.count >= 2 else { return }
        for pairIndex in 0..<(ids.count - 1) {
            let startID = ids[pairIndex]
            let endID = ids[pairIndex + 1]
            guard let startSlot = selectedConnectionSlots[startID] ?? closestAvailableSlot(for: startID, to: endID), let endSlot = selectedConnectionSlots[endID] ?? closestAvailableSlot(for: endID, to: startID) else { continue }
            guard !occupiedSlots(for: startID).contains(startSlot), !occupiedSlots(for: endID).contains(endSlot) else { continue }
            guard !document.segments.contains(where: { ($0.startID == startID && $0.endID == endID) || ($0.startID == endID && $0.endID == startID) }) else { continue }
            let line = selectedLineDefinition ?? document.lineDefinitions.first ?? LineDefinition.defaultLine
            document.segments.append(SchematicSegment(startID: startID, endID: endID, startSlot: startSlot, endSlot: endSlot, name: line.name, colorHex: line.colorHex, wireSize: line.wireSize, material: line.material.rawValue, displayWidth: line.displayWidth, description: line.description))
        }
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
    }

    private var canConnectSelection: Bool {
        selectedTargetIDs.count >= 2 || (selectedTargetIDs.count == 1 && selectedSegmentIDs.count == 1)
    }

    private func connectSelection() {
        if selectedTargetIDs.count >= 2 {
            connectSelectedTargets()
        } else {
            connectSelectedTargetToLine()
        }
    }

    private func connectSelectedTargetToLine() {
        guard selectedTargetIDs.count == 1,
              let targetID = selectedTargetIDs.first,
              let segmentID = selectedSegmentIDs.first,
              let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }),
              let segmentIndex = document.segments.firstIndex(where: { $0.id == segmentID }),
              let start = target(with: document.segments[segmentIndex].startID),
              let end = target(with: document.segments[segmentIndex].endID),
              targetID != start.id,
              targetID != end.id else { return }

        let segment = document.segments[segmentIndex]
        let route = [start.position, CGPoint(x: (start.position.x + end.position.x) / 2, y: start.position.y), CGPoint(x: (start.position.x + end.position.x) / 2, y: end.position.y), end.position]
        let nearest = nearestPoint(on: route, to: document.targets[targetIndex].position).point
        let junction = SchematicTarget(kind: .junction, name: "Junction", position: nearest, maxConnections: 8, colorHex: TargetKind.junction.defaultColorHex)
        document.targets.append(junction)
        document.segments.remove(at: segmentIndex)
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: junction.id, startSlot: segment.startSlot, endSlot: 0, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, displayWidth: segment.displayWidth, description: segment.description), at: segmentIndex)
        document.segments.insert(SchematicSegment(startID: junction.id, endID: segment.endID, startSlot: 1, endSlot: segment.endSlot, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, displayWidth: segment.displayWidth, description: segment.description), at: segmentIndex + 1)
        let targetSlot = selectedConnectionSlots[targetID] ?? closestAvailableSlot(for: targetID, to: junction.id) ?? 0
        document.segments.append(SchematicSegment(startID: targetID, endID: junction.id, startSlot: targetSlot, endSlot: 2, name: "Connection", colorHex: "31D7E8", wireSize: "14 AWG", material: "Copper", displayWidth: 3, description: "Target connection"))
        selectedTargetIDs.removeAll()
        selectedSegmentIDs.removeAll()
        selectedSegmentID = nil
        selectedConnectionSlots.removeAll()
    }

    private func addTarget(_ kind: TargetKind, at point: CGPoint? = nil) {
        let rawPosition = point ?? CGPoint(x: 480 - canvasOffset.width, y: 330 - canvasOffset.height)
        let position = snappedPosition(rawPosition)
        document.targets.append(SchematicTarget(kind: kind, name: kind.title, position: position, maxConnections: kind == .junction ? 8 : 2, colorHex: kind.defaultColorHex))
        selectedTargetIDs = [document.targets.last!.id]
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        editingConnectionPoints = false
        selectedSegmentIDs.removeAll()
    }

    private func addTarget(from template: TargetDefinition) {
        let position = snappedPosition(CGPoint(x: 480 - canvasOffset.width, y: 330 - canvasOffset.height))
        document.targets.append(SchematicTarget(kind: template.kind, name: template.name, position: position, maxConnections: template.maxConnections, colorHex: template.colorHex, symbol: template.symbol, imageData: template.imageData, connectionAngles: template.connectionAngles, scale: template.scale, isCompact: template.isCompact))
        selectedTargetIDs = [document.targets.last!.id]
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        showTargetLibrary = false
    }

    private func saveTargetTemplate(_ target: SchematicTarget) {
        document.targetDefinitions.append(TargetDefinition(kind: target.kind, name: target.name, maxConnections: target.maxConnections, colorHex: target.colorHex, symbol: target.symbol, imageData: target.imageData, connectionAngles: target.connectionAngles, scale: target.scale, isCompact: target.isCompact))
    }

    private func duplicateTarget(_ target: SchematicTarget) {
        var copy = target
        copy.id = UUID()
        copy.name = "\(target.name) copy"
        copy.position = snappedPosition(CGPoint(x: target.position.x + 48, y: target.position.y + 48))
        document.targets.append(copy)
        selectedTargetIDs = [copy.id]
        selectedSegmentID = nil
    }

    private func saveCurrent() {
        if let index = savedDocuments.firstIndex(where: { $0.id == document.id }) { savedDocuments[index] = document } else { savedDocuments.append(document) }
        SchematicDocument.saveAll(savedDocuments)
        SchematicDocument.saveLast(document)
    }

    private func saveToCloud() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            let data = try JSONEncoder().encode(document)
            try await store.saveDrawing(id: document.id, name: document.name, data: data)
            cloudStatus = "Saved to cloud"
        } catch {
            cloudStatus = "Cloud save failed"
        }
    }

    private func loadFromCloud() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            guard let remote = try await store.loadDrawingData().first,
                  let loaded = try? JSONDecoder().decode(SchematicDocument.self, from: remote.data) else {
                cloudStatus = "No cloud drawings"
                return
            }
            document = loaded
            cloudStatus = "Loaded from cloud"
        } catch {
            cloudStatus = "Cloud load failed"
        }
    }

    private func newSchematic() {
        saveCurrent()
        document = SchematicDocument(name: "Untitled schematic")
        selectedTargetIDs.removeAll()
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        showLibrary = false
    }

    private func load(_ saved: SchematicDocument) {
        document = saved
        selectedTargetIDs.removeAll()
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        showLibrary = false
    }

    private func delete(_ saved: SchematicDocument) {
        savedDocuments.removeAll { $0.id == saved.id }
        SchematicDocument.saveAll(savedDocuments)
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SCHEMATICS").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { newSchematic() } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
            }
            ForEach(savedDocuments) { saved in
                HStack(spacing: 8) {
                    Button { load(saved) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(saved.name).font(.system(size: 13, weight: .semibold))
                            Text("\(saved.targets.count) targets · \(saved.segments.count) segments").font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button { delete(saved) } label: { Image(systemName: "trash") }.foregroundStyle(.red.opacity(0.75))
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            if savedDocuments.isEmpty { Text("No saved schematics yet").font(.caption).foregroundStyle(.white.opacity(0.4)) }
        }
        .padding(14)
        .frame(width: 270)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var lineLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LINE LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { document.lineDefinitions.append(.defaultLine) } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
            }
            ForEach(document.lineDefinitions) { line in
                Button {
                    selectedLineDefinitionID = line.id
                    if let selectedSegmentID {
                        applyLineDefinition(line, to: selectedSegmentID)
                    } else {
                        applyLineDefinition(line, to: selectedSegmentIDs)
                    }
                    showLineLibrary = false
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: line.colorHex)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name).font(.system(size: 13, weight: .semibold))
                            Text("\(line.material.rawValue) · \(line.wireSize) · \(line.displayWidth, specifier: "%.1f") pt").font(.caption2).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                        Spacer()
                        if selectedLineDefinitionID == line.id { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                    }
                }
                .buttonStyle(.plain)
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var targetLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TARGET LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { addTarget(.junction) } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
            }

            Text("PROJECT TARGETS").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.35))
            ForEach(document.targets) { target in
                Button {
                    selectedTargetIDs = [target.id]
                    selectedSegmentID = nil
                    selectedSegmentIDs.removeAll()
                    showTargetLibrary = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: target.symbol).foregroundStyle(Color(hex: target.colorHex))
                        Text(target.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(connectionCount(for: target.id)) / \(target.kind == .junction ? "∞" : "\(target.maxConnections)")")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(.white.opacity(0.12))
            Text("SAVED TARGET TYPES").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.35))
            ForEach(document.targetDefinitions) { template in
                Button { addTarget(from: template) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: template.symbol).foregroundStyle(Color(hex: template.colorHex))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.system(size: 12, weight: .semibold))
                            Text(template.kind.title).font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.cyan)
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedSegmentIDs.count > 1 {
                Text("LINES").inspectorLabel()
                Text("\(selectedSegmentIDs.count) lines selected").font(.headline)
                Button {
                    showLineLibrary = true
                } label: {
                    Label("Choose line type", systemImage: "list.bullet.rectangle")
                }
                Button(role: .destructive) {
                    document.segments.removeAll { selectedSegmentIDs.contains($0.id) }
                    selectedSegmentIDs.removeAll()
                    selectedSegmentID = nil
                } label: {
                    Label("Delete lines", systemImage: "trash")
                }
            } else if let segment = selectedSegment {
                Text("SEGMENT").inspectorLabel()
                TextField("Line name", text: segmentBinding(segment).name)
                    .textFieldStyle(.roundedBorder)
                ColorPicker("Line color", selection: segmentBinding(segment).color)
                TextField("Wire size", text: segmentBinding(segment).wireSize).textFieldStyle(.roundedBorder)
                Picker("Material", selection: segmentBinding(segment).material) {
                    ForEach(ConductorMaterial.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
                TextField("Description", text: segmentBinding(segment).description).textFieldStyle(.roundedBorder)
                Stepper("Display width: \(segment.displayWidth, specifier: "%.1f")", value: segmentBinding(segment).displayWidth, in: 1...20, step: 0.5)
                Button {
                    showLineLibrary = true
                } label: {
                    Label("Choose line type", systemImage: "list.bullet.rectangle")
                }
                Button {
                    document.lineDefinitions.append(LineDefinition(name: segment.name, colorHex: segment.colorHex, wireSize: segment.wireSize, material: ConductorMaterial(rawValue: segment.material) ?? .copper, displayWidth: segment.displayWidth, description: segment.description))
                } label: {
                    Label("Add to line library", systemImage: "plus.circle")
                }
                Button(role: .destructive) {
                    document.segments.removeAll { $0.id == segment.id }
                    selectedSegmentIDs.removeAll()
                    selectedSegmentID = nil
                } label: { Label("Delete line", systemImage: "trash") }
            } else if selectedTargetIDs.count == 1, let target = target(with: selectedTargetIDs.first!) {
                Text("TARGET").inspectorLabel()
                TextField("Target name", text: targetBinding(target).name).textFieldStyle(.roundedBorder)
                TextField("SF Symbol name", text: targetBinding(target).symbol)
                    .textFieldStyle(.roundedBorder)
                Button {
                    editingConnectionPoints.toggle()
                } label: {
                    Label(editingConnectionPoints ? "Done editing points" : "Edit connection points", systemImage: "point.3.connected.trianglepath.dotted")
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(target.imageData == nil ? "Upload image icon" : "Replace image icon", systemImage: "photo.badge.plus")
                }
                Button {
                    clearTargetImage(target)
                } label: {
                    Label("Use SF Symbol instead", systemImage: "sf.square")
                }
                .disabled(target.imageData == nil)
                if target.kind == .junction {
                    Text("Connections: Unlimited")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Stepper("Connections: \(target.maxConnections)", value: targetBinding(target).maxConnections, in: 0...32)
                    Stepper("Point rotation: \(target.connectionAngle, specifier: "%.0f")°", value: targetBinding(target).connectionAngle, in: 0...360, step: 15)
                }
                if target.kind != .junction { ColorPicker("Target color", selection: targetBinding(target).color) }
                Stepper("Size: \(target.scale, specifier: "%.1f")x", value: targetBinding(target).scale, in: 0.5...3, step: 0.1)
                Toggle("Compact target", isOn: targetBinding(target).isCompact)
                Button { duplicateTarget(target) } label: {
                    Label("Duplicate target", systemImage: "plus.square.on.square")
                }
                Button { saveTargetTemplate(target) } label: {
                    Label("Save as target type", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    document.segments.removeAll { $0.startID == target.id || $0.endID == target.id }
                    document.targets.removeAll { $0.id == target.id }
                    selectedTargetIDs.removeAll()
                } label: { Label("Delete target", systemImage: "trash") }
            } else {
                Text("MULTI-SELECT").inspectorLabel()
                Text("\(selectedTargetIDs.count) targets selected").font(.headline)
                Text("Tap Connect to link them in order.").font(.caption).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var hasSelection: Bool { !selectedTargetIDs.isEmpty || !selectedSegmentIDs.isEmpty }
    private var selectedSegment: SchematicSegment? { guard let selectedSegmentID else { return nil }; return document.segments.first { $0.id == selectedSegmentID } }
    private func target(with id: UUID) -> SchematicTarget? { document.targets.first { $0.id == id } }
    private func connectionCount(for id: UUID) -> Int { document.segments.filter { $0.startID == id || $0.endID == id }.count }
    private func connectedColor(for id: UUID) -> Color { document.segments.first(where: { $0.startID == id || $0.endID == id }).map { $0.color } ?? .cyan }
    private func connectedColors(for id: UUID) -> [Color] {
        var colors: [Color] = []
        for segment in document.segments where segment.startID == id || segment.endID == id {
            if !colors.contains(where: { $0.hexString == segment.color.hexString }) {
                colors.append(segment.color)
            }
        }
        return colors
    }
    private func occupiedSlots(for id: UUID) -> Set<Int> {
        var slots = Set<Int>()
        for segment in document.segments {
            if segment.startID == id { slots.insert(segment.startSlot ?? 0) }
            if segment.endID == id { slots.insert(segment.endSlot ?? 0) }
        }
        return slots
    }

    private func firstEmptySlot(for id: UUID) -> Int? {
        guard let target = target(with: id) else { return nil }
        if target.kind == .junction {
            return document.segments.reduce(into: 0) { nextSlot, segment in
                if segment.startID == id || segment.endID == id { nextSlot += 1 }
            }
        }
        let occupied = occupiedSlots(for: id)
        return (0..<target.maxConnections).first { !occupied.contains($0) }
    }

    private func closestAvailableSlot(for id: UUID, to otherID: UUID) -> Int? {
        guard let sourceTarget = target(with: id), let otherTarget = target(with: otherID) else { return nil }
        guard sourceTarget.kind != .junction else { return firstEmptySlot(for: id) }
        let occupied = occupiedSlots(for: id)
        return (0..<sourceTarget.maxConnections)
            .filter { !occupied.contains($0) }
            .min { lhs, rhs in
                let lhsPoint = connectionPoint(for: sourceTarget, slot: lhs)
                let rhsPoint = connectionPoint(for: sourceTarget, slot: rhs)
                let lhsDistance = hypot(lhsPoint.x - otherTarget.position.x, lhsPoint.y - otherTarget.position.y)
                let rhsDistance = hypot(rhsPoint.x - otherTarget.position.x, rhsPoint.y - otherTarget.position.y)
                return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
            }
    }

    private func connectionPoint(for target: SchematicTarget, slot: Int?) -> CGPoint {
        let slotIndex = slot ?? 0
        let angle = connectionAngle(for: target, slot: slotIndex) * Double.pi / 180
        let radius: CGFloat = target.kind == .junction ? 0 : (target.isCompact ? 24 : 42) * target.scale
        return CGPoint(x: target.position.x + radius * CGFloat(cos(angle)), y: target.position.y + radius * CGFloat(sin(angle)))
    }

    private func connectionAngle(for target: SchematicTarget, slot: Int) -> Double {
        if target.connectionAngles.indices.contains(slot) { return target.connectionAngles[slot] }
        return (360 * Double(slot) / Double(max(target.maxConnections, 1))) + target.connectionAngle - 90
    }

    private func connectionDragKey(_ targetID: UUID, slot: Int) -> String { "\(targetID.uuidString)-\(slot)" }

    private func moveConnectionPoint(targetID: UUID, slot: Int, translation: CGSize) {
        guard let index = document.targets.firstIndex(where: { $0.id == targetID }), document.targets[index].kind != .junction else { return }
        let target = document.targets[index]
        let key = connectionDragKey(targetID, slot: slot)
        if connectionDragStartAngles[key] == nil { connectionDragStartAngles[key] = connectionAngle(for: target, slot: slot) }
        let startAngle = (connectionDragStartAngles[key] ?? 0) * Double.pi / 180
        let radius: CGFloat = (target.isCompact ? 24 : 42) * target.scale
        let startPoint = CGPoint(x: radius * CGFloat(cos(startAngle)), y: radius * CGFloat(sin(startAngle)))
        let point = CGPoint(x: startPoint.x + translation.width, y: startPoint.y + translation.height)
        let angle = atan2(point.y, point.x) * 180 / Double.pi
        if document.targets[index].connectionAngles.count < document.targets[index].maxConnections {
            document.targets[index].connectionAngles = (0..<document.targets[index].maxConnections).map { connectionAngle(for: target, slot: $0) }
        }
        document.targets[index].connectionAngles[slot] = angle
    }

    private func snapTarget(_ id: UUID, canvasSize: CGSize) {
        guard let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
        guard snapToGrid else {
            document.targets[index].position.x = min(max(document.targets[index].position.x, 180), max(180, canvasSize.width - 80))
            document.targets[index].position.y = min(max(document.targets[index].position.y, 120), max(120, canvasSize.height - 80))
            return
        }
        document.targets[index].position = snappedPosition(document.targets[index].position)
        let gridSize: CGFloat = 32
        let minimumX = ceil(180 / gridSize) * gridSize
        let minimumY = ceil(120 / gridSize) * gridSize
        let maximumX = floor(max(180, canvasSize.width - 80) / gridSize) * gridSize
        let maximumY = floor(max(120, canvasSize.height - 80) / gridSize) * gridSize
        document.targets[index].position.x = min(max(document.targets[index].position.x, minimumX), max(minimumX, maximumX))
        document.targets[index].position.y = min(max(document.targets[index].position.y, minimumY), max(minimumY, maximumY))
    }

    private func snapAllTargets() {
        for index in document.targets.indices {
            document.targets[index].position = snappedPosition(document.targets[index].position)
        }
    }

    private func captureAttachedRoutes(for targetID: UUID) {
        targetDragStartRoutes.removeAll()
        for segment in document.segments where segment.startID == targetID || segment.endID == targetID {
            guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
            targetDragStartRoutes[segment.id] = points
        }
    }

    private func updateAttachedRoutes(for targetID: UUID, translation: CGSize) {
        for index in document.segments.indices where document.segments[index].startID == targetID || document.segments[index].endID == targetID {
            let segment = document.segments[index]
            guard var points = targetDragStartRoutes[segment.id], points.count > 2 else { continue }
            if segment.startID == targetID {
                points[0].x += translation.width
                points[0].y += translation.height
                points[1].x += translation.width
                points[1].y += translation.height
            } else {
                let last = points.count - 1
                points[last].x += translation.width
                points[last].y += translation.height
                points[last - 1].x += translation.width
                points[last - 1].y += translation.height
            }
            document.segments[index].routePoints = points
        }
    }

    private func moveSegmentSection(_ id: UUID, sectionIndex: Int, translation: CGSize) {
        guard selectedSegmentIDs.contains(id), selectedSegmentID == id, selectedSegmentSectionIndex == sectionIndex else { return }
        guard let index = document.segments.firstIndex(where: { $0.id == id }) else { return }
        guard let start = target(with: document.segments[index].startID), let end = target(with: document.segments[index].endID) else { return }
        if segmentDragStartPoints[id] == nil {
            segmentDragStartPoints[id] = orthogonalPoints(for: document.segments[index], from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
        }
        guard var points = segmentDragStartPoints[id], sectionIndex + 1 < points.count else { return }
        guard sectionIndex > 0, sectionIndex + 1 < points.count - 1 else { return }
        let isVertical = abs(points[sectionIndex].x - points[sectionIndex + 1].x) < 0.5
        let delta = isVertical ? translation.width : translation.height
        let base = isVertical ? points[sectionIndex].x : points[sectionIndex].y
        let movedCoordinate = snapToGrid ? snappedCoordinate(base + delta) : base + delta
        if isVertical {
            points[sectionIndex].x = movedCoordinate
            points[sectionIndex + 1].x = movedCoordinate
        } else {
            points[sectionIndex].y = movedCoordinate
            points[sectionIndex + 1].y = movedCoordinate
        }
        document.segments[index].routePoints = points
        selectedTargetIDs.removeAll()
    }

    private func snappedPosition(_ position: CGPoint) -> CGPoint {
        guard snapToGrid else { return position }
        let gridSize: CGFloat = 32
        return CGPoint(x: (position.x / gridSize).rounded() * gridSize, y: (position.y / gridSize).rounded() * gridSize)
    }

    private func snappedOffset(_ offset: CGFloat) -> CGFloat {
        let gridSize: CGFloat = 32
        return (offset / gridSize).rounded() * gridSize
    }

    private func snappedCoordinate(_ coordinate: CGFloat) -> CGFloat {
        let gridSize: CGFloat = 32
        return (coordinate / gridSize).rounded() * gridSize
    }

    private func orthogonalPath(for segment: SchematicSegment, from startTarget: SchematicTarget, to endTarget: SchematicTarget, avoiding obstacles: [SchematicTarget]) -> Path {
        let points = orthogonalPoints(for: segment, from: startTarget, to: endTarget, avoiding: obstacles)
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func orthogonalPoints(for segment: SchematicSegment, from startTarget: SchematicTarget, to endTarget: SchematicTarget, avoiding obstacles: [SchematicTarget]) -> [CGPoint] {
        if segment.routePoints.count > 1 {
            return segment.routePoints
        }
        let laneOffset: CGFloat = 0
        let start = offsetConnectionPoint(for: startTarget, slot: segment.startSlot, toward: endTarget, by: laneOffset)
        let end = offsetConnectionPoint(for: endTarget, slot: segment.endSlot, toward: startTarget, by: laneOffset)
        let escapeStart = escapePoint(for: startTarget, slot: startTargetSlot(startTarget, point: start), toward: endTarget)
        let escapeEnd = escapePoint(for: endTarget, slot: endTargetSlot(endTarget, point: end), toward: startTarget)
        let routeObstacles = (draggingTargetID == nil ? obstacles : []) + [startTarget, endTarget]
        let padding = CGFloat(linePadding)
        let rectangles = routeObstacles.map { obstacleRect(for: $0).insetBy(dx: -padding, dy: -padding) }
        var xCandidates = [escapeStart.x, escapeEnd.x, (escapeStart.x + escapeEnd.x) / 2]
        var yCandidates = [escapeStart.y, escapeEnd.y, (escapeStart.y + escapeEnd.y) / 2]
        for rectangle in rectangles {
            xCandidates.append(contentsOf: [rectangle.minX, rectangle.maxX])
            yCandidates.append(contentsOf: [rectangle.minY, rectangle.maxY])
        }
        let uniqueX = Array(Set(xCandidates)).sorted { lhs, rhs in
            let lhsDistance = abs(lhs - start.x)
            let rhsDistance = abs(rhs - start.x)
            return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
        }
        let uniqueY = Array(Set(yCandidates)).sorted { lhs, rhs in
            let lhsDistance = abs(lhs - start.y)
            let rhsDistance = abs(rhs - start.y)
            return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
        }
        let candidates = uniqueX.map { [escapeStart, CGPoint(x: $0, y: escapeStart.y), CGPoint(x: $0, y: escapeEnd.y), escapeEnd] }
            + uniqueY.map { [escapeStart, CGPoint(x: escapeStart.x, y: $0), CGPoint(x: escapeEnd.x, y: $0), escapeEnd] }
        let safePath = candidates
            .filter { pointsAreClear($0, from: rectangles) }
            .min { pathLength($0) < pathLength($1) }
            ?? [escapeStart, CGPoint(x: (escapeStart.x + escapeEnd.x) / 2, y: escapeStart.y), CGPoint(x: (escapeStart.x + escapeEnd.x) / 2, y: escapeEnd.y), escapeEnd]
        var adjustedPath = safePath
        if abs(adjustedPath[1].x - adjustedPath[2].x) < 0.5 {
            adjustedPath[1].x += segment.bendOffset
            adjustedPath[2].x += segment.bendOffset
            if snapToGrid {
                let snappedX = snappedCoordinate(adjustedPath[1].x)
                adjustedPath[1].x = snappedX
                adjustedPath[2].x = snappedX
            }
        } else {
            adjustedPath[1].y += segment.bendOffset
            adjustedPath[2].y += segment.bendOffset
            if snapToGrid {
                let snappedY = snappedCoordinate(adjustedPath[1].y)
                adjustedPath[1].y = snappedY
                adjustedPath[2].y = snappedY
            }
        }
        let routePoints = simplifyOrthogonalPoints([start, escapeStart] + adjustedPath.dropFirst() + [end])
        return routePoints
    }

    private func sectionPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    private func simplifyOrthogonalPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var simplified = [points[0]]
        for point in points.dropFirst() {
            guard let previous = simplified.last else { continue }
            if abs(point.x - previous.x) < 0.5 && abs(point.y - previous.y) < 0.5 { continue }
            if simplified.count >= 2 {
                let before = simplified[simplified.count - 2]
                let isCollinear = (abs(before.x - previous.x) < 0.5 && abs(previous.x - point.x) < 0.5) ||
                    (abs(before.y - previous.y) < 0.5 && abs(previous.y - point.y) < 0.5)
                if isCollinear {
                    simplified[simplified.count - 1] = point
                    continue
                }
            }
            simplified.append(point)
        }
        return simplified
    }

    private func offsetConnectionPoint(for target: SchematicTarget, slot: Int?, toward other: SchematicTarget, by offset: CGFloat) -> CGPoint {
        let point = connectionPoint(for: target, slot: slot)
        let dx = other.position.x - target.position.x
        let dy = other.position.y - target.position.y
        let length = max(hypot(dx, dy), 1)
        return CGPoint(x: point.x - dy / length * offset, y: point.y + dx / length * offset)
    }

    private func escapePoint(for target: SchematicTarget, slot: Int, toward other: SchematicTarget) -> CGPoint {
        let point = connectionPoint(for: target, slot: slot)
        let angle = target.kind == .junction
            ? atan2(other.position.y - target.position.y, other.position.x - target.position.x)
            : connectionAngle(for: target, slot: slot) * Double.pi / 180
        let distance: CGFloat = target.kind == .junction ? 24 : max((target.isCompact ? 24 : 36) * target.scale, CGFloat(linePadding) + 12)
        return CGPoint(x: point.x + distance * CGFloat(cos(angle)), y: point.y + distance * CGFloat(sin(angle)))
    }

    private func startTargetSlot(_ target: SchematicTarget, point: CGPoint) -> Int {
        nearestConnectionSlot(for: target, to: point)
    }

    private func endTargetSlot(_ target: SchematicTarget, point: CGPoint) -> Int {
        nearestConnectionSlot(for: target, to: point)
    }

    private func nearestConnectionSlot(for target: SchematicTarget, to point: CGPoint) -> Int {
        (0..<max(target.maxConnections, 1)).min { lhs, rhs in
            let lhsPoint = connectionPoint(for: target, slot: lhs)
            let rhsPoint = connectionPoint(for: target, slot: rhs)
            return hypot(lhsPoint.x - point.x, lhsPoint.y - point.y) < hypot(rhsPoint.x - point.x, rhsPoint.y - point.y)
        } ?? 0
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { length, pair in
            length + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private func obstacleRect(for target: SchematicTarget) -> CGRect {
        let size = target.kind == .junction ? CGSize(width: 18, height: 18) : target.isCompact ? CGSize(width: 40, height: 40) : CGSize(width: 108, height: 76)
        return CGRect(x: target.position.x - size.width * target.scale / 2, y: target.position.y - size.height * target.scale / 2, width: size.width * target.scale, height: size.height * target.scale)
    }

    private func pointsAreClear(_ points: [CGPoint], from rectangles: [CGRect]) -> Bool {
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            for rectangle in rectangles where segmentIntersects(rectangle, from: start, to: end) { return false }
        }
        return true
    }

    private func segmentIntersects(_ rectangle: CGRect, from start: CGPoint, to end: CGPoint) -> Bool {
        if abs(start.x - end.x) < 0.5 {
            return start.x >= rectangle.minX && start.x <= rectangle.maxX && max(start.y, end.y) >= rectangle.minY && min(start.y, end.y) <= rectangle.maxY
        }
        if abs(start.y - end.y) < 0.5 {
            return start.y >= rectangle.minY && start.y <= rectangle.maxY && max(start.x, end.x) >= rectangle.minX && min(start.x, end.x) <= rectangle.maxX
        }
        return true
    }

    private func splitSegmentIfNeeded(for targetID: UUID) {
        guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }) else { return }
        let position = document.targets[targetIndex].position
        for (index, segment) in document.segments.enumerated() {
            guard segment.startID != targetID, segment.endID != targetID, let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let candidate = nearestPoint(on: [start.position, CGPoint(x: (start.position.x + end.position.x) / 2, y: start.position.y), CGPoint(x: (start.position.x + end.position.x) / 2, y: end.position.y), end.position], to: position)
            guard candidate.distance <= 30 else { continue }
            guard document.targets[targetIndex].maxConnections >= 2 else { return }
            document.segments.remove(at: index)
            let startSlot = segment.startSlot ?? 0
            let endSlot = segment.endSlot ?? 0
            document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, startSlot: startSlot, endSlot: 0, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, displayWidth: segment.displayWidth, description: segment.description), at: index)
            document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, startSlot: 1, endSlot: endSlot, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, displayWidth: segment.displayWidth, description: segment.description), at: index + 1)
            return
        }
    }

    private func nearestPoint(on points: [CGPoint], to target: CGPoint) -> (point: CGPoint, distance: CGFloat) {
        var best = (points[0], CGFloat.greatestFiniteMagnitude)
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1], vector = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let length = vector.x * vector.x + vector.y * vector.y
            let projection = length == 0 ? 0 : ((target.x - a.x) * vector.x + (target.y - a.y) * vector.y) / length
            let t = min(max(projection, 0), 1), point = CGPoint(x: a.x + vector.x * t, y: a.y + vector.y * t)
            let distance = hypot(point.x - target.x, point.y - target.y)
            if distance < best.1 { best = (point, distance) }
        }
        return best
    }

    private var selectedLineDefinition: LineDefinition? {
        guard let selectedLineDefinitionID else { return nil }
        return document.lineDefinitions.first { $0.id == selectedLineDefinitionID }
    }

    private func segmentBinding(_ segment: SchematicSegment) -> (name: Binding<String>, color: Binding<Color>, wireSize: Binding<String>, material: Binding<ConductorMaterial>, displayWidth: Binding<Double>, description: Binding<String>) {
        guard let index = document.segments.firstIndex(where: { $0.id == segment.id }) else { fatalError("Segment disappeared") }
        return (
            Binding(get: { document.segments[index].name }, set: { document.segments[index].name = $0 }),
            Binding(get: { Color(hex: document.segments[index].colorHex) }, set: { document.segments[index].colorHex = $0.hexString }),
            Binding(get: { document.segments[index].wireSize }, set: { document.segments[index].wireSize = $0 }),
            Binding(get: { ConductorMaterial(rawValue: document.segments[index].material) ?? .copper }, set: { document.segments[index].material = $0.rawValue }),
            Binding(get: { document.segments[index].displayWidth }, set: { document.segments[index].displayWidth = $0 }),
            Binding(get: { document.segments[index].description }, set: { document.segments[index].description = $0 })
        )
    }

    private func targetBinding(_ target: SchematicTarget) -> (name: Binding<String>, symbol: Binding<String>, maxConnections: Binding<Int>, connectionAngle: Binding<Double>, color: Binding<Color>, scale: Binding<Double>, isCompact: Binding<Bool>) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { fatalError("Target disappeared") }
        return (
            Binding(get: { document.targets[index].name }, set: { document.targets[index].name = $0 }),
            Binding(get: { document.targets[index].symbol }, set: { document.targets[index].symbol = $0 }),
            Binding(get: { document.targets[index].maxConnections }, set: { document.targets[index].maxConnections = $0 }),
            Binding(get: { document.targets[index].connectionAngle }, set: { document.targets[index].connectionAngle = $0 }),
            Binding(get: { Color(hex: document.targets[index].colorHex) }, set: { document.targets[index].colorHex = $0.hexString }),
            Binding(get: { document.targets[index].scale }, set: { document.targets[index].scale = $0 }),
            Binding(get: { document.targets[index].isCompact }, set: { document.targets[index].isCompact = $0 })
        )
    }

    private func loadTargetImage(_ item: PhotosPickerItem, targetID: UUID) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let index = document.targets.firstIndex(where: { $0.id == targetID }) else { return }
        document.targets[index].imageData = data
        selectedPhotoItem = nil
    }

    private func clearTargetImage(_ target: SchematicTarget) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        document.targets[index].imageData = nil
        selectedPhotoItem = nil
    }

    private func applyLineDefinition(_ line: LineDefinition, to segmentID: UUID) {
        guard let index = document.segments.firstIndex(where: { $0.id == segmentID }) else { return }
        document.segments[index].name = line.name
        document.segments[index].colorHex = line.colorHex
        document.segments[index].wireSize = line.wireSize
        document.segments[index].material = line.material.rawValue
        document.segments[index].displayWidth = line.displayWidth
        document.segments[index].description = line.description
    }

    private func applyLineDefinition(_ line: LineDefinition, to segmentIDs: Set<UUID>) {
        for segmentID in segmentIDs {
            applyLineDefinition(line, to: segmentID)
        }
    }
}

private struct SchematicDocument: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targets: [SchematicTarget] = []
    var segments: [SchematicSegment] = []
    var lineDefinitions: [LineDefinition] = LineDefinition.defaults
    var targetDefinitions: [TargetDefinition] = []

    init(name: String, targets: [SchematicTarget] = [], segments: [SchematicSegment] = [], lineDefinitions: [LineDefinition] = LineDefinition.defaults, targetDefinitions: [TargetDefinition] = TargetDefinition.defaults) {
        self.name = name; self.targets = targets; self.segments = segments; self.lineDefinitions = lineDefinitions; self.targetDefinitions = targetDefinitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled schematic"
        targets = try container.decodeIfPresent([SchematicTarget].self, forKey: .targets) ?? []
        segments = try container.decodeIfPresent([SchematicSegment].self, forKey: .segments) ?? []
        let savedLineDefinitions = try container.decodeIfPresent([LineDefinition].self, forKey: .lineDefinitions) ?? []
        lineDefinitions = savedLineDefinitions.isEmpty ? LineDefinition.defaults : savedLineDefinitions
        let savedTargetDefinitions = try container.decodeIfPresent([TargetDefinition].self, forKey: .targetDefinitions) ?? []
        targetDefinitions = savedTargetDefinitions.isEmpty ? TargetDefinition.defaults : savedTargetDefinitions
    }

    static func loadLast() -> SchematicDocument {
        guard let data = UserDefaults.standard.data(forKey: "lastSchematic"), let saved = try? JSONDecoder().decode(SchematicDocument.self, from: data) else {
            return SchematicDocument(name: "Untitled schematic", targets: [SchematicTarget(kind: .source, name: "Power source", position: CGPoint(x: 330, y: 270), maxConnections: 2, colorHex: "FF9F43"), SchematicTarget(kind: .load, name: "Load", position: CGPoint(x: 650, y: 430), maxConnections: 2, colorHex: "FFD166")])
        }
        return saved
    }

    static func loadAll() -> [SchematicDocument] { guard let data = UserDefaults.standard.data(forKey: "savedSchematics"), let saved = try? JSONDecoder().decode([SchematicDocument].self, from: data) else { return [] }; return saved }
    static func saveLast(_ document: SchematicDocument) { if let data = try? JSONEncoder().encode(document) { UserDefaults.standard.set(data, forKey: "lastSchematic") } }
    static func saveAll(_ documents: [SchematicDocument]) { if let data = try? JSONEncoder().encode(documents) { UserDefaults.standard.set(data, forKey: "savedSchematics") } }
}

private struct SchematicTarget: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: TargetKind
    var name: String
    var position: CGPoint
    var maxConnections: Int
    var colorHex: String
    var symbol: String
    var imageData: Data?
    var connectionAngle: Double
    var connectionAngles: [Double]
    var scale: Double
    var isCompact: Bool

    init(id: UUID = UUID(), kind: TargetKind, name: String, position: CGPoint, maxConnections: Int, colorHex: String, symbol: String? = nil, imageData: Data? = nil, connectionAngle: Double = 0, connectionAngles: [Double] = [], scale: Double = 1, isCompact: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        self.maxConnections = maxConnections
        self.colorHex = colorHex
        self.symbol = symbol ?? kind.symbol
        self.imageData = imageData
        self.connectionAngle = connectionAngle
        self.connectionAngles = connectionAngles
        self.scale = scale
        self.isCompact = isCompact
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(TargetKind.self, forKey: .kind)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? kind.title
        position = try container.decode(CGPoint.self, forKey: .position)
        maxConnections = try container.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 2
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? kind.defaultColorHex
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? kind.symbol
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        connectionAngle = try container.decodeIfPresent(Double.self, forKey: .connectionAngle) ?? 0
        connectionAngles = try container.decodeIfPresent([Double].self, forKey: .connectionAngles) ?? []
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        isCompact = try container.decodeIfPresent(Bool.self, forKey: .isCompact) ?? false
    }
}

private struct TargetDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: TargetKind
    var name: String
    var maxConnections: Int
    var colorHex: String
    var symbol: String
    var imageData: Data?
    var connectionAngles: [Double]
    var scale: Double
    var isCompact: Bool

    static let defaults: [TargetDefinition] = TargetKind.palette.map {
        TargetDefinition(kind: $0, name: $0.title, maxConnections: $0 == .panel || $0 == .bus ? 8 : 2, colorHex: $0.defaultColorHex, symbol: $0.symbol, imageData: nil, connectionAngles: [], scale: 1)
    }

    init(id: UUID = UUID(), kind: TargetKind, name: String, maxConnections: Int, colorHex: String, symbol: String, imageData: Data?, connectionAngles: [Double], scale: Double, isCompact: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.maxConnections = maxConnections
        self.colorHex = colorHex
        self.symbol = symbol
        self.imageData = imageData
        self.connectionAngles = connectionAngles
        self.scale = scale
        self.isCompact = isCompact
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(TargetKind.self, forKey: .kind)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? kind.title
        maxConnections = try container.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 2
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? kind.defaultColorHex
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? kind.symbol
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        connectionAngles = try container.decodeIfPresent([Double].self, forKey: .connectionAngles) ?? []
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        isCompact = try container.decodeIfPresent(Bool.self, forKey: .isCompact) ?? false
    }
}

private struct SchematicSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var startID: UUID
    var endID: UUID
    var startSlot: Int?
    var endSlot: Int?
    var name: String
    var colorHex: String
    var wireSize: String
    var material: String
    var displayWidth: Double
    var description: String
    var bendOffset: CGFloat
    var routePoints: [CGPoint]
    var color: Color { Color(hex: colorHex) }

    init(startID: UUID, endID: UUID, startSlot: Int? = nil, endSlot: Int? = nil, name: String, colorHex: String, wireSize: String = "14 AWG", material: String = "Copper", displayWidth: Double = 3, description: String = "", bendOffset: CGFloat = 0, routePoints: [CGPoint] = []) {
        self.startID = startID; self.endID = endID; self.startSlot = startSlot; self.endSlot = endSlot; self.name = name; self.colorHex = colorHex
        self.wireSize = wireSize; self.material = material; self.displayWidth = displayWidth; self.description = description; self.bendOffset = bendOffset; self.routePoints = routePoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startID = try container.decode(UUID.self, forKey: .startID)
        endID = try container.decode(UUID.self, forKey: .endID)
        startSlot = try container.decodeIfPresent(Int.self, forKey: .startSlot)
        endSlot = try container.decodeIfPresent(Int.self, forKey: .endSlot)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Connection"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "31D7E8"
        wireSize = try container.decodeIfPresent(String.self, forKey: .wireSize) ?? "14 AWG"
        material = try container.decodeIfPresent(String.self, forKey: .material) ?? "Copper"
        displayWidth = try container.decodeIfPresent(Double.self, forKey: .displayWidth) ?? 3
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        bendOffset = try container.decodeIfPresent(CGFloat.self, forKey: .bendOffset) ?? 0
        routePoints = try container.decodeIfPresent([CGPoint].self, forKey: .routePoints) ?? []
    }
}

private struct LineDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String
    var wireSize: String
    var material: ConductorMaterial
    var displayWidth: Double
    var description: String

    init(id: UUID = UUID(), name: String, colorHex: String, wireSize: String, material: ConductorMaterial = .copper, displayWidth: Double, description: String) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.wireSize = wireSize; self.material = material; self.displayWidth = displayWidth; self.description = description
    }

    static let defaultLine = LineDefinition(name: "Standard wire", colorHex: "31D7E8", wireSize: "14 AWG", material: .copper, displayWidth: 3, description: "General purpose connection")
    static let defaults: [LineDefinition] = {
        let sizes = ["1/0", "2/0", "4/0", "2", "4", "6", "8", "10", "12", "14", "16", "18"]
        return ConductorMaterial.allCases.flatMap { material in
            sizes.map { size in
                LineDefinition(name: "\(material.rawValue) \(size)", colorHex: material.defaultColorHex, wireSize: size, material: material, displayWidth: 3, description: "Common \(material.rawValue) conductor")
            }
        }
    }()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Standard wire"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "31D7E8"
        wireSize = try container.decodeIfPresent(String.self, forKey: .wireSize) ?? "14 AWG"
        material = try container.decodeIfPresent(ConductorMaterial.self, forKey: .material) ?? .copper
        displayWidth = try container.decodeIfPresent(Double.self, forKey: .displayWidth) ?? 3
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

private enum ConductorMaterial: String, CaseIterable, Codable, Identifiable {
    case copper = "Copper"
    case aaac = "AAAC"
    case aac = "AAC"
    case acsr = "ACSR"
    case covered = "Covered"
    var id: String { rawValue }
    var title: String { rawValue }
    var defaultColorHex: String {
        switch self { case .copper: return "D98B5F"; case .aaac: return "B8C4D1"; case .aac: return "D6DEE8"; case .acsr: return "8C9AA8"; case .covered: return "F2C14E" }
    }
}

private enum TargetKind: String, CaseIterable, Identifiable, Codable {
    case source, utilitySource, transformer, breaker, fuse, disconnect, switchTarget, panel, bus, meter, generator, motor, receptacle, ground, capacitor, load, junction
    static let palette: [TargetKind] = [.source, .utilitySource, .transformer, .breaker, .fuse, .disconnect, .switchTarget, .panel, .bus, .meter, .generator, .motor, .receptacle, .ground, .capacitor, .load]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: return "Source"; case .utilitySource: return "Utility source"; case .transformer: return "Transformer"; case .breaker: return "Breaker"; case .fuse: return "Fuse"; case .disconnect: return "Disconnect"; case .switchTarget: return "Switch"; case .panel: return "Panel"; case .bus: return "Bus"; case .meter: return "Meter"; case .generator: return "Generator"; case .motor: return "Motor"; case .receptacle: return "Receptacle"; case .ground: return "Ground"; case .capacitor: return "Capacitor"; case .load: return "Load"; case .junction: return "Junction"
        }
    }
    var symbol: String {
        switch self {
        case .source: return "bolt.fill"; case .utilitySource: return "powerplug.fill"; case .transformer: return "arrow.left.arrow.right"; case .breaker: return "bolt.shield.fill"; case .fuse: return "fuse"; case .disconnect: return "poweroff"; case .switchTarget: return "switch.2"; case .panel: return "rectangle.split.3x1"; case .bus: return "line.3.horizontal"; case .meter: return "gauge.with.dots.needle.bottom.50percent"; case .generator: return "engine.combustion.fill"; case .motor: return "fanblades.fill"; case .receptacle: return "rectangle.grid.2x2"; case .ground: return "arrow.down.to.line"; case .capacitor: return "minus.plus.batteryblock"; case .load: return "lightbulb.fill"; case .junction: return "circle.fill"
        }
    }
    var defaultColorHex: String {
        switch self {
        case .source, .utilitySource: return "FF9F43"; case .transformer: return "F59E0B"; case .breaker, .fuse, .disconnect: return "F87171"; case .switchTarget: return "6EE7B7"; case .panel, .bus: return "60A5FA"; case .meter: return "A78BFA"; case .generator: return "FB923C"; case .motor: return "34D399"; case .receptacle, .load: return "FFD166"; case .ground: return "94A3B8"; case .capacitor: return "F472B6"; case .junction: return "31D7E8"
        }
    }
}

private struct PaletteItem: View {
    let kind: TargetKind
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: kind.defaultColorHex)).frame(width: 24)
            Text(kind.title).font(.system(size: 13, weight: .semibold)); Spacer(); Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 9).frame(height: 38).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct TargetView: View {
    let target: SchematicTarget
    let isSelected: Bool
    let selectionOrder: Int?
    let isConnectionStart: Bool
    let connectedColor: Color
    let connectedColors: [Color]
    let occupiedSlots: Set<Int>
    let selectedSlots: Set<Int>
    let onSelectConnectionPoint: (Int) -> Void
    let editingConnectionPoints: Bool
    let onMoveConnectionPoint: (Int, CGSize) -> Void
    let onEndConnectionPointMove: (Int) -> Void

    var body: some View {
        Group {
            if target.kind == .junction {
                Circle().fill(connectedColor).frame(width: 18, height: 18).overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 2) }
            } else if target.isCompact {
                ZStack {
                    Circle().fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                    Circle().stroke(borderStyle, lineWidth: isSelected || isConnectionStart ? 2 : 1)
                    if let imageData = target.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 24, height: 24).clipShape(Circle())
                    } else {
                        Image(systemName: target.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Color(hex: target.colorHex))
                    }
                }
                .frame(width: 40, height: 40)
            } else {
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(borderStyle, lineWidth: isSelected || isConnectionStart ? 2 : 1)
                        if let imageData = target.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            Image(systemName: target.symbol)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color(hex: target.colorHex))
                        }
                    }.frame(width: 58, height: 48)
                    Text(target.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }.frame(width: 108, height: 76)
            }
        }
        .overlay {
            if isSelected || isConnectionStart {
                if target.kind == .junction {
                    Circle().stroke(.cyan, lineWidth: 3).frame(width: 30, height: 30).shadow(color: .cyan.opacity(0.8), radius: 8)
                } else if target.isCompact {
                    Circle().stroke(.cyan, lineWidth: 3).frame(width: 44, height: 44).shadow(color: .cyan.opacity(0.8), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 12).stroke(.cyan, lineWidth: 3).frame(width: 64, height: 54).shadow(color: .cyan.opacity(0.8), radius: 8)
                        .offset(y: -9)
                }
            }
        }
        .overlay {
            if target.kind == .junction {
                Circle()
                    .fill(connectedColor)
                    .frame(width: 10, height: 10)
                    .overlay { Circle().stroke(.black.opacity(0.65), lineWidth: 1) }
            } else {
                ForEach(0..<target.maxConnections, id: \.self) { slot in
                    connectionPoint(slot: slot)
                }
            }
        }
        .scaleEffect(target.scale)
        .overlay(alignment: .topTrailing) {
            if let selectionOrder {
                Text("\(selectionOrder)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(.cyan, in: Circle())
                    .overlay { Circle().stroke(.black.opacity(0.4), lineWidth: 1) }
                    .offset(x: 4, y: -4)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func connectionPoint(slot: Int) -> some View {
        let point = Circle()
            .fill(selectedSlots.contains(slot) ? Color.cyan : occupiedSlots.contains(slot) ? connectedColor : Color.white.opacity(0.35))
            .frame(width: selectedSlots.contains(slot) ? 14 : 9, height: selectedSlots.contains(slot) ? 14 : 9)
            .overlay { Circle().stroke(selectedSlots.contains(slot) ? Color.white : .black.opacity(0.65), lineWidth: selectedSlots.contains(slot) ? 2 : 1) }

        if editingConnectionPoints {
            point
                .frame(width: 18, height: 18)
                .contentShape(Circle().scale(2.5))
                .offset(connectionPointOffset(for: slot))
                .onTapGesture { onSelectConnectionPoint(slot) }
                .gesture(
                    DragGesture()
                        .onChanged { value in onMoveConnectionPoint(slot, value.translation) }
                        .onEnded { _ in onEndConnectionPointMove(slot) }
                )
        } else {
            ZStack {
                point
                Circle().fill(.clear).frame(width: 28, height: 28)
            }
                .contentShape(Circle())
                .offset(connectionPointOffset(for: slot))
                .highPriorityGesture(TapGesture().onEnded { onSelectConnectionPoint(slot) })
        }
    }

    private func connectionPointOffset(for slot: Int) -> CGSize {
        let angle = (target.connectionAngles.indices.contains(slot) ? target.connectionAngles[slot] : (360 * Double(slot) / Double(max(target.maxConnections, 1))) + target.connectionAngle - 90) * Double.pi / 180
        let radius: CGFloat = target.kind == .junction ? 0 : (target.isCompact ? 24 : 42)
        return CGSize(width: radius * CGFloat(cos(angle)), height: radius * CGFloat(sin(angle)))
    }

    private var borderStyle: AnyShapeStyle {
        if isSelected || isConnectionStart {
            return AnyShapeStyle(Color(hex: target.colorHex))
        }
        if connectedColors.count > 1 {
            return AnyShapeStyle(AngularGradient(colors: connectedColors, center: .center))
        }
        return AnyShapeStyle(connectedColors.first ?? Color.white.opacity(0.18))
    }
}

private struct SegmentHitArea: View {
    let path: Path
    let isSelected: Bool
    let isSectionSelected: Bool
    let onDrag: (CGSize) -> Void
    let onEndDrag: () -> Void
    let onTap: () -> Void
    var body: some View {
        path.stroke(isSectionSelected ? Color.yellow.opacity(0.85) : isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.001), style: StrokeStyle(lineWidth: isSectionSelected ? 12 : 24, lineCap: .round, lineJoin: .round))
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)))
            .onTapGesture(perform: onTap)
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in onDrag(value.translation) }.onEnded { _ in onEndDrag() })
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 32; var path = Path()
            stride(from: 0, through: size.width, by: spacing).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0, through: size.height, by: spacing).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }.background(Color(red: 0.07, green: 0.09, blue: 0.105))
    }
}

private struct EditorButtonStyle: ButtonStyle {
    var isActive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(isActive ? .cyan : .white.opacity(0.82)).padding(.horizontal, 13).frame(height: 42).background(isActive ? .cyan.opacity(0.12) : .white.opacity(configuration.isPressed ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(isActive ? .cyan.opacity(0.45) : .white.opacity(0.1), lineWidth: 1) }
    }
}

private extension View {
    func inspectorLabel() -> some View { font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.4)) }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

#Preview { ContentView() }
