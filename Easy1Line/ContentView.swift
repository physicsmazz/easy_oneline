import SwiftUI
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private extension UTType {
    static let line = UTType(exportedAs: "com.mazzwebdesign.easy1line.line", conformingTo: .data)
}

private struct SchematicFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.line] }

    let document: SchematicDocument

    init(document: SchematicDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try JSONDecoder().decode(SchematicDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(document))
    }

    static func load(from url: URL) throws -> SchematicFileDocument {
        SchematicFileDocument(document: try JSONDecoder().decode(SchematicDocument.self, from: Data(contentsOf: url)))
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @State private var document = SchematicDocument.loadLast()
    @State private var savedDocuments = SchematicDocument.loadAll()
    @State private var canvasOffset = CGSize.zero
    @State private var canvasScale: CGFloat = 1
    @State private var canvasRotation = Angle.zero
    @State private var gestureStartScale: CGFloat?
    @State private var gestureStartRotation: Angle?
    @State private var panStart = CGSize.zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var targetDragStartCanvasOffset: CGSize?
    @State private var activeTargetDragIDs: [UUID] = []
    @State private var targetDragStartRoutes: [UUID: [CGPoint]] = [:]
    @State private var draggingTargetID: UUID?
    @State private var segmentDragStartOffsets: [UUID: CGFloat] = [:]
    @State private var selectedSegmentSectionIndex: Int?
    @State private var segmentDragStartPoints: [UUID: [CGPoint]] = [:]
    @State private var selectedTargetIDs: [UUID] = []
    @State private var connectionMode = false
    @State private var connectionModeTargetIDs: [UUID] = []
    @AppStorage("targetsPanelExpanded") private var targetsPanelExpanded = true
    @State private var selectedSegmentID: UUID?
    @State private var selectedSegmentIDs: Set<UUID> = []
    @State private var selectedConnectionSlots: [UUID: Int] = [:]
    @AppStorage("showConnectionNames") private var showConnectionNames = true
    @AppStorage("showWireLengths") private var showWireLengths = true
    @AppStorage("showWireNames") private var showWireNames = true
    @AppStorage("showWireSizes") private var showWireSizes = false
    @AppStorage("showWireMaterials") private var showWireMaterials = false
    @AppStorage("showWireCoverings") private var showWireCoverings = false
    @AppStorage("showWireNetNames") private var showWireNetNames = false
    @AppStorage("wireAlignmentTolerance") private var wireAlignmentTolerance: Double = 5
    @AppStorage("connectionStubLength") private var connectionStubLength: Double = 15
    @AppStorage("wireBridgesEnabled") private var wireBridgesEnabled = true
    @AppStorage("snapToGrid") private var snapToGrid = true
    private let linePadding: CGFloat = 16
    @State private var showLibrary = false
    @State private var showCloudLibrary = false
    @State private var cloudDrawings: [CloudDrawingChoice] = []
    @State private var showLineLibrary = false
    @State private var lineLibrarySearch = ""
    @State private var showTargetLibrary = false
    @State private var showNetlist = false
    @State private var selectedLineDefinitionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var connectionDragStartAngles: [String: Double] = [:]
    @State private var editingConnectionPoints = false
    @State private var cloudStatus = ""
    @State private var saveNameDraft = ""
    @State private var pendingSaveToCloud = false
    @State private var showSaveNamePrompt = false
    @State private var showFileExporter = false
    @State private var pdfShareItem: PDFShareItem?
    @State private var showFileImporter = false
    @State private var showInfoPanel = false
    @State private var doubleTapInfoTargetIDs: [UUID] = []
    @State private var doubleTapInfoSegmentIDs: Set<UUID> = []
    @State private var editorSize = CGSize.zero
    @State private var dockDragKind: TargetKind?
    @State private var dockDragLocation = CGPoint.zero
    @AppStorage("targetsPanelListHeight") private var targetsPanelListHeight: Double = 460
    @AppStorage("targetsPanelWidth") private var targetsPanelWidth: Double = 250
    @AppStorage("canvasLocked") private var canvasLocked = false
    @State private var targetsPanelResizeStart: Double?
    @State private var targetsPanelWidthResizeStart: Double?
    @State private var splitCandidateSegmentID: UUID?
    @State private var wireAlignmentPreviewSegmentIDs: Set<UUID> = []
    @State private var targetNameDraft = ""
    @State private var targetNameEditingID: UUID?
    @State private var selectionBoxOffset = CGSize.zero
    @State private var selectionBoxDragStart: CGSize?
    @State private var showDeleteWarning = false
    @State private var wireLabelDragStartPositions: [UUID: Double] = [:]
    @State private var showNewDrawingWarning = false
    @State private var pendingNewDrawingAfterSave = false

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

            if let dockDragKind {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                        .frame(width: 72, height: 62)
                    Image(systemName: dockDragKind.symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color(hex: dockDragKind.defaultColorHex))
                }
                .shadow(color: .black.opacity(0.35), radius: 12)
                .allowsHitTesting(false)
                .position(dockDragLocation)
                .zIndex(1200)
            }

            header
                .zIndex(1000)

            if inspectorVisible {
                inspector
                    .padding(.trailing, 20)
                    .padding(.top, 84)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if !inspectorVisible, let selectionAnchor = selectionBoxAnchor, editorSize != .zero {
                selectionBox
                    .position(selectionBoxPosition(near: selectionAnchor))
                    .offset(selectionBoxOffset)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if selectionBoxDragStart == nil { selectionBoxDragStart = selectionBoxOffset }
                                let start = selectionBoxDragStart ?? selectionBoxOffset
                                selectionBoxOffset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                            }
                            .onEnded { _ in selectionBoxDragStart = nil }
                    )
                    .zIndex(900)
            }

            if showLibrary {
                libraryPanel
                    .padding(.top, 84)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if showCloudLibrary {
                cloudLibraryPanel
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

            if showNetlist {
                netlistPanel
                    .padding(.top, 84)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if connectionMode {
                Rectangle()
                    .stroke(.yellow, lineWidth: 4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(900)
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
        .alert("Name this schematic", isPresented: $showSaveNamePrompt) {
            TextField("Schematic name", text: $saveNameDraft)
            Button("Save") { commitNamedSave() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteWarningTitle, isPresented: $showDeleteWarning, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelectedContent() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("New drawing will clear everything currently on screen.", isPresented: $showNewDrawingWarning, titleVisibility: .visible) {
            Button("Save First") {
                pendingNewDrawingAfterSave = true
                promptForSaveName(toCloud: false)
            }
            Button("Discard", role: .destructive) { startNewDrawing() }
            Button("Cancel", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: SchematicFileDocument(document: document),
            contentType: .line,
            defaultFilename: document.name
        ) { result in
            if case .failure(let error) = result { cloudStatus = "Export failed: \(error.localizedDescription)" }
        }
        .sheet(item: $pdfShareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.line]) { result in
            do {
                let url = try result.get()
                document = try SchematicFileDocument.load(from: url).document
                cloudStatus = "Imported schematic"
            } catch {
                cloudStatus = "Import failed: \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedTargetIDs) { _, ids in
            guard let id = ids.last, let target = target(with: id) else {
                targetNameEditingID = nil
                targetNameDraft = ""
                return
            }
            targetNameEditingID = id
            targetNameDraft = target.name
        }
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
                    .frame(width: 150)
                if !cloudStatus.isEmpty {
                    Text(cloudStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
            Menu("File") {
                Button("Drawings") { showLibrary.toggle() }
                Button("New Drawing") { showNewDrawingWarning = true }
                Button("Save locally") { promptForSaveName(toCloud: false) }
                Button("Export .line") { showFileExporter = true }
                Button("Export PDF") { preparePDFShare() }
                Button("Import .line") { showFileImporter = true }
                Button("Save to cloud") { promptForSaveName(toCloud: true) }
                Button("Load from cloud") { Task { await loadCloudDrawings() } }
                Button("View netlist") { showNetlist.toggle() }
            }
            .buttonStyle(EditorButtonStyle())

            Menu("Libraries") {
                Button("Wires") { showLineLibrary.toggle() }
                Button("Targets") { showTargetLibrary.toggle() }
                Button("Sync libraries") { Task { await syncLibraries() } }
            }
            .buttonStyle(EditorButtonStyle())

            Button(snapToGrid ? "Snap: On" : "Snap: Off") { snapToGrid.toggle() }
                .buttonStyle(EditorButtonStyle(isActive: snapToGrid))

            Button(wireBridgesEnabled ? "Bridges: On" : "Bridges: Off") { wireBridgesEnabled.toggle() }
                .buttonStyle(EditorButtonStyle(isActive: wireBridgesEnabled))

            Button(showConnectionNames ? "Pins: On" : "Pins: Off") { showConnectionNames.toggle() }
                .buttonStyle(EditorButtonStyle(isActive: showConnectionNames))
                .accessibilityLabel("Show connection names")

            Menu("Labels") {
                Toggle("Wire names", isOn: $showWireNames)
                Toggle("Lengths", isOn: $showWireLengths)
                Toggle("Wire sizes", isOn: $showWireSizes)
                Toggle("Materials", isOn: $showWireMaterials)
                Toggle("Coverings", isOn: $showWireCoverings)
                Toggle("Net names", isOn: $showWireNetNames)
            }
            .buttonStyle(EditorButtonStyle(isActive: showWireLabels))
            .accessibilityLabel("Configure wire labels")

            Button("Info") { showInfoPanel.toggle() }
                .buttonStyle(EditorButtonStyle(isActive: showInfoPanel))
                .accessibilityLabel("Show item information")

            Button(connectionMode ? "Exit Connect" : "Connect") { toggleConnectionMode() }
                .buttonStyle(EditorButtonStyle(isActive: connectionMode))
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                    Text("TARGETS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Image(systemName: targetsPanelExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(targetsPanelExpanded ? "Collapse targets" : "Expand targets")

            if targetsPanelExpanded {
                ScrollView {
                    ForEach(TargetKind.palette) { kind in
                        PaletteItem(kind: kind)
                            .contentShape(Rectangle())
                            .onTapGesture { addTarget(kind) }
                            .overlay(alignment: .trailing) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 48, height: 38)
                                    .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(RoundedRectangle(cornerRadius: 6))
                                    .gesture(
                                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                            .onChanged { value in
                                                dockDragKind = kind
                                                dockDragLocation = value.location
                                                splitCandidateSegmentID = editorSize == .zero ? nil : splitCandidate(at: canvasDropPoint(value.location, canvasSize: editorSize), excluding: nil)?.segment.id
                                            }
                                            .onEnded { value in
                                                dockDragKind = nil
                                                splitCandidateSegmentID = nil
                                                placeDockItem(kind, at: value.location)
                                            }
                                    )
                                    .accessibilityLabel("Drag \(kind.title) to canvas")
                            }
                    }
                }
                .frame(height: targetsPanelListHeight)

                Text("Drag to place\nTap to add at center")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                if targetsPanelResizeStart == nil { targetsPanelResizeStart = targetsPanelListHeight }
                                targetsPanelListHeight = min(max((targetsPanelResizeStart ?? targetsPanelListHeight) + value.translation.height, 80), 900)
                            }
                            .onEnded { _ in targetsPanelResizeStart = nil }
                    )
                    .accessibilityLabel("Resize targets panel")
            }
        }
        .padding(14)
        .frame(width: targetsPanelWidth)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1) }
        .overlay(alignment: .trailing) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 4, height: 42)
                .padding(.trailing, 4)
                .contentShape(Rectangle().size(width: 24, height: 64))
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if targetsPanelWidthResizeStart == nil { targetsPanelWidthResizeStart = targetsPanelWidth }
                            targetsPanelWidth = min(max((targetsPanelWidthResizeStart ?? targetsPanelWidth) + value.translation.width, 170), 360)
                        }
                        .onEnded { _ in targetsPanelWidthResizeStart = nil }
                )
                .accessibilityLabel("Resize targets panel width")
        }
    }

    private func makePDFData() -> Data {
        let contentBounds = pdfContentBounds()
        let imageRenderer = ImageRenderer(content: pdfCanvas(in: contentBounds.size, origin: contentBounds.origin))
        imageRenderer.scale = 2
        guard let image = imageRenderer.uiImage, let cgImage = image.cgImage else { return Data() }

        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595)
        let imageRect = AVMakeRect(aspectRatio: CGSize(width: cgImage.width, height: cgImage.height), insideRect: pageRect.insetBy(dx: 24, dy: 24))
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(pageRect)
            UIImage(cgImage: cgImage).draw(in: imageRect)
        }
    }

    private func preparePDFShare() {
        let filename = document.name.replacingOccurrences(of: "/", with: "-") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try makePDFData().write(to: url, options: .atomic)
            pdfShareItem = PDFShareItem(url: url)
        } catch {
            cloudStatus = "PDF share failed: \(error.localizedDescription)"
        }
    }

    private func pdfContentBounds() -> CGRect {
        var bounds = CGRect.null
        for target in document.targets {
            let halfWidth: CGFloat = target.kind == .junction ? 9 : target.isCompact ? 20 : 54
            let halfHeight: CGFloat = target.kind == .junction ? 9 : target.isCompact ? 20 : 38
            let scale = CGFloat(target.scale)
            let rect = CGRect(
                x: target.position.x - halfWidth * scale,
                y: target.position.y - halfHeight * scale,
                width: halfWidth * 2 * scale,
                height: halfHeight * 2 * scale
            )
            bounds = bounds.union(rect)
        }
        for segment in document.segments {
            guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
            for point in points {
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
        if bounds.isNull { return CGRect(x: 0, y: 0, width: 1000, height: 700) }
        return bounds.insetBy(dx: -40, dy: -40)
    }

    private func pdfCanvas(in size: CGSize, origin: CGPoint) -> some View {
        ZStack {
            GridBackground()
            ZStack {
                Canvas { context, _ in
                    for segment in document.segments {
                        guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
                        let path = orthogonalPath(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                        context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.displayWidth, lineCap: .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)

                ForEach(document.targets) { target in
                    TargetView(
                        target: target,
                        isSelected: false,
                        selectionOrder: nil,
                        isConnectionStart: false,
                        connectedColor: connectedColor(for: target.id),
                        connectedColors: connectedColors(for: target.id),
                        occupiedSlots: occupiedSlots(for: target.id),
                        selectedSlots: [],
                        connectionNames: target.connectionNames,
                        showConnectionNames: showConnectionNames,
                        onSelectConnectionPoint: { _ in },
                        editingConnectionPoints: false,
                        onMoveConnectionPoint: { _, _ in },
                        onEndConnectionPointMove: { _ in }
                    )
                    .position(target.position)
                }
            }
            .offset(x: -origin.x, y: -origin.y)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func schematicCanvas(in size: CGSize) -> some View {
        ZStack {
            GridBackground()
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture {
                    selectedTargetIDs.removeAll()
                    selectedConnectionSlots.removeAll()
                    selectedSegmentID = nil
                    selectedSegmentIDs.removeAll()
                }

            ZStack {
            Canvas { context, _ in
                context.translateBy(x: 5000 - size.width / 2, y: 5000 - size.height / 2)
                for segment in document.segments {
                    guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
                    let path = orthogonalPath(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                    if selectedSegmentIDs.contains(segment.id) {
                        context.stroke(path, with: .color(.cyan.opacity(0.35)), style: StrokeStyle(lineWidth: segment.displayWidth + 12, lineCap: .round, lineJoin: .round))
                    }
                    if wireAlignmentPreviewSegmentIDs.contains(segment.id) {
                        context.stroke(path, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.displayWidth, lineCap: .round, lineJoin: .round))
                }

                if wireBridgesEnabled {
                    for firstIndex in document.segments.indices {
                    guard let firstStart = target(with: document.segments[firstIndex].startID), let firstEnd = target(with: document.segments[firstIndex].endID) else { continue }
                    let firstPoints = orthogonalPoints(for: document.segments[firstIndex], from: firstStart, to: firstEnd, avoiding: document.targets.filter { $0.id != firstStart.id && $0.id != firstEnd.id })
                    for secondIndex in document.segments.indices.dropFirst(firstIndex + 1) {
                        guard let secondStart = target(with: document.segments[secondIndex].startID), let secondEnd = target(with: document.segments[secondIndex].endID) else { continue }
                        let secondPoints = orthogonalPoints(for: document.segments[secondIndex], from: secondStart, to: secondEnd, avoiding: document.targets.filter { $0.id != secondStart.id && $0.id != secondEnd.id })
                        for crossing in crossings(between: firstPoints, and: secondPoints) {
                            let bridge = bridgePath(at: crossing.point, overHorizontal: !crossing.firstIsHorizontal)
                            let bridgeColor = document.segments[secondIndex].color
                            context.stroke(bridge, with: .color(Color(red: 0.07, green: 0.09, blue: 0.105)), style: StrokeStyle(lineWidth: document.segments[secondIndex].displayWidth + 7, lineCap: .round, lineJoin: .round))
                            context.stroke(bridge, with: .color(bridgeColor), style: StrokeStyle(lineWidth: document.segments[secondIndex].displayWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                    }
                }
            }
            .allowsHitTesting(true)
            .frame(width: 10000, height: 10000)
            .position(x: size.width / 2, y: size.height / 2)

            ForEach(document.segments) { segment in
                if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                    let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                    ForEach(0..<(points.count - 1), id: \.self) { sectionIndex in
                        if sectionIndex > 0 && sectionIndex + 1 < points.count - 1 {
                            SegmentHitArea(path: sectionPath(from: points[sectionIndex], to: points[sectionIndex + 1]), isSelected: selectedSegmentIDs.contains(segment.id), isSectionSelected: selectedSegmentID == segment.id && selectedSegmentSectionIndex == sectionIndex, onDrag: { translation in
                                moveSegmentSection(segment.id, sectionIndex: sectionIndex, translation: CGSize(width: translation.width / canvasScale, height: translation.height / canvasScale))
                            }, onEndDrag: {
                                segmentDragStartPoints.removeValue(forKey: segment.id)
                                finalizeWireSectionDrag(segment.id)
                            }, onTap: {
                                if selectedSegmentID == segment.id {
                                    selectedSegmentSectionIndex = sectionIndex
                                } else {
                                    selectedSegmentIDs.insert(segment.id)
                                    selectedSegmentID = segment.id
                                    selectedSegmentSectionIndex = nil
                                }
                                selectedTargetIDs.removeAll()
                            }, onDoubleTap: {
                                openWireInfo(segment, sectionIndex: sectionIndex)
                            })
                        } else {
                            // Stub sections: keep the hit area clear of the pin so pin taps aren't swallowed by the wire.
                            let pinEnd = sectionIndex == 0 ? points[sectionIndex] : points[sectionIndex + 1]
                            let farEnd = sectionIndex == 0 ? points[sectionIndex + 1] : points[sectionIndex]
                            let movableSectionIndex = sectionIndex == 0 ? 1 : max(1, points.count - 3)
                            SegmentHitArea(path: sectionPath(from: points[sectionIndex], to: points[sectionIndex + 1]), hitPath: sectionPath(from: trimmed(pinEnd, toward: farEnd, by: 4), to: farEnd), isSelected: selectedSegmentIDs.contains(segment.id), isSectionSelected: false, onDrag: { translation in
                                moveSegmentSection(segment.id, sectionIndex: movableSectionIndex, translation: CGSize(width: translation.width / canvasScale, height: translation.height / canvasScale))
                            }, onEndDrag: {
                                segmentDragStartPoints.removeValue(forKey: segment.id)
                                finalizeWireSectionDrag(segment.id)
                            }, onTap: {
                                selectedSegmentIDs.insert(segment.id)
                                selectedSegmentID = segment.id
                                selectedSegmentSectionIndex = nil
                                selectedTargetIDs.removeAll()
                            }, onDoubleTap: {
                                openWireInfo(segment, sectionIndex: sectionIndex)
                            })
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
                    connectionNames: target.connectionNames,
                    showConnectionNames: showConnectionNames,
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
                .onTapGesture(count: 2) {
                    openTargetInfo(target)
                }
            }

            if showWireLabels {
                ForEach(document.segments) { segment in
                    if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                        let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
                        wireLabel(segment, on: points)
                    }
                }
            }

            }
        .offset(canvasOffset)
        .scaleEffect(canvasScale, anchor: .center)
        .rotationEffect(canvasRotation)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { editorSize = size }
        .simultaneousGesture(MagnificationGesture().onChanged { value in
            guard !canvasLocked else { return }
            if gestureStartScale == nil { gestureStartScale = canvasScale }
            canvasScale = min(4, max(0.25, (gestureStartScale ?? 1) * value))
        }.onEnded { _ in
            gestureStartScale = nil
        })
        .simultaneousGesture(RotationGesture().onChanged { value in
            guard !canvasLocked else { return }
            if gestureStartRotation == nil { gestureStartRotation = canvasRotation }
            canvasRotation = (gestureStartRotation ?? .zero) + value
        }.onEnded { _ in
            gestureStartRotation = nil
        })
        .overlay(alignment: .topTrailing) {
            zoomControls
                .padding(.top, 88)
                .padding(.trailing, 24)
        }
        }
    }

    private func wireLabel(_ segment: SchematicSegment, on points: [CGPoint]) -> some View {
        let labelPoint = point(on: points, at: segment.labelPosition)
        let direction = direction(on: points, at: segment.labelPosition)
        let labelPointWithOffset = CGPoint(x: labelPoint.x - direction.dy / max(direction.length, 1) * 14, y: labelPoint.y + direction.dx / max(direction.length, 1) * 14)
        var angle = atan2(direction.dy, direction.dx)
        if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }
        let fields: [String] = [
            showWireNames ? segment.name : nil,
            showWireLengths ? "\(Int(pathLength(points).rounded())) px" : nil,
            showWireSizes ? segment.wireSize : nil,
            showWireMaterials ? segment.material : nil,
            showWireCoverings ? segment.covering : nil,
            showWireNetNames ? segment.netName : nil
        ].compactMap { $0 }
        return Text(fields.joined(separator: "\n"))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.7), in: Capsule())
            .rotationEffect(.radians(angle))
            .position(labelPointWithOffset)
            .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                let start = wireLabelDragStartPositions[segment.id] ?? segment.labelPosition
                wireLabelDragStartPositions[segment.id] = start
                guard let startTarget = target(with: segment.startID), let endTarget = target(with: segment.endID) else { return }
                let route = orthogonalPoints(for: segment, from: startTarget, to: endTarget, avoiding: [])
                let startPoint = point(on: route, at: start)
                let delta = canvasDelta(for: value.translation)
                let proposed = CGPoint(x: startPoint.x + delta.width, y: startPoint.y + delta.height)
                updateWireLabelPosition(segment.id, route: route, near: proposed)
            }.onEnded { _ in
                wireLabelDragStartPositions.removeValue(forKey: segment.id)
            })
            .allowsHitTesting(true)
    }

    private func point(on points: [CGPoint], at fraction: Double) -> CGPoint {
        let total = pathLength(points)
        guard total > 0 else { return points.first ?? .zero }
        var remaining = CGFloat(min(max(fraction, 0), 1)) * total
        for pair in zip(points, points.dropFirst()) {
            let length = hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            if remaining <= length {
                let ratio = length == 0 ? 0 : remaining / length
                return CGPoint(x: pair.0.x + (pair.1.x - pair.0.x) * ratio, y: pair.0.y + (pair.1.y - pair.0.y) * ratio)
            }
            remaining -= length
        }
        return points.last ?? .zero
    }

    private func direction(on points: [CGPoint], at fraction: Double) -> (dx: CGFloat, dy: CGFloat, length: CGFloat) {
        let currentPoint = point(on: points, at: fraction)
        let nextPoint = point(on: points, at: min(fraction + 0.01, 1))
        return (nextPoint.x - currentPoint.x, nextPoint.y - currentPoint.y, hypot(nextPoint.x - currentPoint.x, nextPoint.y - currentPoint.y))
    }

    private func updateWireLabelPosition(_ id: UUID, route: [CGPoint], near location: CGPoint) {
        guard let index = document.segments.firstIndex(where: { $0.id == id }) else { return }
        var bestFraction = 0.5
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let total = pathLength(route)
        var traversed: CGFloat = 0
        for pair in zip(route, route.dropFirst()) {
            let candidate = nearestPoint(on: [pair.0, pair.1], to: location)
            let segmentLength = hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            if candidate.distance < bestDistance {
                bestDistance = candidate.distance
                let along = traversed + hypot(candidate.point.x - pair.0.x, candidate.point.y - pair.0.y)
                bestFraction = total == 0 ? 0.5 : Double(along / total)
            }
            traversed += segmentLength
        }
        document.segments[index].labelPosition = min(max(bestFraction, 0), 1)
    }

    private var showWireLabels: Bool {
        showWireNames || showWireLengths || showWireSizes || showWireMaterials || showWireCoverings || showWireNetNames
    }

    private func placeDockItem(_ kind: TargetKind, at screenLocation: CGPoint) {
        guard editorSize != .zero else { return }
        let dropPoint = canvasDropPoint(screenLocation, canvasSize: editorSize)
        let snappedDropPoint = snapToGrid ? snappedPosition(dropPoint) : dropPoint
        let iconPoint = CGPoint(x: snappedDropPoint.x, y: snappedDropPoint.y + (kind == .junction ? 0 : 9))
        addTarget(kind, at: iconPoint)
        guard let id = document.targets.last?.id,
              let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
        document.targets[index].position = iconPoint
        splitSegmentIfNeeded(for: id)
    }

    private func canvasDropPoint(_ location: CGPoint, canvasSize: CGSize) -> CGPoint {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let translated = CGPoint(x: location.x - center.x - canvasOffset.width, y: location.y - center.y - canvasOffset.height)
        let inverseAngle = -canvasRotation.radians
        let rotated = CGPoint(
            x: translated.x * CGFloat(cos(inverseAngle)) - translated.y * CGFloat(sin(inverseAngle)),
            y: translated.x * CGFloat(sin(inverseAngle)) + translated.y * CGFloat(cos(inverseAngle))
        )
        return CGPoint(x: rotated.x / canvasScale + center.x, y: rotated.y / canvasScale + center.y)
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
                Button { canvasScale = max(0.25, canvasScale - 0.25) } label: { Text("−") }
                .buttonStyle(EditorButtonStyle())
                .help("Zoom out")
                .disabled(canvasLocked)
            Text("\(Int(canvasScale * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 44)
                Button { canvasScale = min(4, canvasScale + 0.25) } label: { Text("+") }
                .buttonStyle(EditorButtonStyle())
                .help("Zoom in")
                .disabled(canvasLocked)
            Button {
                canvasScale = 1
                canvasRotation = .zero
            } label: { Text("Reset") }
                .buttonStyle(EditorButtonStyle())
                .help("Reset zoom and rotation")
                .disabled(canvasLocked)
            Button { canvasLocked.toggle() } label: {
                Image(systemName: canvasLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(EditorButtonStyle(isActive: canvasLocked))
            .help(canvasLocked ? "Unlock canvas position and zoom" : "Lock canvas position and zoom")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !canvasLocked else { return }
                canvasOffset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
            }
            .onEnded { _ in panStart = canvasOffset }
    }

    private func targetDragGesture(for target: SchematicTarget, canvasSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard !editingConnectionPoints, !target.locked else { return }
                draggingTargetID = target.id
                guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
                if dragStartPositions[target.id] == nil {
                    activeTargetDragIDs = selectedTargetIDs.contains(target.id) ? selectedTargetIDs : [target.id]
                    targetDragStartCanvasOffset = canvasOffset
                    if !selectedTargetIDs.contains(target.id) {
                        selectedTargetIDs = [target.id]
                    }
                    targetDragStartRoutes.removeAll()
                    for targetID in activeTargetDragIDs {
                        guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }), !document.targets[targetIndex].locked else { continue }
                        dragStartPositions[targetID] = document.targets[targetIndex].position
                        captureAttachedRoutes(for: targetID)
                    }
                }
                guard let start = dragStartPositions[target.id] else { return }
                autoPanCanvasIfNeeded(for: document.targets[index].position)
                let delta = canvasDelta(for: value.translation)
                let canvasPan = CGSize(
                    width: (targetDragStartCanvasOffset?.width ?? canvasOffset.width) - canvasOffset.width,
                    height: (targetDragStartCanvasOffset?.height ?? canvasOffset.height) - canvasOffset.height
                )
                let panCompensation = canvasDelta(for: canvasPan)
                let groupDelta = CGSize(width: delta.width + panCompensation.width, height: delta.height + panCompensation.height)
                for targetID in activeTargetDragIDs {
                    guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }), let targetStart = dragStartPositions[targetID] else { continue }
                    let proposedPosition = CGPoint(x: targetStart.x + groupDelta.width, y: targetStart.y + groupDelta.height)
                    document.targets[targetIndex].position = snapToGrid ? snappedPosition(proposedPosition) : proposedPosition
                }
                updateAttachedRoutes(for: Set(activeTargetDragIDs), translation: groupDelta, onlyFullySelected: activeTargetDragIDs.count > 1)
                selectedSegmentID = nil
                selectedSegmentIDs.removeAll()
                splitCandidateSegmentID = connectionCount(for: target.id) == 0 && occupiedSlots(for: target.id).count + 2 <= document.targets[index].maxConnections
                    ? splitCandidate(at: document.targets[index].position, excluding: target.id)?.segment.id
                    : nil
            }
            .onEnded { _ in
                guard !target.locked else { return }
                dragStartPositions.removeValue(forKey: target.id)
                targetDragStartCanvasOffset = nil
                targetDragStartRoutes.removeAll()
                for targetID in activeTargetDragIDs {
                    snapTarget(targetID, canvasSize: canvasSize)
                    if connectionCount(for: targetID) == 0 {
                        splitSegmentIfNeeded(for: targetID)
                    }
                }
                dragStartPositions.removeAll()
                activeTargetDragIDs.removeAll()
                splitCandidateSegmentID = nil
                draggingTargetID = nil
            }
    }

    private func autoPanCanvasIfNeeded(for canvasPoint: CGPoint) {
        guard !canvasLocked, editorSize != .zero else { return }
        let screenPoint = screenPoint(forCanvas: canvasPoint)
        let edgeInset: CGFloat = 110
        let step: CGFloat = 8
        var offsetDelta = CGSize.zero
        if screenPoint.x < edgeInset { offsetDelta.width = step }
        else if screenPoint.x > editorSize.width - edgeInset { offsetDelta.width = -step }
        if screenPoint.y < 84 + edgeInset { offsetDelta.height = step }
        else if screenPoint.y > editorSize.height - edgeInset { offsetDelta.height = -step }
        canvasOffset.width += offsetDelta.width
        canvasOffset.height += offsetDelta.height
        panStart = canvasOffset
    }

    private func canvasDelta(for translation: CGSize) -> CGSize {
        let angle = -canvasRotation.radians
        let rotated = CGSize(
            width: translation.width * CGFloat(cos(angle)) - translation.height * CGFloat(sin(angle)),
            height: translation.width * CGFloat(sin(angle)) + translation.height * CGFloat(cos(angle))
        )
        return CGSize(width: rotated.width / canvasScale, height: rotated.height / canvasScale)
    }

    private func targetTapped(_ target: SchematicTarget) {
        if connectionMode {
            handleConnectionModeTap(target)
            return
        }
        if selectedTargetIDs.contains(target.id) {
            cycleConnectionPoint(for: target)
            return
        }
        selectTarget(target)
    }

    private func openTargetInfo(_ target: SchematicTarget) {
        if !selectedTargetIDs.contains(target.id) {
            selectedTargetIDs = [target.id]
        }
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        selectedConnectionSlots.removeAll()
        doubleTapInfoTargetIDs = selectedTargetIDs
        doubleTapInfoSegmentIDs = []
    }

    private func openWireInfo(_ wire: SchematicSegment, sectionIndex: Int) {
        selectedTargetIDs.removeAll()
        selectedSegmentIDs = [wire.id]
        selectedSegmentID = wire.id
        selectedSegmentSectionIndex = sectionIndex
        doubleTapInfoTargetIDs = []
        doubleTapInfoSegmentIDs = [wire.id]
    }

    // Inspector opened by double-tap stays only while that same selection is current.
    private var doubleTapInfoIsCurrent: Bool {
        (!doubleTapInfoTargetIDs.isEmpty || !doubleTapInfoSegmentIDs.isEmpty)
            && doubleTapInfoTargetIDs == selectedTargetIDs
            && doubleTapInfoSegmentIDs == selectedSegmentIDs
    }

    private func toggleConnectionMode() {
        connectionMode.toggle()
        connectionModeTargetIDs.removeAll()
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
    }

    private func handleConnectionModeTap(_ target: SchematicTarget) {
        guard connectionModeTargetIDs.last != target.id else { return }
        if let previousID = connectionModeTargetIDs.last {
            connectTargets(previousID, target.id)
        }
        connectionModeTargetIDs.append(target.id)
        selectedTargetIDs = [target.id]
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
        editingConnectionPoints = false
        if let selectedIndex = selectedTargetIDs.firstIndex(of: target.id) {
            selectedTargetIDs.remove(at: selectedIndex)
        } else {
            selectedTargetIDs.append(target.id)
        }
    }

    private func selectConnectionPoint(targetID: UUID, slot: Int) {
        // Wire-first: with a wire selected, tapping a free pin on one of its end targets moves that end.
        if let wire = selectedSegment, wire.startID == targetID || wire.endID == targetID,
           let index = document.segments.firstIndex(where: { $0.id == wire.id }),
           !occupiedSlots(for: targetID).contains(slot) {
            if wire.startID == targetID { document.segments[index].startSlot = slot } else { document.segments[index].endSlot = slot }
            document.segments[index].routePoints.removeAll()
            return
        }
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        if !selectedTargetIDs.contains(targetID) {
            selectedTargetIDs.append(targetID)
        }
        if let previousSlot = selectedConnectionSlots[targetID], previousSlot != slot,
           !occupiedSlots(for: targetID).contains(slot) {
            reassignConnectionPoint(targetID: targetID, from: previousSlot, to: slot)
        }
        selectedConnectionSlots[targetID] = slot
    }

    private func reassignConnectionPoint(targetID: UUID, from oldSlot: Int, to newSlot: Int) {
        for index in document.segments.indices {
            if document.segments[index].startID == targetID && document.segments[index].startSlot == oldSlot {
                document.segments[index].startSlot = newSlot
                document.segments[index].routePoints.removeAll()
            }
            if document.segments[index].endID == targetID && document.segments[index].endSlot == oldSlot {
                document.segments[index].endSlot = newSlot
                document.segments[index].routePoints.removeAll()
            }
        }
    }

    private func connectSelectedTargets() {
        let ids = Array(selectedTargetIDs)
        guard ids.count >= 2 else { return }
        for pairIndex in 0..<(ids.count - 1) {
            let startID = ids[pairIndex]
            let endID = ids[pairIndex + 1]
            connectTargets(startID, endID, startSlot: selectedConnectionSlots[startID], endSlot: selectedConnectionSlots[endID])
        }
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
    }

    private func connectTargets(_ startID: UUID, _ endID: UUID, startSlot: Int? = nil, endSlot: Int? = nil) {
        guard let resolvedStartSlot = startSlot ?? closestAvailableSlot(for: startID, to: endID),
              let resolvedEndSlot = endSlot ?? closestAvailableSlot(for: endID, to: startID),
              !occupiedSlots(for: startID).contains(resolvedStartSlot),
              !occupiedSlots(for: endID).contains(resolvedEndSlot),
              !document.segments.contains(where: { ($0.startID == startID && $0.endID == endID) || ($0.startID == endID && $0.endID == startID) }) else { return }
        let line = selectedLineDefinition ?? document.lineDefinitions.first ?? LineDefinition.defaultLine
        document.segments.append(SchematicSegment(startID: startID, endID: endID, startSlot: resolvedStartSlot, endSlot: resolvedEndSlot, name: line.name, colorHex: line.colorHex, wireSize: line.wireSize, material: line.material.rawValue, displayWidth: line.displayWidth, description: line.description))
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

    private func toggleTargetLock(_ target: SchematicTarget) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        document.targets[index].locked.toggle()
    }

    private func deleteTargetPreservingWire(_ target: SchematicTarget) {
        let attached = document.segments.filter { $0.startID == target.id || $0.endID == target.id }
        if attached.count == 2 {
            let first = attached[0]
            let second = attached[1]
            let firstOtherID = first.startID == target.id ? first.endID : first.startID
            let secondOtherID = second.startID == target.id ? second.endID : second.startID
            if firstOtherID != secondOtherID {
                guard let firstOther = self.target(with: firstOtherID), let secondOther = self.target(with: secondOtherID) else { return }
                let firstOuterSlot = first.startID == target.id ? first.endSlot : first.startSlot
                let secondOuterSlot = second.startID == target.id ? second.endSlot : second.startSlot
                let startPoint = connectionPoint(for: firstOther, slot: firstOuterSlot)
                let endPoint = connectionPoint(for: secondOther, slot: secondOuterSlot)
                let startEscape = escapePoint(for: firstOther, slot: firstOuterSlot ?? 0, toward: secondOther)
                let endEscape = escapePoint(for: secondOther, slot: secondOuterSlot ?? 0, toward: firstOther)
                let obstacles = document.targets.filter { $0.id != target.id && $0.id != firstOtherID && $0.id != secondOtherID }.map(obstacleRect(for:))
                let midX = (startEscape.x + endEscape.x) / 2
                let midY = (startEscape.y + endEscape.y) / 2
                let candidates = [
                    [startEscape, CGPoint(x: endEscape.x, y: startEscape.y), endEscape],
                    [startEscape, CGPoint(x: startEscape.x, y: endEscape.y), endEscape],
                    [startEscape, CGPoint(x: midX, y: startEscape.y), CGPoint(x: midX, y: endEscape.y), endEscape],
                    [startEscape, CGPoint(x: startEscape.x, y: midY), CGPoint(x: endEscape.x, y: midY), endEscape]
                ].map { orthogonalizedPoints($0) }.filter { pointsAreClear($0, from: obstacles) }
                let routePoints: [CGPoint]
                if let middleRoute = candidates.min(by: { pathLength($0) < pathLength($1) }) {
                    routePoints = orthogonalizedPoints([startPoint, startEscape] + middleRoute.dropFirst().dropLast() + [endEscape, endPoint])
                } else {
                    routePoints = []
                }
                let replacement = SchematicSegment(
                    startID: firstOtherID,
                    endID: secondOtherID,
                    startSlot: firstOuterSlot,
                    endSlot: secondOuterSlot,
                    name: first.name,
                    colorHex: first.colorHex,
                    wireSize: first.wireSize,
                    material: first.material,
                    covering: first.covering,
                    netName: first.netName,
                    displayWidth: first.displayWidth,
                    description: first.description,
                    routePoints: routePoints
                )
                document.segments.removeAll { $0.id == first.id || $0.id == second.id }
                document.segments.append(replacement)
                document.targets.removeAll { $0.id == target.id }
                selectedTargetIDs.removeAll()
                selectedConnectionSlots.removeAll()
                return
            }
        }
        document.segments.removeAll { $0.startID == target.id || $0.endID == target.id }
        document.targets.removeAll { $0.id == target.id }
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
    }

    private var selectedTargetsAreLocked: Bool {
        !selectedTargetIDs.isEmpty && selectedTargetIDs.allSatisfy { target(with: $0)?.locked == true }
    }

    private func toggleSelectedTargetLocks() {
        let shouldLock = !selectedTargetsAreLocked
        for index in document.targets.indices where selectedTargetIDs.contains(document.targets[index].id) {
            document.targets[index].locked = shouldLock
        }
    }

    private func promptForSaveName(toCloud: Bool) {
        saveNameDraft = document.name
        pendingSaveToCloud = toCloud
        showSaveNamePrompt = true
    }

    private func commitNamedSave() {
        let trimmed = saveNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { document.name = trimmed }
        if pendingSaveToCloud {
            Task { await saveToCloud() }
        } else {
            saveCurrent()
        }
        if pendingNewDrawingAfterSave {
            pendingNewDrawingAfterSave = false
            startNewDrawing()
        }
    }

    private func startNewDrawing() {
        document = SchematicDocument(name: "Untitled schematic")
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
        selectedSegmentIDs.removeAll()
        selectedSegmentID = nil
        selectedSegmentSectionIndex = nil
        canvasOffset = .zero
        canvasScale = 1
        canvasRotation = .zero
        selectionBoxOffset = .zero
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
            cloudStatus = "Cloud save failed: \(cloudErrorText(error))"
        }
    }

    private func loadCloudDrawings() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            let remoteDrawings = try await store.loadDrawingData()
            cloudDrawings = remoteDrawings.map { CloudDrawingChoice(id: $0.id, name: $0.name, data: $0.data) }
            showCloudLibrary = true
            guard !remoteDrawings.isEmpty else {
                cloudStatus = "No cloud drawings"
                return
            }
        } catch {
            cloudStatus = "Cloud list failed: \(cloudErrorText(error))"
        }
    }

    private func loadCloudDrawing(_ drawing: CloudDrawingChoice) {
        do {
            document = try JSONDecoder().decode(SchematicDocument.self, from: drawing.data)
            showCloudLibrary = false
            cloudStatus = "Loaded from cloud: \(drawing.name)"
        } catch {
            cloudStatus = "Cloud drawing invalid: \(error.localizedDescription)"
        }
    }

    private func syncLibraries() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            let targetTypes = try await store.loadTargetTypes()
            let conductors = try await store.loadConductorCatalog()
            let syncedTargets = targetTypes.compactMap { record -> TargetDefinition? in
                guard let kind = TargetKind(rawValue: record.kind) else { return nil }
                return TargetDefinition(kind: kind, name: record.name, maxConnections: record.maxConnections ?? 2, colorHex: record.colorHex, symbol: record.symbol ?? kind.symbol, imageData: nil, connectionAngles: record.connectionAngles, scale: 1)
            }
            if !syncedTargets.isEmpty { document.targetDefinitions = syncedTargets }
            let syncedLines = conductors.compactMap { record -> LineDefinition? in
                guard let material = ConductorMaterial(rawValue: record.material) else { return nil }
                return LineDefinition(name: "\(material.rawValue) \(record.wireSize)", colorHex: material.defaultColorHex, wireSize: record.wireSize, material: material, displayWidth: 3, description: "Synced conductor")
            }
            if !syncedLines.isEmpty { document.lineDefinitions = syncedLines }
            cloudStatus = "Libraries synced"
        } catch {
            cloudStatus = "Library sync failed: \(cloudErrorText(error))"
        }
    }

    private func cloudErrorText(_ error: Error) -> String {
        if case let SupabaseDrawingStore.StoreError.requestFailed(code, body) = error {
            return "HTTP \(code) \(body.prefix(120))"
        }
        return error.localizedDescription
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

    private var cloudLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLOUD DRAWINGS").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { Task { await loadCloudDrawings() } } label: { Image(systemName: "arrow.clockwise") }.foregroundStyle(.cyan)
                Button { showCloudLibrary = false } label: { Image(systemName: "xmark") }.foregroundStyle(.white.opacity(0.65))
            }
            if cloudDrawings.isEmpty {
                Text("No cloud drawings yet").font(.caption).foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(cloudDrawings) { drawing in
                            Button { loadCloudDrawing(drawing) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(drawing.name).font(.system(size: 13, weight: .semibold))
                                    Text(drawing.id.uuidString.prefix(8)).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.4))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(9)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var lineLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WIRE LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { document.lineDefinitions.append(.defaultLine) } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
                Button { showLineLibrary = false } label: { Image(systemName: "xmark") }.foregroundStyle(.white.opacity(0.65))
            }
            TextField("Search material or wire size", text: $lineLibrarySearch)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(ConductorMaterial.allCases) { material in
                        let materialLines = document.lineDefinitions.filter {
                            $0.material == material && (lineLibrarySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(lineLibrarySearch) || $0.wireSize.localizedCaseInsensitiveContains(lineLibrarySearch))
                        }
                        if !materialLines.isEmpty {
                            Text(material.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 5)

                            ForEach(materialLines) { line in
                                Button {
                                    selectedLineDefinitionID = line.id
                                    if selectedSegmentIDs.count > 1 {
                                        applyLineDefinition(line, to: selectedSegmentIDs)
                                    } else if let selectedSegmentID {
                                        applyLineDefinition(line, to: selectedSegmentID)
                                    } else {
                                        applyLineDefinition(line, to: selectedSegmentIDs)
                                    }
                                    showLineLibrary = false
                                } label: {
                                    HStack(spacing: 9) {
                                        Circle().fill(Color(hex: line.colorHex)).frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(line.wireSize).font(.system(size: 12, weight: .semibold))
                                            Text("\(line.displayWidth, specifier: "%.1f") pt").font(.caption2).foregroundStyle(.white.opacity(0.4))
                                        }
                                        Spacer()
                                        if selectedLineDefinitionID == line.id { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 34)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .padding(12)
        .frame(width: 320, height: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var netlistPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NETLIST").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                ShareLink(item: netlistText, subject: Text("Easy1Line netlist"), message: Text("SPICE-style netlist")) {
                    Text("Export")
                }
                .buttonStyle(.borderedProminent)
                Button { showNetlist = false } label: { Image(systemName: "xmark") }
                    .foregroundStyle(.white.opacity(0.65))
            }
            ScrollView {
                Text(netlistText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)
        }
        .padding(14)
        .frame(width: 360, height: 540)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var netlistText: String {
        document.targets.map { target in
            let pins = (0..<target.maxConnections).map { slot in
                let pinName = target.connectionNames.indices.contains(slot) ? target.connectionNames[slot] : defaultConnectionName(for: slot)
                let netNames = document.segments.compactMap { segment -> String? in
                    guard (segment.startID == target.id && segment.startSlot == slot) || (segment.endID == target.id && segment.endSlot == slot) else { return nil }
                    return segment.netName
                }
                return "\(pinName)=\((netNames.first ?? "NC"))"
            }.joined(separator: " ")
            return "\(target.name) \(pins)"
        }.joined(separator: "\n")
    }

    private var deleteWarningTitle: String {
        if !selectedTargetIDs.isEmpty {
            return selectedTargetIDs.count == 1 ? "Delete selected item?" : "Delete selected items?"
        }
        return selectedSegmentIDs.count == 1 ? "Delete selected wire?" : "Delete selected wires?"
    }

    private func deleteSelectedContent() {
        if selectedTargetIDs.count == 1,
           let targetID = selectedTargetIDs.first,
           let target = target(with: targetID) {
            deleteTargetPreservingWire(target)
        } else if !selectedTargetIDs.isEmpty {
            let targetIDs = Set(selectedTargetIDs)
            document.segments.removeAll { targetIDs.contains($0.startID) || targetIDs.contains($0.endID) }
            document.targets.removeAll { targetIDs.contains($0.id) }
        } else {
            document.segments.removeAll { selectedSegmentIDs.contains($0.id) }
        }
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
        selectedSegmentIDs.removeAll()
        selectedSegmentID = nil
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
                Text("WIRES").inspectorLabel()
                Text("\(selectedSegmentIDs.count) wires selected").font(.headline)
                if let primary = selectedSegment ?? selectedSegmentIDs.compactMap({ segment(with: $0) }).first {
                    wireEditor(primary, compact: true, applyToAll: true)
                }
                Button {
                    showLineLibrary = true
                } label: {
                    Label("Choose wire type", systemImage: "list.bullet.rectangle")
                }
                Button(role: .destructive) {
                    showDeleteWarning = true
                } label: {
                    Label("Delete wires", systemImage: "trash")
                }
            } else if let segment = selectedSegment {
                Text("WIRE").inspectorLabel()
                wireEditor(segment)
                Button {
                    splitWire(segment)
                } label: {
                    Label("Split wire", systemImage: "scissors")
                }
                Button(role: .destructive) {
                    showDeleteWarning = true
                } label: {
                    Label("Delete wire", systemImage: "trash")
                }
                /*
                TextField("Wire name", text: segmentBinding(segment).name)
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
                    Label("Choose wire type", systemImage: "list.bullet.rectangle")
                }
                Button {
                    document.lineDefinitions.append(LineDefinition(name: segment.name, colorHex: segment.colorHex, wireSize: segment.wireSize, material: ConductorMaterial(rawValue: segment.material) ?? .copper, displayWidth: segment.displayWidth, description: segment.description))
                } label: {
                    Label("Add to wire library", systemImage: "plus.circle")
                }
                Button(role: .destructive) {
                    document.segments.removeAll { $0.id == segment.id }
                    selectedSegmentIDs.removeAll()
                    selectedSegmentID = nil
                } label: { Label("Delete wire", systemImage: "trash") }
                */
            } else if selectedTargetIDs.count == 1, let target = target(with: selectedTargetIDs.first!) {
                Text("TARGET").inspectorLabel()
                TextField("Item name", text: $targetNameDraft).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") { saveTargetName(target) }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { cancelTargetName(target) }
                        .buttonStyle(.bordered)
                }
                Button {
                    rotateTarget(target, by: 90)
                } label: {
                    Label("Rotate 90°", systemImage: "rotate.right")
                }
                Button {
                    editingConnectionPoints.toggle()
                } label: {
                    Label(editingConnectionPoints ? "Done editing points" : "Edit connection points", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Text("PIN NAMES").inspectorLabel()
                ForEach(0..<target.maxConnections, id: \.self) { slot in
                    HStack {
                        Text("Pin \(slot + 1)").font(.caption)
                        TextField("A, B, GND...", text: connectionNameBinding(target, slot: slot))
                            .textFieldStyle(.roundedBorder)
                    }
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
                    showDeleteWarning = true
                } label: { Label("Delete target", systemImage: "trash") }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectionBoxSize: CGSize {
        let actionCount: Int
        if !selectedTargetIDs.isEmpty {
            actionCount = selectedTargetIDs.count == 1 ? 6 : 3
        } else {
            actionCount = selectedSegmentIDs.count == 1 ? 2 : 1
        }
        let buttonWidth: CGFloat = 40
        let countWidth: CGFloat = 16
        let spacing = CGFloat(actionCount) * 8
        let horizontalPadding: CGFloat = 24
        return CGSize(width: countWidth + CGFloat(actionCount) * buttonWidth + spacing + horizontalPadding, height: 60)
    }

    private var selectionBox: some View {
        HStack(spacing: 8) {
            Text("\(selectedTargetIDs.isEmpty ? selectedSegmentIDs.count : selectedTargetIDs.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)
                .accessibilityLabel("\(selectedTargetIDs.isEmpty ? selectedSegmentIDs.count : selectedTargetIDs.count) selected")
            if !selectedTargetIDs.isEmpty {
                Button { connectSelectedTargets() } label: { Image(systemName: "link") }
                    .buttonStyle(EditorButtonStyle())
                    .disabled(selectedTargetIDs.count < 2)
                    .opacity(selectedTargetIDs.count < 2 ? 0.4 : 1)
                    .help("Connect selected items")
                    .accessibilityLabel("Connect selected items")
            }
            if selectedTargetIDs.isEmpty, selectedSegmentIDs.count == 1, let segment = selectedSegment {
                Button { splitWire(segment) } label: { Image(systemName: "scissors") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Split selected wire")
                    .accessibilityLabel("Split selected wire")
            }
            Button(role: .destructive) {
                showDeleteWarning = true
            } label: { Image(systemName: "trash") }
                .buttonStyle(EditorButtonStyle())
                .help("Delete selected items")
                .accessibilityLabel("Delete selected items")
            if selectedTargetIDs.count > 1 {
                Button { toggleSelectedTargetLocks() } label: {
                    Image(systemName: selectedTargetsAreLocked ? "lock.open" : "lock")
                }
                    .buttonStyle(EditorButtonStyle(isActive: selectedTargetsAreLocked))
                    .help(selectedTargetsAreLocked ? "Unlock selected items" : "Lock selected items")
                    .accessibilityLabel(selectedTargetsAreLocked ? "Unlock selected items" : "Lock selected items")
            }
            if selectedTargetIDs.count == 1, let targetID = selectedTargetIDs.first, let target = target(with: targetID) {
                Button { rotateTarget(target, by: -90) } label: { Image(systemName: "rotate.left") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Rotate selected item counter-clockwise")
                    .accessibilityLabel("Rotate selected item counter-clockwise")
                Button { rotateTarget(target, by: 90) } label: { Image(systemName: "rotate.right") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Rotate selected item clockwise")
                    .accessibilityLabel("Rotate selected item clockwise")
                Button { duplicateTarget(target) } label: { Image(systemName: "plus.square.on.square") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Duplicate selected item")
                    .accessibilityLabel("Duplicate selected item")
                Button { toggleTargetLock(target) } label: {
                    Image(systemName: target.locked ? "lock.open" : "lock")
                }
                    .buttonStyle(EditorButtonStyle(isActive: target.locked))
                    .help(target.locked ? "Unlock selected item" : "Lock selected item")
                    .accessibilityLabel(target.locked ? "Unlock selected item" : "Lock selected item")
            }
        }
        .padding(12)
        .frame(width: selectionBoxSize.width, height: selectionBoxSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var selectionBoxAnchor: CGPoint? {
        if let targetID = selectedTargetIDs.last, let target = target(with: targetID) { return target.position }
        guard let segment = selectedSegment,
              let start = target(with: segment.startID),
              let end = target(with: segment.endID) else { return nil }
        return CGPoint(x: (start.position.x + end.position.x) / 2, y: (start.position.y + end.position.y) / 2)
    }

    // Screen-space inverse of canvasDropPoint.
    private func screenPoint(forCanvas point: CGPoint) -> CGPoint {
        let center = CGPoint(x: editorSize.width / 2, y: editorSize.height / 2)
        let scaled = CGPoint(x: (point.x - center.x) * canvasScale, y: (point.y - center.y) * canvasScale)
        let angle = canvasRotation.radians
        let rotated = CGPoint(
            x: scaled.x * CGFloat(cos(angle)) - scaled.y * CGFloat(sin(angle)),
            y: scaled.x * CGFloat(sin(angle)) + scaled.y * CGFloat(cos(angle))
        )
        return CGPoint(x: rotated.x + center.x + canvasOffset.width, y: rotated.y + center.y + canvasOffset.height)
    }

    private func selectionBoxPosition(near canvasPoint: CGPoint) -> CGPoint {
        let anchor = screenPoint(forCanvas: canvasPoint)
        let halfWidth = selectionBoxSize.width / 2, halfHeight = selectionBoxSize.height / 2
        let proposed = CGPoint(x: anchor.x + 70 * canvasScale + halfWidth, y: anchor.y + 60 * canvasScale + halfHeight)
        let minY = 84 + halfHeight + 8
        return CGPoint(
            x: min(max(proposed.x, halfWidth + 8), max(halfWidth + 8, editorSize.width - halfWidth - 8)),
            y: min(max(proposed.y, minY), max(minY, editorSize.height - halfHeight - 8))
        )
    }

    private var hasSelection: Bool { !selectedTargetIDs.isEmpty || !selectedSegmentIDs.isEmpty }
    private var inspectorVisible: Bool {
        (hasSelection && (showInfoPanel || doubleTapInfoIsCurrent) && selectedTargetIDs.count <= 1) || selectedSegmentIDs.count > 1
    }
    private var selectedSegment: SchematicSegment? { guard let selectedSegmentID else { return nil }; return document.segments.first { $0.id == selectedSegmentID } }
    private func segment(with id: UUID) -> SchematicSegment? { document.segments.first { $0.id == id } }
    private func defaultConnectionName(for slot: Int) -> String { String(UnicodeScalar(65 + min(slot, 25))!) }

    private func connectionNameBinding(_ target: SchematicTarget, slot: Int) -> Binding<String> {
        let id = target.id
        return Binding(
            get: {
                let names = document.targets.first { $0.id == id }?.connectionNames ?? target.connectionNames
                if names.indices.contains(slot) { return names[slot] }
                return defaultConnectionName(for: slot)
            },
            set: {
                guard let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
                while document.targets[index].connectionNames.count <= slot { document.targets[index].connectionNames.append(defaultConnectionName(for: document.targets[index].connectionNames.count)) }
                document.targets[index].connectionNames[slot] = $0
            }
        )
    }

    private func wireEditor(_ wire: SchematicSegment, compact: Bool = false, applyToAll: Bool = false) -> some View {
        let binding = segmentBinding(wire, applyToAll: applyToAll)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(applyToAll ? "\(selectedSegmentIDs.count) wires" : String(wire.id.uuidString.prefix(8))).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("WIRE").font(.caption2.weight(.bold)).foregroundStyle(.cyan)
            }
            TextField("Wire name", text: binding.name).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Size", text: binding.wireSize).textFieldStyle(.roundedBorder)
                Picker("Material", selection: binding.material) {
                    ForEach(ConductorMaterial.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
            }
            TextField("Covering", text: binding.covering).textFieldStyle(.roundedBorder)
            TextField("Net name", text: binding.netName).textFieldStyle(.roundedBorder)
            Stepper("Display size: \(wire.displayWidth, specifier: "%.1f") pt", value: binding.displayWidth, in: 1...20, step: 0.5)
        }
        .padding(10)
        .background(.white.opacity(compact ? 0.05 : 0.03), in: RoundedRectangle(cornerRadius: 8))
    }
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
        guard snapToGrid else { return }
        document.targets[index].position = snappedPosition(document.targets[index].position)
    }

    private func snapAllTargets() {
        for index in document.targets.indices {
            document.targets[index].position = snappedPosition(document.targets[index].position)
        }
    }

    private func captureAttachedRoutes(for targetID: UUID) {
        for segment in document.segments where segment.startID == targetID || segment.endID == targetID {
            guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            var points = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
            if points.count == 2 {
                // Straight wires collapse their stubs; restore them so both ends keep leaving their pins outward while dragging.
                let startSlot = segment.startSlot ?? nearestConnectionSlot(for: start, to: points[0])
                let endSlot = segment.endSlot ?? nearestConnectionSlot(for: end, to: points[1])
                points = [points[0], escapePoint(for: start, slot: startSlot, toward: end), escapePoint(for: end, slot: endSlot, toward: start), points[1]]
            }
            targetDragStartRoutes[segment.id] = points
        }
    }

    private func updateAttachedRoutes(for targetID: UUID, translation: CGSize) {
        updateAttachedRoutes(for: Set([targetID]), translation: translation, onlyFullySelected: false)
    }

    private func updateAttachedRoutes(for targetIDs: Set<UUID>, translation: CGSize, onlyFullySelected: Bool = false) {
        for index in document.segments.indices where targetIDs.contains(document.segments[index].startID) || targetIDs.contains(document.segments[index].endID) {
            let segment = document.segments[index]
            guard var points = targetDragStartRoutes[segment.id], points.count > 1 else { continue }
            let startMoved = targetIDs.contains(segment.startID)
            let endMoved = targetIDs.contains(segment.endID)
            if onlyFullySelected && !(startMoved && endMoved) {
                document.segments[index].routePoints.removeAll()
                continue
            }
            if startMoved && endMoved {
                document.segments[index].routePoints = points.map { CGPoint(x: $0.x + translation.width, y: $0.y + translation.height) }
                continue
            }
            let targetID = startMoved ? segment.startID : segment.endID
            if points.count == 2 {
                // Straight stub: move only the attached end; drawing re-orthogonalizes it.
                let movedIndex = segment.startID == targetID ? 0 : 1
                points[movedIndex].x += translation.width
                points[movedIndex].y += translation.height
            } else {
                let pinIndex = segment.startID == targetID ? 0 : points.count - 1
                let stubIndex = segment.startID == targetID ? 1 : points.count - 2
                let pin = points[pinIndex], stub = points[stubIndex]
                let stubIsVertical = abs(pin.x - stub.x) < 0.5
                points[pinIndex].x += translation.width
                points[pinIndex].y += translation.height
                // Stub end follows only across the stub axis so the next leg keeps its line;
                // along the stub axis it stays put unless the pin passes it.
                let minimumStub: CGFloat = 8
                if stubIsVertical {
                    points[stubIndex].x += translation.width
                    let direction: CGFloat = stub.y >= pin.y ? 1 : -1
                    if (points[stubIndex].y - points[pinIndex].y) * direction < minimumStub {
                        points[stubIndex].y = points[pinIndex].y + direction * minimumStub
                    }
                } else {
                    points[stubIndex].y += translation.height
                    let direction: CGFloat = stub.x >= pin.x ? 1 : -1
                    if (points[stubIndex].x - points[pinIndex].x) * direction < minimumStub {
                        points[stubIndex].x = points[pinIndex].x + direction * minimumStub
                    }
                }
                // If the leg after the stub went diagonal, jog at the stub end so that leg keeps its original line.
                let nextIndex = segment.startID == targetID ? stubIndex + 1 : stubIndex - 1
                if points.indices.contains(nextIndex) {
                    let moved = points[stubIndex], next = points[nextIndex]
                    if abs(moved.x - next.x) > 0.5 && abs(moved.y - next.y) > 0.5 {
                        let legWasHorizontal = abs(stub.y - next.y) < 0.5
                        let corner = legWasHorizontal ? CGPoint(x: moved.x, y: next.y) : CGPoint(x: next.x, y: moved.y)
                        points.insert(corner, at: max(stubIndex, nextIndex))
                    }
                }
            }
            document.segments[index].routePoints = points
        }
    }

    private func moveSegmentSection(_ id: UUID, sectionIndex: Int, translation: CGSize) {
        if !selectedSegmentIDs.contains(id) || selectedSegmentID != id || selectedSegmentSectionIndex != sectionIndex {
            selectedTargetIDs.removeAll()
            selectedSegmentIDs = [id]
            selectedSegmentID = id
            selectedSegmentSectionIndex = sectionIndex
        }
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
        let alignment = nearbyParallelAlignment(segmentID: id, sectionStart: points[sectionIndex], sectionEnd: points[sectionIndex + 1], coordinate: movedCoordinate)
        let alignedCoordinate = alignment?.coordinate ?? movedCoordinate
        if isVertical {
            points[sectionIndex].x = alignedCoordinate
            points[sectionIndex + 1].x = alignedCoordinate
        } else {
            points[sectionIndex].y = alignedCoordinate
            points[sectionIndex + 1].y = alignedCoordinate
        }
        let dragRoute = orthogonalizedPoints(points, alignmentTolerance: 0)
        wireAlignmentPreviewSegmentIDs = alignment.map { [id, $0.segmentID] } ?? []
        document.segments[index].routePoints = dragRoute
        selectedTargetIDs.removeAll()
    }

    private func finalizeWireSectionDrag(_ id: UUID) {
        wireAlignmentPreviewSegmentIDs.removeAll()
    }

    private func nearbyParallelAlignment(segmentID: UUID, sectionStart: CGPoint, sectionEnd: CGPoint, coordinate: CGFloat) -> (segmentID: UUID, coordinate: CGFloat)? {
        let tolerance = CGFloat(wireAlignmentTolerance)
        let horizontal = abs(sectionStart.y - sectionEnd.y) < 0.5
        var best: (segmentID: UUID, coordinate: CGFloat, distance: CGFloat)?
        for other in document.segments where other.id != segmentID {
            guard let start = target(with: other.startID), let end = target(with: other.endID) else { continue }
            let points = orthogonalPoints(for: other, from: start, to: end, avoiding: [])
            for index in 0..<(points.count - 1) {
                let otherStart = points[index], otherEnd = points[index + 1]
                guard (abs(otherStart.y - otherEnd.y) < 0.5) == horizontal else { continue }
                let overlap: CGFloat
                let otherCoordinate: CGFloat
                if horizontal {
                    overlap = min(max(sectionStart.x, sectionEnd.x), max(otherStart.x, otherEnd.x)) - max(min(sectionStart.x, sectionEnd.x), min(otherStart.x, otherEnd.x))
                    otherCoordinate = otherStart.y
                } else {
                    overlap = min(max(sectionStart.y, sectionEnd.y), max(otherStart.y, otherEnd.y)) - max(min(sectionStart.y, sectionEnd.y), min(otherStart.y, otherEnd.y))
                    otherCoordinate = otherStart.x
                }
                let distance = abs(coordinate - otherCoordinate)
                    guard overlap >= -tolerance, distance <= tolerance else { continue }
                if best == nil || distance < best!.distance {
                    best = (other.id, otherCoordinate, distance)
                }
            }
        }
        return best.map { ($0.segmentID, $0.coordinate) }
    }

    private func hasNearAlignment(in points: [CGPoint]) -> Bool {
        guard points.count > 2 else { return false }
        for index in 1..<(points.count - 1) {
            let before = points[index - 1]
            let current = points[index]
            let after = points[index + 1]
            let tolerance = CGFloat(wireAlignmentTolerance)
            let vertical = abs(before.x - current.x) <= tolerance && abs(current.x - after.x) <= tolerance
            let horizontal = abs(before.y - current.y) <= tolerance && abs(current.y - after.y) <= tolerance
            if vertical || horizontal { return true }
        }
        return false
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

    private func routeWithCurrentEndpoints(_ routePoints: [CGPoint], segment: SchematicSegment, startTarget: SchematicTarget, endTarget: SchematicTarget) -> [CGPoint] {
        var points = orthogonalizedPoints(routePoints, alignmentTolerance: 0)
        guard points.count > 1 else { return points }
        let startSlot = segment.startSlot ?? startTargetSlot(startTarget, point: points[0])
        let endSlot = segment.endSlot ?? endTargetSlot(endTarget, point: points[points.count - 1])
        let startPin = connectionPoint(for: startTarget, slot: startSlot)
        let endPin = connectionPoint(for: endTarget, slot: endSlot)
        let startEscape = preservedStub(from: points[0], to: points[1], minimumLength: 15, fallback: escapePoint(for: startTarget, slot: startSlot, toward: endTarget))
        let endEscape = preservedStub(from: points[points.count - 1], to: points[points.count - 2], minimumLength: 15, fallback: escapePoint(for: endTarget, slot: endSlot, toward: startTarget))
        if points.count == 2 {
            return orthogonalizedPoints([startPin, startEscape, endEscape, endPin], alignmentTolerance: 0)
        }
        points[0] = startPin
        points[1] = startEscape
        points[points.count - 1] = endPin
        points[points.count - 2] = endEscape
        return orthogonalizedPoints(points, alignmentTolerance: 0)
    }

    private func preservedStub(from pin: CGPoint, to existingPoint: CGPoint, minimumLength: CGFloat, fallback: CGPoint) -> CGPoint {
        let dx = existingPoint.x - pin.x
        let dy = existingPoint.y - pin.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return fallback }
        let actualLength = max(minimumLength, length)
        return CGPoint(x: pin.x + dx / length * actualLength, y: pin.y + dy / length * actualLength)
    }

    private func orthogonalPoints(for segment: SchematicSegment, from startTarget: SchematicTarget, to endTarget: SchematicTarget, avoiding obstacles: [SchematicTarget]) -> [CGPoint] {
        if segment.routePoints.count > 1 {
            return routeWithCurrentEndpoints(segment.routePoints, segment: segment, startTarget: startTarget, endTarget: endTarget)
        }
        let laneOffset: CGFloat = 0
        let start = offsetConnectionPoint(for: startTarget, slot: segment.startSlot, toward: endTarget, by: laneOffset)
        let end = offsetConnectionPoint(for: endTarget, slot: segment.endSlot, toward: startTarget, by: laneOffset)
        let escapeStart = escapePoint(for: startTarget, slot: startTargetSlot(startTarget, point: start), toward: endTarget)
        let escapeEnd = escapePoint(for: endTarget, slot: endTargetSlot(endTarget, point: end), toward: startTarget)
        let rectangles = obstacles.map { obstacleRect(for: $0).insetBy(dx: -12, dy: -12) }
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

    private func trimmed(_ point: CGPoint, toward other: CGPoint, by distance: CGFloat) -> CGPoint {
        let length = hypot(other.x - point.x, other.y - point.y)
        guard length > distance else { return other }
        return CGPoint(x: point.x + (other.x - point.x) / length * distance, y: point.y + (other.y - point.y) / length * distance)
    }

    private func crossings(between first: [CGPoint], and second: [CGPoint]) -> [(point: CGPoint, firstIsHorizontal: Bool)] {
        var results: [(point: CGPoint, firstIsHorizontal: Bool)] = []
        for firstIndex in 0..<(first.count - 1) {
            let firstStart = first[firstIndex], firstEnd = first[firstIndex + 1]
            let firstHorizontal = abs(firstStart.y - firstEnd.y) < 0.5
            guard abs(firstStart.x - firstEnd.x) > 0.5 || abs(firstStart.y - firstEnd.y) > 0.5 else { continue }
            for secondIndex in 0..<(second.count - 1) {
                let secondStart = second[secondIndex], secondEnd = second[secondIndex + 1]
                let secondHorizontal = abs(secondStart.y - secondEnd.y) < 0.5
                guard firstHorizontal != secondHorizontal else { continue }
                let horizontal = firstHorizontal ? (firstStart, firstEnd) : (secondStart, secondEnd)
                let vertical = firstHorizontal ? (secondStart, secondEnd) : (firstStart, firstEnd)
                let point = CGPoint(x: vertical.0.x, y: horizontal.0.y)
                guard point.x > min(horizontal.0.x, horizontal.1.x) + 8,
                      point.x < max(horizontal.0.x, horizontal.1.x) - 8,
                      point.y > min(vertical.0.y, vertical.1.y) + 8,
                      point.y < max(vertical.0.y, vertical.1.y) - 8 else { continue }
                if !results.contains(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < 2 }) {
                    results.append((point, firstHorizontal))
                }
            }
        }
        return results
    }

    private func bridgePath(at point: CGPoint, overHorizontal: Bool) -> Path {
        let radius: CGFloat = 9
        let control: CGFloat = radius * 1.35
        var path = Path()
        if overHorizontal {
            path.move(to: CGPoint(x: point.x - radius, y: point.y))
            path.addCurve(to: CGPoint(x: point.x + radius, y: point.y), control1: CGPoint(x: point.x - radius / 2, y: point.y - control), control2: CGPoint(x: point.x + radius / 2, y: point.y - control))
        } else {
            path.move(to: CGPoint(x: point.x, y: point.y - radius))
            path.addCurve(to: CGPoint(x: point.x, y: point.y + radius), control1: CGPoint(x: point.x + control, y: point.y - radius / 2), control2: CGPoint(x: point.x + control, y: point.y + radius / 2))
        }
        return path
    }

    private func orthogonalizedPoints(_ points: [CGPoint], alignmentTolerance: CGFloat = 4) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result = [points[0]]
        for point in points.dropFirst() {
            guard let previous = result.last else { continue }
            if abs(point.x - previous.x) > 0.5 && abs(point.y - previous.y) > 0.5 {
                result.append(CGPoint(x: point.x, y: previous.y))
            }
            result.append(point)
        }
        return simplifyOrthogonalPoints(result, alignmentTolerance: alignmentTolerance)
    }

    private func simplifyOrthogonalPoints(_ points: [CGPoint], alignmentTolerance: CGFloat = 4) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var simplified = [points[0]]
        for point in points.dropFirst() {
            guard let previous = simplified.last else { continue }
            if abs(point.x - previous.x) < alignmentTolerance && abs(point.y - previous.y) < alignmentTolerance { continue }
            if simplified.count >= 2 {
                let before = simplified[simplified.count - 2]
                let isCollinear = (abs(before.x - previous.x) < alignmentTolerance && abs(previous.x - point.x) < alignmentTolerance) ||
                    (abs(before.y - previous.y) < alignmentTolerance && abs(previous.y - point.y) < alignmentTolerance)
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
            ? quantizedAngle(atan2(other.position.y - target.position.y, other.position.x - target.position.x))
            : atan2(point.y - target.position.y, point.x - target.position.x)
        let distance = max(15, CGFloat(connectionStubLength))
        return CGPoint(x: point.x + distance * CGFloat(cos(angle)), y: point.y + distance * CGFloat(sin(angle)))
    }

    private func quantizedAngle(_ angle: Double) -> Double {
        let increment = Double.pi / 12
        return (angle / increment).rounded() * increment
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
        let size = target.kind == .junction ? CGSize(width: 18, height: 18) : target.isCompact ? CGSize(width: 40, height: 40) : CGSize(width: 88, height: 76)
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

    private func splitCandidate(at position: CGPoint, excluding targetID: UUID?) -> (segment: SchematicSegment, index: Int, route: [CGPoint], point: CGPoint)? {
        for (index, segment) in document.segments.enumerated() {
            guard segment.startID != targetID, segment.endID != targetID, let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let route = segment.routePoints.count > 1
                ? segment.routePoints
                : orthogonalPoints(for: segment, from: start, to: end, avoiding: [])
            let candidate = nearestPoint(on: route, to: position)
            if candidate.distance <= 52 { return (segment, index, route, candidate.point) }
        }
        return nil
    }

    private func splitSegmentIfNeeded(for targetID: UUID) {
        guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }) else { return }
        guard connectionCount(for: targetID) == 0 else { return }
        let freeSlots = document.targets[targetIndex].maxConnections - occupiedSlots(for: targetID).count
        guard freeSlots >= 2 else { return }
        guard let hit = splitCandidate(at: document.targets[targetIndex].position, excluding: targetID) else { return }
        let segment = hit.segment
        let isJunction = document.targets[targetIndex].kind == .junction
        let junctionPosition = hit.point
        // Sit the dropped item on the wire so both halves terminate at its pins.
        document.targets[targetIndex].position = junctionPosition
        let splitRoutes = splitRoutePoints(hit.route, at: junctionPosition)
        document.segments.remove(at: hit.index)
        let startSlot = segment.startSlot ?? 0
        let endSlot = segment.endSlot ?? 0
        let firstSlot = closestAvailableSlot(for: targetID, to: segment.startID) ?? 0
        if isJunction {
            let secondSlot = firstSlot + 1
            document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, startSlot: startSlot, endSlot: firstSlot, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.first), at: hit.index)
            document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, startSlot: secondSlot, endSlot: endSlot, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.second), at: hit.index + 1)
            return
        }
        // Rotate so the first pin faces back along the wire: sides for a horizontal wire, top/bottom for vertical.
        if let section = nearestSection(of: hit.route, to: hit.point) {
            let wireIsHorizontal = abs(section.start.y - section.end.y) < 0.5
            let desired: Double = wireIsHorizontal ? (section.start.x < section.end.x ? 180 : 0) : (section.start.y < section.end.y ? 270 : 90)
            let current = connectionAngle(for: document.targets[targetIndex], slot: firstSlot).truncatingRemainder(dividingBy: 360)
            let delta = (desired - current).truncatingRemainder(dividingBy: 360)
            if abs(delta) > 0.5 { rotateTarget(document.targets[targetIndex], by: delta) }
        }
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, startSlot: startSlot, endSlot: firstSlot, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: routeIntoPin(Array(splitRoutes.first.dropLast()), target: document.targets[targetIndex], slot: firstSlot, toward: segment.startID, fallback: junctionPosition)), at: hit.index)
        let secondSlot = closestAvailableSlot(for: targetID, to: segment.endID) ?? (firstSlot == 0 ? 1 : 0)
        document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, startSlot: secondSlot, endSlot: endSlot, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: routeIntoPin(Array(splitRoutes.second.dropFirst()).reversed(), target: document.targets[targetIndex], slot: secondSlot, toward: segment.endID, fallback: junctionPosition).reversed()), at: hit.index + 1)
    }

    private func nearestSection(of points: [CGPoint], to point: CGPoint) -> (start: CGPoint, end: CGPoint)? {
        guard points.count > 1 else { return nil }
        var best: (start: CGPoint, end: CGPoint)?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            let distance = nearestPoint(on: [points[index], points[index + 1]], to: point).distance
            if distance < bestDistance { bestDistance = distance; best = (points[index], points[index + 1]) }
        }
        return best
    }

    // Ends `points` at the pin by way of its escape stub so the wire leaves the pin outward.
    private func routeIntoPin(_ points: [CGPoint], target: SchematicTarget, slot: Int, toward otherID: UUID, fallback: CGPoint) -> [CGPoint] {
        let pin = connectionPoint(for: target, slot: slot)
        guard let other = self.target(with: otherID) else { return orthogonalizedPoints(points + [pin]) }
        let escape = escapePoint(for: target, slot: slot, toward: other)
        let previous = points.last ?? fallback
        let pinIsVertical = abs(pin.y - target.position.y) >= abs(pin.x - target.position.x)
        let corner = pinIsVertical ? CGPoint(x: previous.x, y: escape.y) : CGPoint(x: escape.x, y: previous.y)
        return simplifyOrthogonalPoints((points.isEmpty ? [fallback] : points) + [corner, escape, pin])
    }

    private func splitWire(_ segment: SchematicSegment) {
        guard let start = target(with: segment.startID), let end = target(with: segment.endID),
              let index = document.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let route = orthogonalPoints(for: segment, from: start, to: end, avoiding: document.targets.filter { $0.id != start.id && $0.id != end.id })
        let midpoint = nearestPoint(on: route, to: CGPoint(x: (start.position.x + end.position.x) / 2, y: (start.position.y + end.position.y) / 2)).point
        let junctionPosition = snapToGrid ? snappedPosition(midpoint) : midpoint
        let splitRoutes = splitRoutePoints(route, at: junctionPosition)
        let junction = SchematicTarget(kind: .junction, name: "Junction", position: junctionPosition, maxConnections: 8, colorHex: TargetKind.junction.defaultColorHex)
        document.targets.append(junction)
        document.segments.remove(at: index)
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: junction.id, startSlot: segment.startSlot, endSlot: 0, name: segment.name + " A", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.first), at: index)
        document.segments.insert(SchematicSegment(startID: junction.id, endID: segment.endID, startSlot: 1, endSlot: segment.endSlot, name: segment.name + " B", colorHex: segment.colorHex, wireSize: segment.wireSize, material: segment.material, covering: segment.covering, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.second), at: index + 1)
        selectedSegmentIDs.remove(segment.id)
        selectedSegmentID = nil
    }

    private func splitRoutePoints(_ points: [CGPoint], at point: CGPoint) -> (first: [CGPoint], second: [CGPoint]) {
        guard points.count > 1 else { return (points, points) }
        var splitIndex = 0
        var shortestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            let candidate = nearestPoint(on: [points[index], points[index + 1]], to: point)
            if candidate.distance < shortestDistance {
                shortestDistance = candidate.distance
                splitIndex = index
            }
        }
        let first = orthogonalizedPoints(Array(points.prefix(splitIndex + 1)) + [point])
        let second = orthogonalizedPoints([point] + Array(points.suffix(from: splitIndex + 1)))
        return (first, second)
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

    private func segmentBinding(_ segment: SchematicSegment, applyToAll: Bool = false) -> (name: Binding<String>, color: Binding<Color>, wireSize: Binding<String>, material: Binding<ConductorMaterial>, displayWidth: Binding<Double>, description: Binding<String>, covering: Binding<String>, netName: Binding<String>) {
        let id = segment.id
        func current() -> SchematicSegment { document.segments.first { $0.id == id } ?? segment }
        func update(_ change: (inout SchematicSegment) -> Void) {
            let ids: Set<UUID> = applyToAll ? selectedSegmentIDs.union([id]) : [id]
            for index in document.segments.indices where ids.contains(document.segments[index].id) {
                change(&document.segments[index])
            }
        }
        return (
            Binding(get: { current().name }, set: { value in update { $0.name = value } }),
            Binding(get: { Color(hex: current().colorHex) }, set: { value in update { $0.colorHex = value.hexString } }),
            Binding(get: { current().wireSize }, set: { value in update { $0.wireSize = value } }),
            Binding(get: { ConductorMaterial(rawValue: current().material) ?? .copper }, set: { value in update { $0.material = value.rawValue } }),
            Binding(get: { current().displayWidth }, set: { value in update { $0.displayWidth = value } }),
            Binding(get: { current().description }, set: { value in update { $0.description = value } }),
            Binding(get: { current().covering }, set: { value in update { $0.covering = value } }),
            Binding(get: { current().netName }, set: { value in update { $0.netName = value } })
        )
    }

    private func targetBinding(_ target: SchematicTarget) -> (name: Binding<String>, symbol: Binding<String>, maxConnections: Binding<Int>, connectionAngle: Binding<Double>, color: Binding<Color>, scale: Binding<Double>, isCompact: Binding<Bool>) {
        let id = target.id
        // Resolve by id on every access; a captured index goes stale when targets are deleted.
        func current() -> SchematicTarget { document.targets.first { $0.id == id } ?? target }
        func update(_ change: (inout SchematicTarget) -> Void) {
            guard let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
            change(&document.targets[index])
        }
        return (
            Binding(get: { current().name }, set: { value in update { $0.name = value } }),
            Binding(get: { current().symbol }, set: { value in update { $0.symbol = value } }),
            Binding(get: { current().maxConnections }, set: { value in update { $0.maxConnections = value } }),
            Binding(get: { current().connectionAngle }, set: { value in update { $0.connectionAngle = value } }),
            Binding(get: { Color(hex: current().colorHex) }, set: { value in update { $0.colorHex = value.hexString } }),
            Binding(get: { current().scale }, set: { value in update { $0.scale = value } }),
            Binding(get: { current().isCompact }, set: { value in update { $0.isCompact = value } })
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

    private func rotateTarget(_ target: SchematicTarget, by degrees: Double) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        if document.targets[index].connectionAngles.isEmpty {
            document.targets[index].connectionAngle = (document.targets[index].connectionAngle + degrees).truncatingRemainder(dividingBy: 360)
        } else {
            document.targets[index].connectionAngles = document.targets[index].connectionAngles.map {
                ($0 + degrees).truncatingRemainder(dividingBy: 360)
            }
        }
        for segmentIndex in document.segments.indices where document.segments[segmentIndex].startID == target.id || document.segments[segmentIndex].endID == target.id {
            document.segments[segmentIndex].routePoints.removeAll()
        }
    }

    private func saveTargetName(_ target: SchematicTarget) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        let trimmedName = targetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        document.targets[index].name = trimmedName.isEmpty ? target.kind.title : trimmedName
        targetNameDraft = document.targets[index].name
    }

    private func cancelTargetName(_ target: SchematicTarget) {
        targetNameDraft = target.name
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

private struct CloudDrawingChoice: Identifiable {
    let id: UUID
    let name: String
    let data: Data
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
    var connectionNames: [String]
    var scale: Double
    var isCompact: Bool
    var locked: Bool

    init(id: UUID = UUID(), kind: TargetKind, name: String, position: CGPoint, maxConnections: Int, colorHex: String, symbol: String? = nil, imageData: Data? = nil, connectionAngle: Double = 0, connectionAngles: [Double] = [], connectionNames: [String] = [], scale: Double = 1, isCompact: Bool = false, locked: Bool = false) {
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
        self.connectionNames = connectionNames
        self.scale = scale
        self.isCompact = isCompact
        self.locked = locked
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
        connectionNames = try container.decodeIfPresent([String].self, forKey: .connectionNames) ?? []
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        isCompact = try container.decodeIfPresent(Bool.self, forKey: .isCompact) ?? false
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
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
    var covering: String
    var netName: String
    var displayWidth: Double
    var description: String
    var bendOffset: CGFloat
    var routePoints: [CGPoint]
    var labelPosition: Double
    var color: Color { Color(hex: colorHex) }

    init(startID: UUID, endID: UUID, startSlot: Int? = nil, endSlot: Int? = nil, name: String, colorHex: String, wireSize: String = "14 AWG", material: String = "Copper", covering: String = "None", netName: String = "N001", displayWidth: Double = 3, description: String = "", bendOffset: CGFloat = 0, routePoints: [CGPoint] = [], labelPosition: Double = 0.5) {
        self.startID = startID; self.endID = endID; self.startSlot = startSlot; self.endSlot = endSlot; self.name = name; self.colorHex = colorHex
        self.wireSize = wireSize; self.material = material; self.covering = covering; self.netName = netName; self.displayWidth = displayWidth; self.description = description; self.bendOffset = bendOffset; self.routePoints = routePoints; self.labelPosition = labelPosition
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
        covering = try container.decodeIfPresent(String.self, forKey: .covering) ?? "None"
        netName = try container.decodeIfPresent(String.self, forKey: .netName) ?? "N001"
        displayWidth = try container.decodeIfPresent(Double.self, forKey: .displayWidth) ?? 3
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        bendOffset = try container.decodeIfPresent(CGFloat.self, forKey: .bendOffset) ?? 0
        routePoints = try container.decodeIfPresent([CGPoint].self, forKey: .routePoints) ?? []
        labelPosition = try container.decodeIfPresent(Double.self, forKey: .labelPosition) ?? 0.5
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
    static let palette: [TargetKind] = [.source, .utilitySource, .transformer, .breaker, .fuse, .disconnect, .switchTarget, .panel, .bus, .meter, .generator, .motor, .receptacle, .ground, .capacitor, .load, .junction]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: return "Source"; case .utilitySource: return "Utility source"; case .transformer: return "Transformer"; case .breaker: return "Breaker"; case .fuse: return "Fuse"; case .disconnect: return "Disconnect"; case .switchTarget: return "Switch"; case .panel: return "Panel"; case .bus: return "Bus"; case .meter: return "Meter"; case .generator: return "Generator"; case .motor: return "Motor"; case .receptacle: return "Receptacle"; case .ground: return "Ground"; case .capacitor: return "Capacitor"; case .load: return "Load"; case .junction: return "Junction"
        }
    }
    var symbol: String {
        switch self {
        case .source: return "bolt.fill"; case .utilitySource: return "powerplug.fill"; case .transformer: return "arrow.left.arrow.right"; case .breaker: return "bolt.shield.fill"; case .fuse: return "battery.100percent"; case .disconnect: return "poweroff"; case .switchTarget: return "switch.2"; case .panel: return "rectangle.split.3x1"; case .bus: return "line.3.horizontal"; case .meter: return "gauge.with.dots.needle.bottom.50percent"; case .generator: return "engine.combustion.fill"; case .motor: return "fanblades.fill"; case .receptacle: return "rectangle.grid.2x2"; case .ground: return "arrow.down.to.line"; case .capacitor: return "minus.plus.batteryblock"; case .load: return "lightbulb.fill"; case .junction: return "circle.fill"
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
    let connectionNames: [String]
    let showConnectionNames: Bool
    let onSelectConnectionPoint: (Int) -> Void
    let editingConnectionPoints: Bool
    let onMoveConnectionPoint: (Int, CGSize) -> Void
    let onEndConnectionPointMove: (Int) -> Void

    var body: some View {
        Group {
            if target.kind == .junction {
                ZStack {
                    Circle().fill(connectedColor).frame(width: 18, height: 18).overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 2) }
                }
            } else if target.isCompact {
                ZStack {
                    Circle().fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                    Circle().stroke(borderStyle, lineWidth: isSelected || isConnectionStart ? 3 : 2)
                    if let imageData = target.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 24, height: 24).clipShape(Circle())
                    } else {
                        Image(systemName: target.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Color(hex: target.colorHex))
                    }
                }
                .frame(width: 40, height: 40)
            } else {
                VStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.14, blue: 0.16))
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
                    Text(target.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 80, height: 24)
                        .offset(y: -4)
                }
                .frame(width: 88, height: 76)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(borderStyle, lineWidth: isSelected || isConnectionStart ? 3 : 2) }
            }
        }
        .overlay {
            if target.locked {
                if target.kind == .junction {
                    Circle().stroke(lockedBorderStyle, lineWidth: 1.5).frame(width: 28, height: 28)
                } else if target.isCompact {
                    Circle().stroke(lockedBorderStyle, lineWidth: 1.5).frame(width: 52, height: 52)
                } else {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(lockedBorderStyle, lineWidth: 1.5)
                        .frame(width: 88, height: 76)
                }
            }
        }
        .overlay {
            if isSelected || isConnectionStart {
                if target.kind == .junction {
                    Circle().stroke(.cyan, lineWidth: 3).frame(width: 30, height: 30).shadow(color: .cyan.opacity(0.8), radius: 8)
                } else if target.isCompact {
                    Circle().stroke(.cyan, lineWidth: 3).frame(width: 44, height: 44).shadow(color: .cyan.opacity(0.8), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 12).stroke(.cyan, lineWidth: 3).frame(width: 88, height: 76).shadow(color: .cyan.opacity(0.8), radius: 8)
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
        // Pins sit outside the body frame; widen the hit shape so taps on them don't fall through to wires.
        .contentShape(targetHitShape)
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
    }

    @ViewBuilder
    private func connectionPoint(slot: Int) -> some View {
        let point = Circle()
            .fill(selectedSlots.contains(slot) ? Color.cyan : occupiedSlots.contains(slot) ? connectedColor : Color.white.opacity(0.35))
            .frame(width: selectedSlots.contains(slot) ? 14 : 9, height: selectedSlots.contains(slot) ? 14 : 9)
            .overlay { Circle().stroke(selectedSlots.contains(slot) ? Color.white : .black.opacity(0.65), lineWidth: selectedSlots.contains(slot) ? 2 : 1) }
            .overlay(alignment: .bottomTrailing) {
                if showConnectionNames {
                let labelAngle = (target.connectionAngles.indices.contains(slot) ? target.connectionAngles[slot] : (360 * Double(slot) / Double(max(target.maxConnections, 1))) + target.connectionAngle - 90) * Double.pi / 180
                Text(connectionNames.indices.contains(slot) ? connectionNames[slot] : String(UnicodeScalar(65 + min(slot, 25))!))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .offset(x: 12 * CGFloat(cos(labelAngle)), y: 12 * CGFloat(sin(labelAngle)))
                }
            }

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

    private var targetHitShape: AnyShape {
        AnyShape(TargetBodyHitShape(kind: target.kind, isCompact: target.isCompact))
    }

    private var lockedBorderStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [Color.red, Color(red: 0.55, green: 0.02, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct TargetBodyHitShape: Shape {
    let kind: TargetKind
    let isCompact: Bool

    func path(in rect: CGRect) -> Path {
        if kind == .junction {
            return Circle().path(in: CGRect(x: rect.midX - 9, y: rect.midY - 9, width: 18, height: 18))
        }
        if isCompact {
            return Circle().path(in: CGRect(x: rect.midX - 20, y: rect.midY - 20, width: 40, height: 40))
        }
        return RoundedRectangle(cornerRadius: 10).path(in: CGRect(x: rect.midX - 44, y: rect.midY - 38, width: 88, height: 76))
    }
}

private struct SegmentHitArea: View {
    let path: Path
    var hitPath: Path? = nil
    let isSelected: Bool
    let isSectionSelected: Bool
    let onDrag: (CGSize) -> Void
    let onEndDrag: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    var body: some View {
        path.stroke(isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.001), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
            .contentShape((hitPath ?? path).strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)))
            .onTapGesture(perform: onTap)
            .onTapGesture(count: 2, perform: onDoubleTap)
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
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isActive ? .cyan : .white.opacity(0.82))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(isActive ? .cyan.opacity(0.14) : .white.opacity(configuration.isPressed ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(isActive ? .cyan.opacity(0.5) : .white.opacity(0.08), lineWidth: 1) }
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
