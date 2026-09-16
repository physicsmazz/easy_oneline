import SwiftUI
import Foundation

struct ContentView: View {
    @State private var document = SchematicDocument.loadLast()
    @State private var savedDocuments = SchematicDocument.loadAll()
    @State private var canvasOffset = CGSize.zero
    @State private var panStart = CGSize.zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var selectedTargetIDs: [UUID] = []
    @State private var selectedSegmentID: UUID?
    @State private var showInspector = false
    @State private var showLibrary = false
    @State private var showLineLibrary = false
    @State private var selectedLineDefinitionID: UUID?

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

            if showInspector {
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
        }
        .preferredColorScheme(.dark)
        .onChange(of: document) { _, _ in
            SchematicDocument.saveLast(document)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EASY / ONE LINE")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(1.5)
                TextField("Schematic name", text: $document.name)
                    .font(.system(size: 12, weight: .medium))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 180)
            }

            Spacer()

            Button { showLibrary.toggle() } label: {
                Label("Schematics", systemImage: "folder")
            }
            .buttonStyle(EditorButtonStyle(isActive: showLibrary))

            Button { showLineLibrary.toggle() } label: {
                Label("Lines", systemImage: "line.3.horizontal")
            }
            .buttonStyle(EditorButtonStyle(isActive: showLineLibrary))

            Button { saveCurrent() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(EditorButtonStyle())

            Button {
                connectSelectedTargets()
            } label: {
                Label(selectedTargetIDs.count >= 2 ? "Connect \(selectedTargetIDs.count)" : "Connect", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(EditorButtonStyle(isActive: selectedTargetIDs.count >= 2))
            .disabled(selectedTargetIDs.count < 2)

            Button { showInspector.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(EditorButtonStyle())
            .accessibilityLabel("Toggle inspector")
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
            Text("TARGETS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))

            ForEach(TargetKind.palette) { kind in
                PaletteItem(kind: kind)
                    .draggable(kind.rawValue)
                    .onDrag { NSItemProvider(object: kind.rawValue as NSString) }
                    .onTapGesture { addTarget(kind) }
            }

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
        .padding(14)
        .frame(width: 170)
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
                    showInspector = false
                }

            Canvas { context, _ in
                for segment in document.segments {
                    guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
                    let path = orthogonalPath(from: start.position, to: end.position)
                    context.stroke(path, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.displayWidth, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(false)

            ForEach(document.segments) { segment in
                if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                    SegmentHitArea(path: orthogonalPath(from: start.position, to: end.position), isSelected: segment.id == selectedSegmentID) {
                        selectedSegmentID = segment.id
                        selectedTargetIDs.removeAll()
                        showInspector = true
                    }
                }
            }

            ForEach(document.targets) { target in
                TargetView(
                    target: target,
                    isSelected: selectedTargetIDs.contains(target.id),
                    selectionOrder: selectedTargetIDs.firstIndex(of: target.id).map { $0 + 1 },
                    isConnectionStart: selectedTargetIDs.contains(target.id),
                    connectedColor: connectedColor(for: target.id)
                )
                .position(target.position)
                .gesture(targetDragGesture(for: target, canvasSize: size))
                .onTapGesture { targetTapped(target) }
            }
        }
        .offset(canvasOffset)
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
                guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
                if dragStartPositions[target.id] == nil { dragStartPositions[target.id] = document.targets[index].position }
                guard let start = dragStartPositions[target.id] else { return }
                document.targets[index].position = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                selectedTargetIDs = [target.id]
                selectedSegmentID = nil
            }
            .onEnded { _ in
                dragStartPositions.removeValue(forKey: target.id)
                snapTarget(target.id, canvasSize: canvasSize)
                splitSegmentIfNeeded(for: target.id)
            }
    }

    private func targetTapped(_ target: SchematicTarget) {
        selectedSegmentID = nil
        if let selectedIndex = selectedTargetIDs.firstIndex(of: target.id) {
            selectedTargetIDs.remove(at: selectedIndex)
        } else {
            selectedTargetIDs.append(target.id)
        }
        showInspector = true
    }

    private func connectSelectedTargets() {
        let ids = Array(selectedTargetIDs)
        guard ids.count >= 2 else { return }
        for pairIndex in 0..<(ids.count - 1) {
            let startID = ids[pairIndex]
            let endID = ids[pairIndex + 1]
            guard connectionCount(for: startID) < (target(with: startID)?.maxConnections ?? 0), connectionCount(for: endID) < (target(with: endID)?.maxConnections ?? 0) else { continue }
            guard !document.segments.contains(where: { ($0.startID == startID && $0.endID == endID) || ($0.startID == endID && $0.endID == startID) }) else { continue }
            let line = selectedLineDefinition ?? document.lineDefinitions.first ?? LineDefinition.defaultLine
            document.segments.append(SchematicSegment(startID: startID, endID: endID, name: line.name, colorHex: line.colorHex, wireSize: line.wireSize, displayWidth: line.displayWidth, description: line.description))
        }
        selectedTargetIDs.removeAll()
    }

    private func addTarget(_ kind: TargetKind, at point: CGPoint? = nil) {
        let position = point ?? CGPoint(x: 480 - canvasOffset.width, y: 330 - canvasOffset.height)
        document.targets.append(SchematicTarget(kind: kind, name: kind.title, position: position, maxConnections: kind == .junction ? 8 : 2, colorHex: kind.defaultColorHex))
        selectedTargetIDs = [document.targets.last!.id]
        selectedSegmentID = nil
        showInspector = true
    }

    private func saveCurrent() {
        if let index = savedDocuments.firstIndex(where: { $0.id == document.id }) { savedDocuments[index] = document } else { savedDocuments.append(document) }
        SchematicDocument.saveAll(savedDocuments)
        SchematicDocument.saveLast(document)
    }

    private func newSchematic() {
        saveCurrent()
        document = SchematicDocument(name: "Untitled schematic")
        selectedTargetIDs.removeAll()
        selectedSegmentID = nil
        showLibrary = false
    }

    private func load(_ saved: SchematicDocument) {
        document = saved
        selectedTargetIDs.removeAll()
        selectedSegmentID = nil
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
                    showLineLibrary = false
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: line.colorHex)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name).font(.system(size: 13, weight: .semibold))
                            Text("\(line.wireSize) · \(line.displayWidth, specifier: "%.1f") pt · \(line.description)").font(.caption2).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
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

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let segment = selectedSegment {
                Text("SEGMENT").inspectorLabel()
                TextField("Line name", text: segmentBinding(segment).name)
                    .textFieldStyle(.roundedBorder)
                ColorPicker("Line color", selection: segmentBinding(segment).color)
                TextField("Wire size", text: segmentBinding(segment).wireSize).textFieldStyle(.roundedBorder)
                TextField("Description", text: segmentBinding(segment).description).textFieldStyle(.roundedBorder)
                Stepper("Display width: \(segment.displayWidth, specifier: "%.1f")", value: segmentBinding(segment).displayWidth, in: 1...20, step: 0.5)
                Button {
                    document.lineDefinitions.append(LineDefinition(name: segment.name, colorHex: segment.colorHex, wireSize: segment.wireSize, displayWidth: segment.displayWidth, description: segment.description))
                } label: {
                    Label("Add to line library", systemImage: "plus.circle")
                }
                Button(role: .destructive) { document.segments.removeAll { $0.id == segment.id }; selectedSegmentID = nil } label: { Label("Delete line", systemImage: "trash") }
            } else if selectedTargetIDs.count == 1, let target = target(with: selectedTargetIDs.first!) {
                Text("TARGET").inspectorLabel()
                TextField("Target name", text: targetBinding(target).name).textFieldStyle(.roundedBorder)
                Stepper("Connections: \(target.maxConnections)", value: targetBinding(target).maxConnections, in: 0...32)
                if target.kind != .junction { ColorPicker("Target color", selection: targetBinding(target).color) }
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

    private var selectedSegment: SchematicSegment? { guard let selectedSegmentID else { return nil }; return document.segments.first { $0.id == selectedSegmentID } }
    private func target(with id: UUID) -> SchematicTarget? { document.targets.first { $0.id == id } }
    private func connectionCount(for id: UUID) -> Int { document.segments.filter { $0.startID == id || $0.endID == id }.count }
    private func connectedColor(for id: UUID) -> Color { document.segments.first(where: { $0.startID == id || $0.endID == id }).map { $0.color } ?? .cyan }

    private func snapTarget(_ id: UUID, canvasSize: CGSize) {
        guard let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
        document.targets[index].position.x = min(max(document.targets[index].position.x, 180), max(180, canvasSize.width - 80))
        document.targets[index].position.y = min(max(document.targets[index].position.y, 120), max(120, canvasSize.height - 80))
    }

    private func orthogonalPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path(); let midpointX = (start.x + end.x) / 2
        path.move(to: start); path.addLine(to: CGPoint(x: midpointX, y: start.y)); path.addLine(to: CGPoint(x: midpointX, y: end.y)); path.addLine(to: end)
        return path
    }

    private func splitSegmentIfNeeded(for targetID: UUID) {
        guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }) else { return }
        let position = document.targets[targetIndex].position
        for (index, segment) in document.segments.enumerated() {
            guard segment.startID != targetID, segment.endID != targetID, let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let candidate = nearestPoint(on: [start.position, CGPoint(x: (start.position.x + end.position.x) / 2, y: start.position.y), CGPoint(x: (start.position.x + end.position.x) / 2, y: end.position.y), end.position], to: position)
            guard candidate.distance <= 30 else { continue }
            document.targets[targetIndex].position = candidate.point
            document.segments.remove(at: index)
            document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, displayWidth: segment.displayWidth, description: segment.description), at: index)
            document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, displayWidth: segment.displayWidth, description: segment.description), at: index + 1)
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

    private func segmentBinding(_ segment: SchematicSegment) -> (name: Binding<String>, color: Binding<Color>, wireSize: Binding<String>, displayWidth: Binding<Double>, description: Binding<String>) {
        guard let index = document.segments.firstIndex(where: { $0.id == segment.id }) else { fatalError("Segment disappeared") }
        return (
            Binding(get: { document.segments[index].name }, set: { document.segments[index].name = $0 }),
            Binding(get: { Color(hex: document.segments[index].colorHex) }, set: { document.segments[index].colorHex = $0.hexString }),
            Binding(get: { document.segments[index].wireSize }, set: { document.segments[index].wireSize = $0 }),
            Binding(get: { document.segments[index].displayWidth }, set: { document.segments[index].displayWidth = $0 }),
            Binding(get: { document.segments[index].description }, set: { document.segments[index].description = $0 })
        )
    }

    private func targetBinding(_ target: SchematicTarget) -> (name: Binding<String>, maxConnections: Binding<Int>, color: Binding<Color>) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { fatalError("Target disappeared") }
        return (Binding(get: { document.targets[index].name }, set: { document.targets[index].name = $0 }), Binding(get: { document.targets[index].maxConnections }, set: { document.targets[index].maxConnections = $0 }), Binding(get: { Color(hex: document.targets[index].colorHex) }, set: { document.targets[index].colorHex = $0.hexString }))
    }
}

private struct SchematicDocument: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targets: [SchematicTarget] = []
    var segments: [SchematicSegment] = []
    var lineDefinitions: [LineDefinition] = [.defaultLine]

    init(name: String, targets: [SchematicTarget] = [], segments: [SchematicSegment] = [], lineDefinitions: [LineDefinition] = [.defaultLine]) {
        self.name = name; self.targets = targets; self.segments = segments; self.lineDefinitions = lineDefinitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled schematic"
        targets = try container.decodeIfPresent([SchematicTarget].self, forKey: .targets) ?? []
        segments = try container.decodeIfPresent([SchematicSegment].self, forKey: .segments) ?? []
        lineDefinitions = try container.decodeIfPresent([LineDefinition].self, forKey: .lineDefinitions) ?? [.defaultLine]
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
}

private struct SchematicSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var startID: UUID
    var endID: UUID
    var name: String
    var colorHex: String
    var wireSize: String
    var displayWidth: Double
    var description: String
    var color: Color { Color(hex: colorHex) }

    init(startID: UUID, endID: UUID, name: String, colorHex: String, wireSize: String = "14 AWG", displayWidth: Double = 3, description: String = "") {
        self.startID = startID; self.endID = endID; self.name = name; self.colorHex = colorHex
        self.wireSize = wireSize; self.displayWidth = displayWidth; self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startID = try container.decode(UUID.self, forKey: .startID)
        endID = try container.decode(UUID.self, forKey: .endID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Connection"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "31D7E8"
        wireSize = try container.decodeIfPresent(String.self, forKey: .wireSize) ?? "14 AWG"
        displayWidth = try container.decodeIfPresent(Double.self, forKey: .displayWidth) ?? 3
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

private struct LineDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String
    var wireSize: String
    var displayWidth: Double
    var description: String

    static let defaultLine = LineDefinition(name: "Standard wire", colorHex: "31D7E8", wireSize: "14 AWG", displayWidth: 3, description: "General purpose connection")
}

private enum TargetKind: String, CaseIterable, Identifiable, Codable {
    case source, load, switchTarget, junction
    static let palette: [TargetKind] = [.source, .load, .switchTarget]
    var id: String { rawValue }
    var title: String { switch self { case .source: return "Source"; case .load: return "Load"; case .switchTarget: return "Switch"; case .junction: return "Junction" } }
    var symbol: String { switch self { case .source: return "bolt.fill"; case .load: return "lightbulb.fill"; case .switchTarget: return "switch.2"; case .junction: return "circle.fill" } }
    var defaultColorHex: String { switch self { case .source: return "FF9F43"; case .load: return "FFD166"; case .switchTarget: return "6EE7B7"; case .junction: return "31D7E8" } }
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

    var body: some View {
        Group {
            if target.kind == .junction {
                Circle().fill(connectedColor).frame(width: 18, height: 18).overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 2) }
            } else {
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                        RoundedRectangle(cornerRadius: 10).stroke(isSelected || isConnectionStart ? Color(hex: target.colorHex) : .white.opacity(0.18), lineWidth: isSelected || isConnectionStart ? 2 : 1)
                        Image(systemName: target.kind.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Color(hex: target.colorHex))
                    }.frame(width: 58, height: 48)
                    Text(target.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }.frame(width: 108, height: 76)
            }
        }
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
}

private struct SegmentHitArea: View {
    let path: Path
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View { path.stroke(isSelected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.001), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)).contentShape(path.strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))).onTapGesture(perform: onTap) }
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
