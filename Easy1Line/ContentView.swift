import SwiftUI
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import MultipeerConnectivity

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

private struct NetEndpoint: Hashable {
    let targetID: UUID
    let slot: Int
}

struct ContentView: View {
    @State private var document = SchematicDocument.loadLast()
    @State private var savedDocuments = SchematicDocument.loadAll()
    @State private var undoStack: [SchematicDocument] = []
    @State private var redoStack: [SchematicDocument] = []
    @StateObject private var multipeerSession = MultipeerSession()
    @State private var showMultiuserSheet = false
    @AppStorage("currentDisplayName") private var currentDisplayName = ""
    @State private var profileNames: [String] = []
    @State private var profileNameDraft = ""
    @State private var showProfilePicker = false
    @State private var editingDocumentName = false
    @State private var isApplyingRemoteDocument = false
    @State private var remoteSyncEnabled = false
    @State private var remoteSyncTask: Task<Void, Never>?
    @State private var remoteSyncDirty = false
    @State private var remoteSyncLastKnownUpdatedAt: String?
    @State private var canvasOffset = CGSize.zero
    @State private var canvasScale: CGFloat = 1
    @State private var canvasRotation = Angle.zero
    @State private var gestureStartScale: CGFloat?
    @State private var gestureStartRotation: Angle?
    @State private var isPinchingOrRotating = false
    @State private var quickAddCascadeIndex = 0
    @State private var cachedWirePoints: [UUID: [CGPoint]] = [:]
    @State private var cachedBridgeStrokes: [(path: Path, color: Color, width: CGFloat)] = []
    @State private var cachedConnectedColor: [UUID: Color] = [:]
    @State private var cachedConnectedColors: [UUID: [Color]] = [:]
    @State private var cachedOccupiedSlots: [UUID: Set<Int>] = [:]
        @State private var cachedConnectionCounts: [UUID: [Int: Int]] = [:]
    @State private var panStart = CGSize.zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var targetDragStartCanvasOffset: CGSize?
    @State private var activeTargetDragIDs: [UUID] = []
    @State private var targetDragStartRoutes: [UUID: [CGPoint]] = [:]
    @State private var draggingTargetID: UUID?
    @State private var selectedSegmentSectionIndex: Int?
    @State private var segmentDragStartPoints: [UUID: [CGPoint]] = [:]
    @State private var selectedTargetIDs: [UUID] = []
    @State private var connectionMode = false
    @State private var connectionModeTargetIDs: [UUID] = []
    @AppStorage("targetsPanelExpanded") private var targetsPanelExpanded = true
    @State private var selectedSegmentID: UUID?
    @State private var selectedSegmentIDs: Set<UUID> = []
    @State private var selectedConnectionSlots: [UUID: Int] = [:]
    @State private var wirePinMoveTargetID: UUID?
    @State private var wireConnectionMoveMode = false
    @AppStorage("showConnectionNames") private var showConnectionNames = true
    @AppStorage("showWireLegend") private var showWireLegend = false
    @AppStorage("showWireLengths") private var showWireLengths = true
    @AppStorage("showWireNames") private var showWireNames = true
    @AppStorage("showWireSizes") private var showWireSizes = false
    @AppStorage("showWireMaterials") private var showWireMaterials = false
    @AppStorage("showWireCoverings") private var showWireCoverings = false
    @AppStorage("showWireNetNames") private var showWireNetNames = false
    @AppStorage("canvasBackgroundColorHex") private var canvasBackgroundColorHex: String = "0F1215"
    private let canvasFieldSize: CGFloat = 5000
    private let wireRoutingClearancePixels: CGFloat = 0
    @AppStorage("baseItemSize") private var baseItemSize: Double = 1.0
    @AppStorage("selectionHighlightColorHex") private var selectionHighlightColorHex: String = "31D7E8"
    @AppStorage("wireAlignmentTolerance") private var wireAlignmentTolerance: Double = 5
    @AppStorage("connectionStubLength") private var connectionStubLength: Double = 15
    @AppStorage("wireBridgesEnabled") private var wireBridgesEnabled = true
    @AppStorage("snapToGrid") private var snapToGrid = true
    @AppStorage("showEditBoxOnSelection") private var showEditBoxOnSelection = true
    @State private var forceEditBoxTargetID: UUID?
    @State private var forceEditBoxSegmentID: UUID?
    @State private var dismissedEditBoxTargetID: UUID?
    @State private var dismissedEditBoxSegmentID: UUID?
    private let linePadding: CGFloat = 16
    @State private var showLibrary = false
    @State private var showCloudLibrary = false
    @State private var cloudDrawings: [CloudDrawingChoice] = []
    @State private var showLineLibrary = false
    @State private var showColorLibrary = false
    @State private var showVisualizationsPanel = false
    @State private var showLabelsPanel = false
    @State private var showLineDefinitionEditor = false
    @State private var editingLineDefinitionID: UUID?
    @State private var lineDefinitionNameDraft = ""
    @State private var lineDefinitionSizeDraft = ""
    @State private var lineDefinitionTypeDraft = ""
    @State private var lineDefinitionMiscDraft = ""
    @State private var lineDefinitionDescriptionDraft = ""
    @State private var lineDefinitionColorHexDraft = "31D7E8"
    @State private var colorLegendMeaningDraft = ""
    @State private var colorLegendHexDraft = "31D7E8"
    @State private var editingColorLegendID: UUID?
    @State private var showColorLegendEditor = false
    @State private var lineDefinitionUsesCustomSize = false
    @State private var lineDefinitionUsesCustomType = false
    @State private var lineLibrarySearch = ""
    @State private var showTargetLibrary = false
    @State private var showNetlist = false
    @State private var showBackgroundImagePanel = false
    @State private var showBackgroundColorPicker = false
    @State private var showSelectionColorPicker = false
    @State private var selectedLineDefinitionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var connectionDragStartAngles: [String: Double] = [:]
    @State private var editingConnectionPoints = false
    @State private var cloudStatus = ""
    @State private var errorLog = LocalErrorLog.load()
    @State private var saveNameDraft = ""
    @State private var pendingSaveToCloud = false
    @State private var showSaveNamePrompt = false
    @State private var showVersionPrompt = false
    @State private var showVersionHistory = false
    @State private var versionDescriptionDraft = ""
    @State private var showFileExporter = false
    @State private var pdfShareItem: PDFShareItem?
    @State private var showFileImporter = false
    @State private var editorSize = CGSize.zero
    @State private var dockDragKind: TargetKind?
    @State private var dockDragLocation = CGPoint.zero
    @AppStorage("targetsPanelListHeight") private var targetsPanelListHeight: Double = 460
    @AppStorage("targetsPanelWidth") private var targetsPanelWidth: Double = 250
    @AppStorage("itemsPanelOffsetX") private var itemsPanelOffsetX: Double = 0
    @AppStorage("itemsPanelOffsetY") private var itemsPanelOffsetY: Double = 0
    @AppStorage("canvasLocked") private var canvasLocked = false
    @AppStorage("rotationLocked") private var rotationLocked = false
    @State private var targetsPanelResizeStart: Double?
    @State private var targetsPanelWidthResizeStart: Double?
    @State private var itemsPanelDragStartOffset: CGSize?
    @State private var itemsPanelHeight: CGFloat = 44
    @State private var splitCandidateSegmentID: UUID?
    @State private var wireAlignmentPreviewSegmentIDs: Set<UUID> = []
    @State private var targetIdentifierDraft = ""
    @State private var targetNameEditingID: UUID?
    @AppStorage("selectionToolbarOffsetX") private var selectionToolbarOffsetX: Double = 0
    @AppStorage("selectionToolbarOffsetY") private var selectionToolbarOffsetY: Double = 0
    @AppStorage("targetToolbarOffsetX") private var targetToolbarOffsetX: Double = 0
    @AppStorage("targetToolbarOffsetY") private var targetToolbarOffsetY: Double = 0
    @AppStorage("zoomToolbarOffsetX") private var zoomToolbarOffsetX: Double = 0
    @AppStorage("zoomToolbarOffsetY") private var zoomToolbarOffsetY: Double = 0
    @State private var toolbarDragStartOffset: CGSize?
    @State private var targetToolbarHeight: CGFloat = 0
    @State private var zoomToolbarWidth: CGFloat = 0
    @State private var showDeleteWarning = false
    @State private var deleteWarningSourceFrame: CGRect = .zero
    @State private var wirePlacementMode: WirePlacementMode?
    @State private var wireLabelDragStartPoints: [UUID: CGPoint] = [:]
    @State private var wireLabelRouteAnchorPoints: [UUID: CGPoint] = [:]
    @State private var showNewDrawingWarning = false
    @State private var pendingNewDrawingAfterSave = false
    @State private var editingWireID: UUID?
    @State private var editingWireDraft: SchematicSegment?
    @State private var backgroundImage: UIImage?
    @State private var backgroundImageSize = CGSize(width: 500, height: 500)
    @State private var backgroundImagePosition = CGPoint(x: 2000, y: 2000)
    @State private var backgroundImageOpacity: Double = 1.0
    @State private var backgroundImageLocked = false
    @State private var backgroundImageConstrainProportions = false
    @State private var backgroundImagePhotoItem: PhotosPickerItem?
    @State private var wireLibraryEntries: [SupabaseWireLibraryRecord] = []
    @State private var showWireLibraryPanel = false
    @State private var newWireLibrarySize = ""
    @State private var newWireLibraryType = ""
    @State private var newWireLibraryMisc = ""
    @State private var newWireLibraryDescription = ""
    @State private var newWireLibrarySizeID: Int?
    @State private var newWireLibraryTypeID: Int?
    @State private var newWireLibraryMiscID: Int?
    @State private var newWireLibraryDisplaySize: Double = 2.0
    @State private var newWireLibraryColorHex: String = "31D7E8"
    @State private var selectedWireLibraryID: Int?
    @State private var wireLibraryAction: String? // "change", "changeAll", or nil for discard
    @State private var wireSizeOptions: [SupabaseWireSizeRecord] = []
    @State private var wireTypeOptions: [SupabaseWireTypeRecord] = []
    @State private var wireMiscOptions: [SupabaseWireMiscRecord] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: canvasBackgroundColorHex)
                .ignoresSafeArea()

            GeometryReader { geometry in
                schematicCanvas(in: geometry.size)
            }

            palette
                .padding(.leading, 20)
                .padding(.top, 90)
                .offset(x: itemsPanelOffsetX, y: itemsPanelOffsetY)

            if let dockDragKind {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                        .frame(width: 72, height: 62)
                    SchematicSymbolView(kind: dockDragKind, color: Color(hex: dockDragKind.defaultColorHex))
                        .frame(width: 34, height: 34)
                }
                .shadow(color: .black.opacity(0.35), radius: 12)
                .allowsHitTesting(false)
                .position(dockDragLocation)
                .zIndex(1200)
            }

            header
                .zIndex(1000)

            if showProfilePicker {
                profilePickerPanel
                    .zIndex(1400)
            }

            if wireConnectionMoveMode {
                Text(wirePinMoveTargetID == nil ? "Select endpoint to move" : "Select new connection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 84)
                    .allowsHitTesting(false)
                    .zIndex(1100)
            }

                if selectedTargetIDs.count == 1, !connectionMode, let target = target(with: selectedTargetIDs.first!),
                       (showEditBoxOnSelection && dismissedEditBoxTargetID != target.id) || forceEditBoxTargetID == target.id {
                targetBottomPanel(target)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    targetToolbarHeight = proxy.size.height
                                    recoverToolbarOffsetsIfNeeded()
                                }
                                .onChange(of: proxy.size.height) { _, newHeight in
                                    targetToolbarHeight = newHeight
                                    recoverToolbarOffsetsIfNeeded()
                                }
                        }
                    }
                    .padding(.bottom, 6)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(x: targetToolbarOffsetX, y: targetToolbarOffsetY)
                    .simultaneousGesture(toolbarDragGesture(isTarget: true))
            }

            if showLibrary {
                libraryPanel
                    .padding(.top, 84)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

                    if showVersionHistory {
                    versionHistoryPanel
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

            if showColorLibrary {
                colorLibraryPanel
                    .padding(.top, 84)
                    .padding(.leading, 205)
            }

            if showTargetLibrary {
                targetLibraryPanel
                    .padding(.top, 84)
                    .padding(.leading, 205)
            }

            if showWireLegend {
                wireLegendPanel
                    .padding(.top, 84)
                    .padding(.leading, 205)
            }

            if showNetlist {
                netlistPanel
                    .padding(.top, 84)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            if showBackgroundImagePanel {
                backgroundImagePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
            }

                if selectedSegmentIDs.count >= 1, !connectionMode, let segment = selectedSegment,
                       (showEditBoxOnSelection && dismissedEditBoxSegmentID != segment.id) || forceEditBoxSegmentID == segment.id {
                wireBottomPanel(segment)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if connectionMode {
                Rectangle()
                    .stroke(.yellow, lineWidth: 4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(900)
            }

            Text("v\(appVersion)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.trailing, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onChange(of: document) { _, newValue in
            SchematicDocument.saveLast(document)
            restoreBackgroundImage()
            recomputeWireGeometry()
            sanitizeTargetDefinitionSymbols()
            if !isApplyingRemoteDocument {
                broadcastDocumentIfNeeded(newValue)
                remoteSyncDirty = true
            }
        }
        .onChange(of: wireBridgesEnabled) { _, _ in
            recomputeWireGeometry()
        }
        .onChange(of: editorSize.height) { _, _ in
            recoverToolbarOffsetsIfNeeded()
        }
        .onAppear {
            multipeerSession.onReceiveData = { data in
                applyRemoteDocument(data)
            }
            multipeerSession.onAcceptedPeerConnected = { peerID in
                if let encoded = try? JSONEncoder().encode(document) {
                    multipeerSession.send(encoded, to: peerID)
                }
            }
        }
        .sheet(isPresented: $showMultiuserSheet) {
            MultiuserSessionView(session: multipeerSession)
        }
        .alert("Invitation from \(multipeerSession.pendingInvite?.peerID.displayName ?? "")", isPresented: Binding(
            get: { multipeerSession.pendingInvite != nil },
            set: { if !$0 { multipeerSession.respondToPendingInvite(accept: false) } }
        )) {
            Button("Accept") { multipeerSession.respondToPendingInvite(accept: true) }
            Button("Decline", role: .cancel) { multipeerSession.respondToPendingInvite(accept: false) }
        } message: {
            Text("Join their Easy1Line session? Your current drawing will be replaced.")
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item, let targetID = selectedTargetIDs.first else { return }
            Task { await loadTargetImage(item, targetID: targetID) }
        }
        .onChange(of: backgroundImagePhotoItem) { _, item in
            guard let item else { return }
            Task { await loadBackgroundImage(item) }
        }
        .onAppear {
            restoreBackgroundImage()
            recomputeWireGeometry()
            sanitizeTargetDefinitionSymbols()
            if currentDisplayName.isEmpty { showProfilePicker = true }
        }
        .task(id: cloudStatus) {
            guard !cloudStatus.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            cloudStatus = ""
        }
        .alert("Name this schematic", isPresented: $showSaveNamePrompt) {
            TextField("Schematic name", text: $saveNameDraft)
            Button("Save") { commitNamedSave() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save a version", isPresented: $showVersionPrompt) {
            TextField("What changed?", text: $versionDescriptionDraft)
            Button("Save version") { saveVersion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add a short description so you can recognize this snapshot later.")
        }
        .popover(isPresented: $showDeleteWarning, attachmentAnchor: .point(.center), arrowEdge: .bottom) {
            VStack(spacing: 12) {
                Text(deleteWarningTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    Button(role: .cancel) {
                        showDeleteWarning = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(role: .destructive) {
                        deleteSelectedContent()
                        showDeleteWarning = false
                    } label: {
                        Text("Delete")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(16)
            .frame(width: 220)
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
            if case .failure(let error) = result { 
                let exportError = error.localizedDescription
                cloudStatus = "Export failed: " + exportError
            }
        }
        .sheet(item: $pdfShareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.line]) { result in
            do {
                let url = try result.get()
                document = try SchematicFileDocument.load(from: url).document
                autoZoomAfterLoad()
                cloudStatus = "Imported schematic"
            } catch {
                let errorMsg = error.localizedDescription
                let failMsg = "Import failed: " + errorMsg
                cloudStatus = failMsg
            }
        }
        .sheet(isPresented: $showLineDefinitionEditor) {
            lineDefinitionEditor
        }
        .onChange(of: selectedTargetIDs) { _, ids in
            if ids.count != 1 {
                forceEditBoxTargetID = nil
            }
            guard let id = ids.last, let target = target(with: id) else {
                targetNameEditingID = nil
                targetIdentifierDraft = ""
                return
            }
            targetNameEditingID = id
            targetIdentifierDraft = target.identifier
        }
        .onChange(of: showEditBoxOnSelection) { _, isEnabled in
            if !isEnabled {
                forceEditBoxTargetID = nil
                forceEditBoxSegmentID = nil
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Easy1Line")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.62))
                HStack(spacing: 5) {
                    if editingDocumentName {
                        TextField("Schematic name", text: $document.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 190)
                    } else {
                        Text(document.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .frame(width: 190, alignment: .leading)
                    }
                    Button { editingDocumentName.toggle() } label: {
                        Image(systemName: editingDocumentName ? "checkmark" : "pencil")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.45))
                    .help(editingDocumentName ? "Finish renaming drawing" : "Rename drawing")
                }
                if !currentDisplayName.isEmpty {
                    Button { showProfilePicker = true } label: {
                        Label(currentDisplayName, systemImage: "person")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Change profile")
                }
                if !cloudStatus.isEmpty {
                    Button {
                        cloudStatus = ""
                    } label: {
                        Text(cloudStatus)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.cyan.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss status: \(cloudStatus)")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
            Menu("File") {
                Button("Drawings") { showLibrary.toggle() }
                Divider()
                Button("New Drawing") { showNewDrawingWarning = true }
                Button("Save locally") { promptForSaveName(toCloud: false) }
                Button("Save version") { promptForVersion() }
                Button("Version history") { showVersionHistory.toggle() }
                Button("Export .line") { showFileExporter = true }
                Button("Export PDF") { preparePDFShare() }
                Button("Import .line") { showFileImporter = true }
                Button("Save to cloud") { promptForSaveName(toCloud: true) }
                Button("Load from cloud") { Task { await loadCloudDrawings() } }
                Button("View netlist") { showNetlist.toggle() }
                Button("Clear status") { cloudStatus = "" }
            }
            .buttonStyle(EditorButtonStyle())

            Menu("Libraries") {
                Button("Wires") { showLineLibrary.toggle() }
                Button("Colors") { showColorLibrary.toggle() }
                Button("Items") { showTargetLibrary.toggle() }
                Button("Sync item library") { Task { await syncLibraries() } }
            }
            .buttonStyle(EditorButtonStyle())

            Menu("Tools") {
                Button {
                    fixAllWires()
                } label: {
                    Label("Fix all wires", systemImage: "cross.case")
                }
            }
            .buttonStyle(EditorButtonStyle())
            .accessibilityLabel("Schematic tools")

            Button("Visualizations") { showVisualizationsPanel.toggle() }
            .buttonStyle(EditorButtonStyle(isActive: snapToGrid || wireBridgesEnabled || showConnectionNames || showWireLegend))
            .accessibilityLabel("Toggle canvas visualizations")
            .popover(isPresented: $showVisualizationsPanel) { visualizationsPanel }

            Button("Labels") { showLabelsPanel.toggle() }
            .buttonStyle(EditorButtonStyle(isActive: showWireLabels))
            .accessibilityLabel("Configure wire labels")
            .popover(isPresented: $showLabelsPanel) { labelsPanel }

            Menu("Settings") {
                Button { snapToGrid.toggle() } label: {
                    Label("Snap to grid: \(snapToGrid ? "On" : "Off")", systemImage: snapToGrid ? "checkmark.circle.fill" : "circle")
                }
                Stepper("Auto-straighten distance: \(wireAlignmentTolerance, specifier: "%.0f") px", value: $wireAlignmentTolerance, in: 1...25, step: 1)
                Stepper("Base item size: \(Int(baseItemSize * 100))%", value: $baseItemSize, in: 0.5...1.15, step: 0.05)
                Button {
                    showSelectionColorPicker = true
                } label: {
                    Label("Selection border color", systemImage: "circle.fill")
                        .imageScale(.large)
                        .tint(Color(hex: selectionHighlightColorHex))
                }
                .accessibilityLabel("Selection border color")
                Button {
                    showBackgroundColorPicker = true
                } label: {
                    Label("Background color", systemImage: "circle.fill")
                        .imageScale(.large)
                        .tint(Color(hex: canvasBackgroundColorHex))
                }
                .accessibilityLabel("Background color")
                Button("Background image") { showBackgroundImagePanel.toggle() }
                Divider()
                Button("Reset Toolbars") { resetToolbars() }
                Divider()
                Text("Version \(appVersion)")
            }
            .buttonStyle(EditorButtonStyle())
            .accessibilityLabel("App settings")
            .popover(isPresented: $showBackgroundColorPicker) {
                ColorPicker("Background color", selection: Binding(
                    get: { Color(hex: canvasBackgroundColorHex) },
                    set: { canvasBackgroundColorHex = $0.hexString }
                ))
                .padding()
                .frame(width: 260)
            }
            .popover(isPresented: $showSelectionColorPicker) {
                ColorPicker("Selection border color", selection: Binding(
                    get: { Color(hex: selectionHighlightColorHex) },
                    set: { selectionHighlightColorHex = $0.hexString }
                ), supportsOpacity: false)
                .padding()
                .frame(width: 260)
            }

                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(EditorButtonStyle())
                .disabled(undoStack.isEmpty)
                .opacity(undoStack.isEmpty ? 0.4 : 1.0)
                .accessibilityLabel("Undo")

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(EditorButtonStyle())
                .disabled(redoStack.isEmpty)
                .opacity(redoStack.isEmpty ? 0.4 : 1.0)
                .accessibilityLabel("Redo")

                Button(action: toggleConnectionMode) {
                    Image(systemName: connectionMode ? "xmark.circle.fill" : "link.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(EditorButtonStyle(isActive: connectionMode))
                .accessibilityLabel(connectionMode ? "Exit Connect mode" : "Enter Connect mode")

                Button(action: { showMultiuserSheet = true }) {
                    Image(systemName: multipeerSession.connectedPeers.isEmpty ? "person.2.wave.2" : "person.2.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(EditorButtonStyle(isActive: !multipeerSession.connectedPeers.isEmpty))
                .accessibilityLabel("Multiuser session")

                Button(action: toggleRemoteSync) {
                    Image(systemName: remoteSyncEnabled ? "arrow.triangle.2.circlepath.icloud.fill" : "arrow.triangle.2.circlepath.icloud")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(EditorButtonStyle(isActive: remoteSyncEnabled))
                .help(remoteSyncEnabled ? "Stop remote sync" : "Start remote sync")
                .accessibilityLabel(remoteSyncEnabled ? "Stop remote sync" : "Start remote sync")
            }
        }

        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var palette: some View {
        let compact = targetsPanelWidth < 180
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { targetsPanelExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if !compact {
                        Text("COMPONENTS")
                            .font(.system(size: 14.95, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Image(systemName: targetsPanelExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(itemsPanelDragGesture)
            .accessibilityLabel(targetsPanelExpanded ? "Collapse items" : "Expand items")

            if targetsPanelExpanded {
                ScrollView {
                    ForEach(TargetKind.palette) { kind in
                        PaletteItem(kind: kind, compact: compact)
                            .contentShape(Rectangle())
                            .onTapGesture { addTarget(kind) }
                            .overlay(alignment: .trailing) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 48, height: 38)
                                    .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(RoundedRectangle(cornerRadius: 6))
                                    .highPriorityGesture(
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

                if !compact {
                    Text("Drag to place\nTap to add at center")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                    .accessibilityLabel("Resize items panel")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, targetsPanelExpanded ? 14 : 10)
        .frame(width: targetsPanelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { itemsPanelHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in itemsPanelHeight = newHeight }
            }
        }
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
                            targetsPanelWidth = min(max((targetsPanelWidthResizeStart ?? targetsPanelWidth) + value.translation.width, 30), 360)
                        }
                        .onEnded { _ in targetsPanelWidthResizeStart = nil }
                )
                .accessibilityLabel("Resize items panel width")
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
            let points = orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
            for point in points {
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
        if bounds.isNull { return CGRect(x: 0, y: 0, width: 1000, height: 700) }
        return bounds.insetBy(dx: -40, dy: -40)
    }

    /// Zooms/pans so all targets and wires (not the background image) fit in view - reuses the same bounds as PDF export.
    private func zoomToExtents() {
        guard editorSize != .zero else { return }
        let bounds = selectedContentBounds ?? pdfContentBounds()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scaleX = editorSize.width / bounds.width
        let scaleY = editorSize.height / bounds.height
        let newScale = min(max(min(scaleX, scaleY) * 0.85, 0.25), 4)
        let boundsCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let canvasCenter = CGPoint(x: canvasFieldSize / 2, y: canvasFieldSize / 2)
        canvasRotation = .zero
        canvasScale = newScale
        canvasOffset = CGSize(width: (canvasCenter.x - boundsCenter.x) * newScale, height: (canvasCenter.y - boundsCenter.y) * newScale)
    }

    private var selectedContentBounds: CGRect? {
        guard !selectedTargetIDs.isEmpty || !selectedSegmentIDs.isEmpty else { return nil }
        var bounds = CGRect.null
        for targetID in selectedTargetIDs {
            guard let target = target(with: targetID) else { continue }
            let halfWidth: CGFloat = target.kind == .junction ? 9 : target.isCompact ? 20 : 54
            let halfHeight: CGFloat = target.kind == .junction ? 9 : target.isCompact ? 20 : 38
            let scale = CGFloat(target.scale)
            bounds = bounds.union(CGRect(
                x: target.position.x - halfWidth * scale,
                y: target.position.y - halfHeight * scale,
                width: halfWidth * 2 * scale,
                height: halfHeight * 2 * scale
            ))
        }
        for segmentID in selectedSegmentIDs {
            guard let segment = document.segments.first(where: { $0.id == segmentID }),
                  let start = target(with: segment.startID),
                  let end = target(with: segment.endID) else { continue }
            let points = cachedWirePoints[segment.id] ?? orthogonalPoints(for: segment, from: start, to: end, avoiding: [])
            for point in points {
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
        guard !bounds.isNull else { return nil }
        return bounds.insetBy(dx: -40, dy: -40)
    }

    private func pdfCanvas(in size: CGSize, origin: CGPoint) -> some View {
        ZStack {
            GridBackground(color: Color(hex: canvasBackgroundColorHex))
            ZStack {
                Canvas { context, _ in
                    for segment in document.segments {
                        guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
                        let path = orthogonalPath(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
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
                        connectionCounts: [:],
                        selectedSlots: [],
                        connectionNames: target.connectionNames,
                        showConnectionNames: showConnectionNames,
                        baseItemSize: baseItemSize,
                        selectionHighlightColor: Color(hex: selectionHighlightColorHex),
                        connectionMode: false,
                        connectionMoveMode: false,
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
            GridBackground(color: Color(hex: canvasBackgroundColorHex))
                .contentShape(Rectangle())
                .simultaneousGesture(panGesture)
                .onTapGesture {
                    guard !connectionMode else { return }
                    selectedTargetIDs.removeAll()
                    selectedConnectionSlots.removeAll()
                    selectedSegmentID = nil
                    selectedSegmentIDs.removeAll()
                }

            ZStack {
                if let bgImage = backgroundImage {
                    Image(uiImage: bgImage)
                        .resizable()
                        .opacity(backgroundImageOpacity)
                        .frame(width: backgroundImageSize.width, height: backgroundImageSize.height)
                        .position(backgroundImagePosition)
                        .gesture(
                            !backgroundImageLocked ? DragGesture()
                                .onChanged { value in
                                    backgroundImagePosition.x += value.translation.width / 25
                                    backgroundImagePosition.y += value.translation.height / 25
                                }
                                .onEnded { _ in
                                    saveBackgroundImageState()
                                } : nil
                        )
                }
            
            Canvas { context, _ in
                for segment in document.segments {
                    guard let points = cachedWirePoints[segment.id], !points.isEmpty else { continue }
                    var path = Path()
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                    if selectedSegmentIDs.contains(segment.id) {
                        context.stroke(path, with: .color(Color(hex: selectionHighlightColorHex).opacity(0.35)), style: StrokeStyle(lineWidth: segment.displayWidth + 14, lineCap: .round, lineJoin: .round))
                    }
                    if wireAlignmentPreviewSegmentIDs.contains(segment.id) {
                        context.stroke(path, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.displayWidth, lineCap: .round, lineJoin: .round))
                }

                for bridge in cachedBridgeStrokes {
                    context.stroke(bridge.path, with: .color(bridge.color), style: StrokeStyle(lineWidth: bridge.width, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(false)

            if !wireConnectionMoveMode {
            ForEach(document.segments) { segment in
                if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                    let points = cachedWirePoints[segment.id] ?? orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
                    ForEach(0..<(points.count - 1), id: \.self) { sectionIndex in
                        if sectionIndex > 0 && sectionIndex + 1 < points.count - 1 {
                            SegmentHitArea(path: sectionPath(from: points[sectionIndex], to: points[sectionIndex + 1]), isSelected: selectedSegmentIDs.contains(segment.id), isSectionSelected: selectedSegmentID == segment.id && selectedSegmentSectionIndex == sectionIndex, onDrag: { translation in
                                moveSegmentSection(segment.id, sectionIndex: sectionIndex, translation: canvasDelta(for: translation))
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
                            }, onTapAt: { location in
                                if wirePlacementMode != nil { placeWirePoint(at: location) }
                            })
                        } else {
                            // Stub sections: keep the hit area clear of the pin so pin taps aren't swallowed by the wire.
                            let pinEnd = sectionIndex == 0 ? points[sectionIndex] : points[sectionIndex + 1]
                            let farEnd = sectionIndex == 0 ? points[sectionIndex + 1] : points[sectionIndex]
                            let movableSectionIndex = sectionIndex
                            SegmentHitArea(path: sectionPath(from: points[sectionIndex], to: points[sectionIndex + 1]), hitPath: sectionPath(from: trimmed(pinEnd, toward: farEnd, by: 4), to: farEnd), isSelected: selectedSegmentIDs.contains(segment.id), isSectionSelected: false, onDrag: { translation in
                                moveSegmentSection(segment.id, sectionIndex: movableSectionIndex, translation: canvasDelta(for: translation))
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
                            }, onTapAt: { location in
                                if wirePlacementMode != nil { placeWirePoint(at: location) }
                            })
                        }
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
                    connectedColor: cachedConnectedColor[target.id] ?? .cyan,
                    connectedColors: cachedConnectedColors[target.id] ?? [],
                    occupiedSlots: cachedOccupiedSlots[target.id] ?? [],
                                        connectionCounts: cachedConnectionCounts[target.id] ?? [:],
                    selectedSlots: selectedConnectionSlots[target.id].map { Set([$0]) } ?? [],
                    connectionNames: target.connectionNames,
                    showConnectionNames: showConnectionNames,
                    baseItemSize: baseItemSize,
                    selectionHighlightColor: Color(hex: selectionHighlightColorHex),
                    connectionMode: connectionMode,
                    connectionMoveMode: wireConnectionMoveMode,
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
                .onTapGesture(count: 2) {
                    openTargetInfo(target)
                }
                // Junctions are small and often sit directly on a wire's hit area; force the tap
                // to win over any overlapping wire gesture instead of letting z-order/ambiguity decide.
                // Only one single-tap recognizer is attached at a time -- adding both a plain
                // onTapGesture AND this for the same view made Mac click recognition unreliable.
                .singleTapToSelect(isJunction: target.kind == .junction) { targetTapped(target) }
            }

            if showWireLabels {
                ForEach(document.segments) { segment in
                    if let start = target(with: segment.startID), let end = target(with: segment.endID) {
                        let points = cachedWirePoints[segment.id] ?? orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
                        wireLabel(segment, on: points)
                    }
                }
            }

            }
        }
        .frame(width: canvasFieldSize, height: canvasFieldSize)
        .scaleEffect(canvasScale, anchor: .center)
        .rotationEffect(canvasRotation)
        .offset(canvasOffset)
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { editorSize = size }
        .onChange(of: size) { _, newSize in
            guard newSize != .zero else { return }
            editorSize = newSize
            recoverToolbarOffsetsIfNeeded()
        }
        .simultaneousGesture(MagnificationGesture().onChanged { value in
            guard !canvasLocked else { return }
            isPinchingOrRotating = true
            if gestureStartScale == nil { gestureStartScale = canvasScale }
            let oldScale = canvasScale
            let newScale = min(4, max(0.25, (gestureStartScale ?? 1) * value))
            // Keep whatever's currently centered in the viewport centered as the scale changes,
            // instead of always snapping back toward the canvas's abstract center point.
            if oldScale > 0 {
                let factor = newScale / oldScale
                canvasOffset = CGSize(width: canvasOffset.width * factor, height: canvasOffset.height * factor)
            }
            canvasScale = newScale
        }.onEnded { _ in
            gestureStartScale = nil
            isPinchingOrRotating = false
        })
        .simultaneousGesture(RotationGesture().onChanged { value in
            guard !canvasLocked, !rotationLocked else { return }
            isPinchingOrRotating = true
            if gestureStartRotation == nil { gestureStartRotation = canvasRotation }
            let newAngle = (gestureStartRotation ?? .zero) + value
            let delta = newAngle.radians - canvasRotation.radians
            // Rotate the existing pan offset by the same increment so whatever's centered stays centered.
            canvasOffset = CGSize(
                width: canvasOffset.width * CGFloat(cos(delta)) - canvasOffset.height * CGFloat(sin(delta)),
                height: canvasOffset.width * CGFloat(sin(delta)) + canvasOffset.height * CGFloat(cos(delta))
            )
            canvasRotation = newAngle
        }.onEnded { _ in
            gestureStartRotation = nil
            isPinchingOrRotating = false
        })
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                selectionBox
                    .offset(x: selectionToolbarOffsetX, y: selectionToolbarOffsetY)
                    .simultaneousGesture(toolbarDragGesture(isTarget: false))
                zoomControls
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { zoomToolbarWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, newWidth in zoomToolbarWidth = newWidth }
                        }
                    }
                    .offset(x: zoomToolbarOffsetX, y: zoomToolbarOffsetY)
                    .simultaneousGesture(toolbarDragGesture(isTarget: false, isZoom: true))
            }
            .padding(.top, 88)
            .padding(.trailing, 24)
        }
    }

    private func wireLabel(_ segment: SchematicSegment, on points: [CGPoint]) -> some View {
        let anchor = labelAnchor(for: segment, on: points)
        let labelPoint = anchor.point
        let direction = anchor.direction
        let labelPointWithOffset = CGPoint(x: labelPoint.x - direction.dy / max(direction.length, 1) * 14, y: labelPoint.y + direction.dx / max(direction.length, 1) * 14)
        var angle = atan2(direction.dy, direction.dx)
        if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }
        let fields: [String] = [
            showWireNames ? segment.name : nil,
            showWireLengths ? "\(Int(pathLength(points).rounded())) px" : nil,
            showWireSizes ? segment.size : nil,
            showWireMaterials ? segment.type : nil,
            showWireCoverings ? segment.misc : nil,
            showWireNetNames ? netName(for: segment) : nil
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
                let start = wireLabelDragStartPoints[segment.id] ?? labelPoint
                wireLabelDragStartPoints[segment.id] = start
                guard let startTarget = target(with: segment.startID), let endTarget = target(with: segment.endID) else { return }
                let route = orthogonalPoints(for: segment, from: startTarget, to: endTarget, avoiding: [])
                let delta = canvasDelta(for: value.translation)
                let proposed = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
                updateWireLabelPosition(segment.id, route: route, near: proposed)
            }.onEnded { _ in
                wireLabelDragStartPoints.removeValue(forKey: segment.id)
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

    private func labelAnchor(for segment: SchematicSegment, on points: [CGPoint]) -> (point: CGPoint, direction: (dx: CGFloat, dy: CGFloat, length: CGFloat)) {
        let sectionIndex = segment.labelSectionIndex >= 0 && segment.labelSectionIndex < points.count - 1 ? segment.labelSectionIndex : max(0, min(points.count - 2, points.count / 2 - 1))
        let first = points[sectionIndex]
        let second = points[sectionIndex + 1]
        let sectionFraction = min(max(segment.labelSectionPosition, 0), 1)
        let point = CGPoint(x: first.x + (second.x - first.x) * sectionFraction, y: first.y + (second.y - first.y) * sectionFraction)
        return (point, (second.x - first.x, second.y - first.y, hypot(second.x - first.x, second.y - first.y)))
    }

    private func updateWireLabelPosition(_ id: UUID, route: [CGPoint], near location: CGPoint) {
        guard let index = document.segments.firstIndex(where: { $0.id == id }) else { return }
        var bestSectionIndex = 0
        var bestSectionPosition = 0.5
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (sectionIndex, pair) in zip(route, route.dropFirst()).enumerated() {
            let candidate = nearestPoint(on: [pair.0, pair.1], to: location)
            let segmentLength = hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            if candidate.distance < bestDistance {
                bestDistance = candidate.distance
                let distanceOnSection = hypot(candidate.point.x - pair.0.x, candidate.point.y - pair.0.y)
                bestSectionIndex = sectionIndex
                bestSectionPosition = segmentLength == 0 ? 0.5 : Double(distanceOnSection / segmentLength)
            }
        }
        document.segments[index].labelSectionIndex = bestSectionIndex
        document.segments[index].labelSectionPosition = min(max(bestSectionPosition, 0), 1)
    }

    private var showWireLabels: Bool {
        showWireNames || showWireLengths || showWireSizes || showWireMaterials || showWireCoverings || showWireNetNames
    }

    private func placeDockItem(_ kind: TargetKind, at screenLocation: CGPoint) {
        guard editorSize != .zero else { return }
        let dropPoint = canvasDropPoint(screenLocation, canvasSize: editorSize)
        let snappedDropPoint = snapToGrid ? snappedPosition(dropPoint) : dropPoint
        #if targetEnvironment(macCatalyst)
        let dropOffset: CGFloat = 0
        #else
        let dropOffset: CGFloat = kind == .junction ? 0 : 9
        #endif
        let iconPoint = CGPoint(x: snappedDropPoint.x, y: snappedDropPoint.y + dropOffset)
        addTarget(kind, at: iconPoint)
        guard let id = document.targets.last?.id,
              let index = document.targets.firstIndex(where: { $0.id == id }) else { return }
        document.targets[index].position = iconPoint
        splitSegmentIfNeeded(for: id)
    }

    private func canvasDropPoint(_ location: CGPoint, canvasSize viewportSize: CGSize) -> CGPoint {
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let canvasCenter = CGPoint(x: canvasFieldSize / 2, y: canvasFieldSize / 2)
        let translated = CGPoint(x: location.x - viewportCenter.x - canvasOffset.width, y: location.y - viewportCenter.y - canvasOffset.height)
        let inverseAngle = -canvasRotation.radians
        let rotated = CGPoint(
            x: translated.x * CGFloat(cos(inverseAngle)) - translated.y * CGFloat(sin(inverseAngle)),
            y: translated.x * CGFloat(sin(inverseAngle)) + translated.y * CGFloat(cos(inverseAngle))
        )
        return CGPoint(x: rotated.x / canvasScale + canvasCenter.x, y: rotated.y / canvasScale + canvasCenter.y)
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
            Button { rotationLocked.toggle() } label: {
                Image(systemName: rotationLocked ? "lock.rotation" : "lock.rotation.open")
            }
            .buttonStyle(EditorButtonStyle(isActive: rotationLocked))
            .help(rotationLocked ? "Unlock canvas rotation" : "Lock canvas rotation")
            .disabled(canvasLocked)
            Button { zoomToExtents() } label: {
                Image(systemName: "viewfinder")
            }
            .buttonStyle(EditorButtonStyle())
            .help("Zoom to fit items and wires (ignores background image)")
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
        // .global is required: this gesture is attached inside the scaled/rotated content subtree, so
        // the default .local coordinate space would report translation already distorted by canvasScale.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !canvasLocked, !isPinchingOrRotating else { return }
                canvasOffset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
            }
            .onEnded { _ in panStart = canvasOffset }
    }

    private func targetDragGesture(for target: SchematicTarget, canvasSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard !connectionMode, !wireConnectionMoveMode, !editingConnectionPoints, !target.locked else { return }
                draggingTargetID = target.id
                guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
                if dragStartPositions[target.id] == nil {
                    captureForUndo()
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
                guard dragStartPositions[target.id] != nil else { return }
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
                    splitSegmentIfNeeded(for: targetID)
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

    private func routingObstacles(excluding ids: UUID...) -> [SchematicTarget] {
        document.targets.filter { target in
            !ids.contains(target.id) && target.id != draggingTargetID
        }
    }

    /// Recomputes wire routing (points + bridge crossings) once per document change instead of on every render,
    /// so panning/zooming the canvas (which doesn't change the document) doesn't re-run pathfinding every frame.
    private func recomputeWireGeometry() {
        var points: [UUID: [CGPoint]] = [:]
        for segment in document.segments {
            guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            let route = segmentDragStartPoints[segment.id] != nil
                ? segment.routePoints
                : orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
            points[segment.id] = routeWithInsertedOrthogonalJoints(route)
        }
        cachedWirePoints = points

        var connColor: [UUID: Color] = [:]
        var connColors: [UUID: [Color]] = [:]
        var occSlots: [UUID: Set<Int>] = [:]
        var connectionCounts: [UUID: [Int: Int]] = [:]
        for docTarget in document.targets {
            connColor[docTarget.id] = document.segments.first(where: { $0.startID == docTarget.id || $0.endID == docTarget.id }).map { $0.color } ?? .cyan
            var colorsList: [Color] = []
            var slots = Set<Int>()
            var counts: [Int: Int] = [:]
            for segment in document.segments {
                if segment.startID == docTarget.id || segment.endID == docTarget.id {
                    if !colorsList.contains(where: { $0.hexString == segment.color.hexString }) {
                        colorsList.append(segment.color)
                    }
                }
                if segment.startID == docTarget.id {
                    let slot = segment.startSlot ?? 0
                    slots.insert(slot)
                    counts[slot, default: 0] += 1
                }
                if segment.endID == docTarget.id {
                    let slot = segment.endSlot ?? 0
                    slots.insert(slot)
                    counts[slot, default: 0] += 1
                }
            }
            connColors[docTarget.id] = colorsList
            occSlots[docTarget.id] = slots
            connectionCounts[docTarget.id] = counts
        }
        cachedConnectedColor = connColor
        cachedConnectedColors = connColors
        cachedOccupiedSlots = occSlots
        cachedConnectionCounts = connectionCounts

        guard wireBridgesEnabled else {
            cachedBridgeStrokes = []
            return
        }
        var bridges: [(path: Path, color: Color, width: CGFloat)] = []
        for firstIndex in document.segments.indices {
            guard let firstPoints = points[document.segments[firstIndex].id] else { continue }
            for secondIndex in document.segments.indices.dropFirst(firstIndex + 1) {
                guard let secondPoints = points[document.segments[secondIndex].id] else { continue }
                for crossing in crossings(between: firstPoints, and: secondPoints) {
                    let bridge = bridgePath(at: crossing.point, overHorizontal: !crossing.firstIsHorizontal)
                    let bridgeColor = document.segments[secondIndex].color
                    let bridgeWidth = document.segments[secondIndex].displayWidth
                    bridges.append((bridge, Color(red: 0.07, green: 0.09, blue: 0.105), bridgeWidth + 7))
                    bridges.append((bridge, bridgeColor, bridgeWidth))
                }
            }
        }
        cachedBridgeStrokes = bridges
    }

    private func targetTapped(_ target: SchematicTarget) {
        if connectionMode || wireConnectionMoveMode {
            return
        }
        if selectedTargetIDs.contains(target.id) {
            cycleConnectionPoint(for: target)
            return
        }
        selectTarget(target)
    }

    private func openTargetInfo(_ target: SchematicTarget) {
        guard !connectionMode else { return }
        let isVisible = (showEditBoxOnSelection && dismissedEditBoxTargetID != target.id) || forceEditBoxTargetID == target.id
        if isVisible {
            forceEditBoxTargetID = nil
            dismissedEditBoxTargetID = target.id
        } else {
            forceEditBoxTargetID = target.id
            dismissedEditBoxTargetID = nil
        }
        forceEditBoxSegmentID = nil
        dismissedEditBoxSegmentID = nil
        if !selectedTargetIDs.contains(target.id) {
            selectedTargetIDs = [target.id]
        }
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        selectedConnectionSlots.removeAll()
    }

    private func openWireInfo(_ wire: SchematicSegment, sectionIndex: Int) {
        wirePinMoveTargetID = nil
        wireConnectionMoveMode = false
        let isVisible = (showEditBoxOnSelection && dismissedEditBoxSegmentID != wire.id) || forceEditBoxSegmentID == wire.id
        if isVisible {
            forceEditBoxSegmentID = nil
            dismissedEditBoxSegmentID = wire.id
        } else {
            forceEditBoxSegmentID = wire.id
            dismissedEditBoxSegmentID = nil
        }
        forceEditBoxTargetID = nil
        dismissedEditBoxTargetID = nil
        selectedTargetIDs.removeAll()
        selectedSegmentIDs = [wire.id]
        selectedSegmentID = wire.id
        selectedSegmentSectionIndex = sectionIndex
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
        if connectionMode {
            handleConnectionModeConnectionPoint(targetID: targetID, slot: slot)
            return
        }
        if wireConnectionMoveMode {
            guard let wire = selectedSegment,
                  let index = document.segments.firstIndex(where: { $0.id == wire.id }) else { return }
            if wirePinMoveTargetID == nil {
                guard targetID == wire.startID || targetID == wire.endID else { return }
                wirePinMoveTargetID = targetID
                selectedConnectionSlots[targetID] = targetID == wire.startID ? (wire.startSlot ?? 0) : (wire.endSlot ?? 0)
                return
            }
            guard let sourceTargetID = wirePinMoveTargetID,
                  targetID != sourceTargetID,
                  let target = target(with: targetID),
                  slot >= 0, slot < target.maxConnections else { return }
            let occupied = occupiedSlots(for: targetID)
            guard target.kind == .junction || !occupied.contains(slot) else { return }
            if wire.startID == sourceTargetID {
                document.segments[index].startID = targetID
                document.segments[index].startSlot = slot
            } else if wire.endID == sourceTargetID {
                document.segments[index].endID = targetID
                document.segments[index].endSlot = slot
            }
            document.segments[index].routePoints.removeAll()
            wirePinMoveTargetID = nil
            wireConnectionMoveMode = false
            selectedConnectionSlots.removeAll()
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

    private func handleConnectionModeConnectionPoint(targetID: UUID, slot: Int) {
        guard let target = target(with: targetID), slot >= 0, slot < target.maxConnections else { return }
        
        // Toggle: clicking selected pin deselects it
        if selectedConnectionSlots[targetID] == slot {
            selectedConnectionSlots.removeValue(forKey: targetID)
            connectionModeTargetIDs.removeAll(where: { $0 == targetID })
            return
        }
        
        if let previousID = connectionModeTargetIDs.last,
           let previousSlot = selectedConnectionSlots[previousID],
           previousID != targetID,
           connectTargets(previousID, targetID, startSlot: previousSlot, endSlot: slot) {
            // Connection made; clear selection and ready for next connection
            connectionModeTargetIDs.removeAll()
            selectedConnectionSlots.removeAll()
        } else if connectionModeTargetIDs.isEmpty {
            connectionModeTargetIDs = [targetID]
            selectedConnectionSlots = [targetID: slot]
        }
    }

    private func connectSelectedTargets() {
        let ids = selectedTargetIDs
        guard ids.count >= 2 else { return }
        var connected = false
        for pairIndex in 0..<(ids.count - 1) {
            let startID = ids[pairIndex]
            let endID = ids[pairIndex + 1]
            let startSlot = selectedConnectionSlots[startID] ?? closestAvailableSlot(for: startID, to: endID)
            let endSlot = selectedConnectionSlots[endID] ?? closestAvailableSlot(for: endID, to: startID)
            connected = connectTargets(startID, endID, startSlot: startSlot, endSlot: endSlot) || connected
        }
        if connected {
            selectedTargetIDs.removeAll()
            selectedConnectionSlots.removeAll()
        }
    }

    @discardableResult
    private func connectTargets(_ startID: UUID, _ endID: UUID, startSlot: Int? = nil, endSlot: Int? = nil) -> Bool {
          guard let resolvedStartSlot = resolvedConnectionSlot(for: startID, requestedSlot: startSlot, toward: endID),
              let resolvedEndSlot = resolvedConnectionSlot(for: endID, requestedSlot: endSlot, toward: startID),
              !document.segments.contains(where: { ($0.startID == startID && $0.endID == endID) || ($0.startID == endID && $0.endID == startID) }) else { return false }
        captureForUndo()
        let line = selectedLineDefinition ?? document.lineDefinitions.first ?? LineDefinition.defaultLine
        document.segments.append(SchematicSegment(startID: startID, endID: endID, startSlot: resolvedStartSlot, endSlot: resolvedEndSlot, name: line.name, colorHex: line.colorHex, size: line.wireSize, type: line.wireType, misc: line.misc, displayWidth: 3, description: line.description))
        autoOrientTargetIfHelpful(startID)
        autoOrientTargetIfHelpful(endID)
        return true
    }

    private func autoOrientTargetIfHelpful(_ targetID: UUID) {
        guard let targetIndex = document.targets.firstIndex(where: { $0.id == targetID }),
              document.targets[targetIndex].kind != .junction else { return }
        let target = document.targets[targetIndex]
        let connections = document.segments.compactMap { segment -> (slot: Int, other: SchematicTarget)? in
            if segment.startID == targetID, let other = self.target(with: segment.endID) {
                return (segment.startSlot ?? 0, other)
            }
            if segment.endID == targetID, let other = self.target(with: segment.startID) {
                return (segment.endSlot ?? 0, other)
            }
            return nil
        }
        guard !connections.isEmpty else { return }

        let currentAngles = connections.map { connection in
            connectionAngle(for: target, slot: connection.slot)
        }
        let desiredAngles = connections.map { connection in
            atan2(connection.other.position.y - target.position.y, connection.other.position.x - target.position.x) * 180 / Double.pi
        }
        func score(for delta: Double) -> Double {
            zip(currentAngles, desiredAngles).reduce(0) { total, pair in
                total + angularDistance(pair.0 + delta, pair.1)
            }
        }

        let candidates: [Double] = [0, 180]
        guard let bestDelta = candidates.min(by: { score(for: $0) < score(for: $1) }),
              score(for: bestDelta) + 0.5 < score(for: 0) else { return }
        rotateTarget(target, by: bestDelta)
    }

    private func resolvedConnectionSlot(for targetID: UUID, requestedSlot: Int?, toward otherID: UUID) -> Int? {
        guard let target = target(with: targetID) else { return nil }
        guard target.kind == .junction else { return requestedSlot ?? closestAvailableSlot(for: targetID, to: otherID) }
        let occupied = occupiedSlots(for: targetID)
        if occupied.count == 1, let existingSlot = occupied.first {
            let oppositeSlot = [1, 0, 3, 2, 5, 4, 7, 6][min(existingSlot, 7)]
            if !occupied.contains(oppositeSlot) { return oppositeSlot }
        }
        if let requestedSlot, requestedSlot >= 0, requestedSlot < target.maxConnections, !occupied.contains(requestedSlot) {
            return requestedSlot
        }
        return closestAvailableSlot(for: targetID, to: otherID)
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
        let junction = SchematicTarget(identifier: nextTargetIdentifier(for: .junction), kind: .junction, name: "Junction", position: nearest, maxConnections: 8, colorHex: TargetKind.junction.defaultColorHex)
        document.targets.append(junction)
        document.segments.remove(at: segmentIndex)
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: junction.id, startSlot: segment.startSlot, endSlot: 0, name: segment.name + " A", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, displayWidth: segment.displayWidth, description: segment.description), at: segmentIndex)
        document.segments.insert(SchematicSegment(startID: junction.id, endID: segment.endID, startSlot: 1, endSlot: segment.endSlot, name: segment.name + " B", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, displayWidth: segment.displayWidth, description: segment.description), at: segmentIndex + 1)
        let targetSlot = selectedConnectionSlots[targetID] ?? closestAvailableSlot(for: targetID, to: junction.id) ?? 0
        document.segments.append(SchematicSegment(startID: targetID, endID: junction.id, startSlot: targetSlot, endSlot: 2, name: "Connection", colorHex: "31D7E8", size: "14 AWG", type: "Copper", misc: "BARE", displayWidth: 3, description: "Target connection"))
        selectedTargetIDs.removeAll()
        selectedSegmentIDs.removeAll()
        selectedSegmentID = nil
        selectedConnectionSlots.removeAll()
    }

    private func addTarget(_ kind: TargetKind, at point: CGPoint? = nil) {
        captureForUndo()
        let rawPosition = point ?? quickAddPosition()
        let position = snappedPosition(rawPosition)
        document.targets.append(SchematicTarget(identifier: nextTargetIdentifier(for: kind), kind: kind, name: kind.title, position: position, maxConnections: kind == .junction ? 8 : 2, colorHex: kind.defaultColorHex))
        selectedTargetIDs = [document.targets.last!.id]
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        editingConnectionPoints = false
        selectedSegmentIDs.removeAll()
    }

    private func nextTargetIdentifier(for kind: TargetKind) -> String {
        let used = Set(document.targets.map(\.identifier))
        var number = 1
        while used.contains(String(format: "%@%03d", kind.designatorPrefix, number)) {
            number += 1
        }
        return String(format: "%@%03d", kind.designatorPrefix, number)
    }

    private func addTarget(from template: TargetDefinition) {
        captureForUndo()
        let position = snappedPosition(quickAddPosition())
        document.targets.append(SchematicTarget(identifier: nextTargetIdentifier(for: template.kind), kind: template.kind, name: template.kind.title, position: position, maxConnections: template.maxConnections, colorHex: template.colorHex, symbol: template.symbol, imageData: template.imageData, connectionAngles: template.connectionAngles, scale: template.scale, isCompact: template.isCompact))
        selectedTargetIDs = [document.targets.last!.id]
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        showTargetLibrary = false
    }

    /// Cascades consecutively tap-added items diagonally so they don't stack directly on top of each other.
    private func quickAddPosition() -> CGPoint {
        let step: CGFloat = 44
        let cascade = CGFloat(quickAddCascadeIndex % 8)
        quickAddCascadeIndex += 1
        let viewportCenter = editorSize == .zero ? CGPoint(x: 480, y: 330) : CGPoint(x: editorSize.width / 2, y: editorSize.height / 2)
        let center = canvasDropPoint(viewportCenter, canvasSize: editorSize == .zero ? CGSize(width: 960, height: 660) : editorSize)
        return CGPoint(x: center.x + cascade * step, y: center.y + cascade * step)
    }

    private func saveTargetTemplate(_ target: SchematicTarget) {
        document.targetDefinitions.append(TargetDefinition(kind: target.kind, name: target.name, maxConnections: target.maxConnections, colorHex: target.colorHex, symbol: target.symbol, imageData: target.imageData, connectionAngles: target.connectionAngles, scale: target.scale, isCompact: target.isCompact))
    }

    private func duplicateTarget(_ target: SchematicTarget) {
        var copy = target
        copy.id = UUID()
        copy.identifier = nextTargetIdentifier(for: target.kind)
        copy.name = target.kind.title
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
                    size: first.size,
                    type: first.type,
                    misc: first.misc,
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

    private func removeTargetFromWire(_ target: SchematicTarget) {
        let attached = document.segments.filter { $0.startID == target.id || $0.endID == target.id }
        guard !attached.isEmpty else { return }
        if attached.count == 1 {
            captureForUndo()
            document.segments.removeAll { $0.id == attached[0].id }
            selectedTargetIDs = [target.id]
            selectedSegmentID = nil
            selectedSegmentIDs.removeAll()
            selectedConnectionSlots.removeAll()
            return
        }
        guard attached.count == 2 else { return }
        let first = attached[0]
        let route = orthogonalPoints(for: first, from: self.target(with: first.startID) ?? target, to: self.target(with: first.endID) ?? target, avoiding: [])
        let nearest = nearestPoint(on: route, to: target.position).point
        guard let section = nearestSection(of: route, to: nearest) else { return }
        let dx = section.end.x - section.start.x
        let dy = section.end.y - section.start.y
        let length: CGFloat = max(hypot(dx, dy), CGFloat(1))
        let side = CGPoint(x: -dy / length, y: dx / length)
        let movedPosition = CGPoint(x: nearest.x + side.x * 64, y: nearest.y + side.y * 64)
        guard mergeWireAroundTarget(target) else { return }
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        document.targets[index].position = movedPosition
        selectedTargetIDs = [target.id]
        selectedSegmentID = nil
        selectedSegmentIDs.removeAll()
        selectedConnectionSlots.removeAll()
    }

    private func canRemoveTargetFromWire(_ target: SchematicTarget) -> Bool {
        !document.segments.filter { $0.startID == target.id || $0.endID == target.id }.isEmpty
    }

    private func mergeWireAroundTarget(_ target: SchematicTarget) -> Bool {
        let attached = document.segments.filter { $0.startID == target.id || $0.endID == target.id }
        guard attached.count == 2 else { return false }
        let first = attached[0]
        let second = attached[1]
        let firstOtherID = first.startID == target.id ? first.endID : first.startID
        let secondOtherID = second.startID == target.id ? second.endID : second.startID
        guard firstOtherID != secondOtherID,
              let firstOther = self.target(with: firstOtherID),
              let secondOther = self.target(with: secondOtherID) else { return false }
        let firstOuterSlot = first.startID == target.id ? first.endSlot : first.startSlot
        let secondOuterSlot = second.startID == target.id ? second.endSlot : second.startSlot
        let startPoint = connectionPoint(for: firstOther, slot: firstOuterSlot)
        let endPoint = connectionPoint(for: secondOther, slot: secondOuterSlot)
        let startEscape = escapePoint(for: firstOther, slot: firstOuterSlot ?? 0, toward: secondOther)
        let endEscape = escapePoint(for: secondOther, slot: secondOuterSlot ?? 0, toward: firstOther)
        let obstacles = document.targets.filter { $0.id != target.id && $0.id != firstOtherID && $0.id != secondOtherID }.map(obstacleRect(for:))
        let candidates = [
            [startEscape, CGPoint(x: endEscape.x, y: startEscape.y), endEscape],
            [startEscape, CGPoint(x: startEscape.x, y: endEscape.y), endEscape],
            [startEscape, CGPoint(x: (startEscape.x + endEscape.x) / 2, y: startEscape.y), CGPoint(x: (startEscape.x + endEscape.x) / 2, y: endEscape.y), endEscape],
            [startEscape, CGPoint(x: startEscape.x, y: (startEscape.y + endEscape.y) / 2), CGPoint(x: endEscape.x, y: (startEscape.y + endEscape.y) / 2), endEscape]
        ].map { normalizedRoute(orthogonalizedPoints($0)) }.filter { pointsAreClear($0, from: obstacles) }
        let middleRoute = candidates.min(by: { pathLength($0) < pathLength($1) }) ?? []
        let routePoints = middleRoute.isEmpty ? [] : normalizedRoute([startPoint, startEscape] + middleRoute.dropFirst().dropLast() + [endEscape, endPoint])
        let replacement = SchematicSegment(startID: firstOtherID, endID: secondOtherID, startSlot: firstOuterSlot, endSlot: secondOuterSlot, name: first.name, colorHex: first.colorHex, size: first.size, type: first.type, misc: first.misc, netName: first.netName, displayWidth: first.displayWidth, description: first.description, routePoints: routePoints)
        captureForUndo()
        document.segments.removeAll { $0.id == first.id || $0.id == second.id }
        document.segments.append(replacement)
        return true
    }

    private var selectedTargetsAreLocked: Bool {
        !selectedTargetIDs.isEmpty && selectedTargetIDs.allSatisfy { target(with: $0)?.locked == true }
    }

    private enum TargetAlignment {
        case horizontal
        case vertical
    }

    private func alignSelectedTargets(_ alignment: TargetAlignment) {
        let targets = selectedTargetIDs.compactMap { target(with: $0) }
        guard targets.count >= 2 else { return }
        let movableTargets = targets.filter { !$0.locked }
        guard !movableTargets.isEmpty else { return }
        guard let anchor = selectedTargetIDs.last.flatMap({ target(with: $0) }) else { return }
        let reference = alignment == .horizontal ? anchor.position.x : anchor.position.y
        let movedIDs = Set(movableTargets.map(\.id))
        captureForUndo()
        for index in document.targets.indices where movedIDs.contains(document.targets[index].id) {
            if alignment == .horizontal {
                document.targets[index].position.x = reference
            } else {
                document.targets[index].position.y = reference
            }
        }
        for index in document.segments.indices where movedIDs.contains(document.segments[index].startID) || movedIDs.contains(document.segments[index].endID) {
            document.segments[index].routePoints.removeAll()
        }
    }

    private func distributeSelectedTargets(_ alignment: TargetAlignment) {
        let targets = selectedTargetIDs.compactMap { target(with: $0) }
        guard targets.count >= 3 else { return }
        let sortedTargets = targets.sorted {
            let firstPosition = alignment == .horizontal ? $0.position.x : $0.position.y
            let secondPosition = alignment == .horizontal ? $1.position.x : $1.position.y
            return firstPosition < secondPosition
        }
        let firstPosition = alignment == .horizontal ? sortedTargets[0].position.x : sortedTargets[0].position.y
        let lastPosition = alignment == .horizontal ? sortedTargets[sortedTargets.count - 1].position.x : sortedTargets[sortedTargets.count - 1].position.y
        let step = (lastPosition - firstPosition) / CGFloat(sortedTargets.count - 1)
        guard step.isFinite, abs(step) > 0.01 else { return }
        let movedIDs = Set(sortedTargets.dropFirst().dropLast().filter { !$0.locked }.map(\.id))
        guard !movedIDs.isEmpty else { return }
        captureForUndo()
        for (positionIndex, target) in sortedTargets.enumerated() where movedIDs.contains(target.id) {
            guard let targetIndex = document.targets.firstIndex(where: { $0.id == target.id }) else { continue }
            let position = firstPosition + step * CGFloat(positionIndex)
            if alignment == .horizontal {
                document.targets[targetIndex].position.x = position
            } else {
                document.targets[targetIndex].position.y = position
            }
        }
        for index in document.segments.indices where movedIDs.contains(document.segments[index].startID) || movedIDs.contains(document.segments[index].endID) {
            document.segments[index].routePoints.removeAll()
        }
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

    private func promptForVersion() {
        versionDescriptionDraft = ""
        showVersionPrompt = true
    }

    private func saveVersion() {
        let description = versionDescriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty,
              let data = SchematicDocument.snapshotData(for: document) else { return }
        document.versionHistory.insert(
            SchematicVersion(
                createdAt: Date(),
                description: description,
                userName: currentDisplayName,
                data: data
            ),
            at: 0
        )
        saveCurrent()
        cloudStatus = "Version saved"
    }

    private func recallVersion(_ version: SchematicVersion) {
        guard let restored = try? JSONDecoder().decode(SchematicDocument.self, from: version.data) else {
            cloudStatus = "Version could not be recalled"
            return
        }
        var recalled = restored
        recalled.versionHistory = document.versionHistory
        document = recalled
        showVersionHistory = false
        selectedTargetIDs.removeAll()
        selectedConnectionSlots.removeAll()
        selectedSegmentIDs.removeAll()
        selectedSegmentID = nil
        saveCurrent()
        autoZoomAfterLoad()
        cloudStatus = "Recalled version"
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
    }

    private func saveCurrent() {
        document.updatedByName = currentDisplayName
        if let index = savedDocuments.firstIndex(where: { $0.id == document.id }) { savedDocuments[index] = document } else { savedDocuments.append(document) }
        SchematicDocument.saveAll(savedDocuments)
        SchematicDocument.saveLast(document)
    }

    private func captureForUndo() {
        redoStack.removeAll()
        undoStack.append(document)
        if undoStack.count > 10 {
            undoStack.removeFirst()
        }
    }

    private func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(document)
        document = undoStack.removeLast()
        SchematicDocument.saveLast(document)
        restoreBackgroundImage()
    }

    private func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(document)
        document = redoStack.removeLast()
        SchematicDocument.saveLast(document)
        restoreBackgroundImage()
    }

    private func broadcastDocumentIfNeeded(_ newValue: SchematicDocument) {
        guard let encoded = try? JSONEncoder().encode(newValue) else { return }
        multipeerSession.send(encoded)
    }

    private func toggleRemoteSync() {
        if remoteSyncEnabled {
            remoteSyncEnabled = false
            remoteSyncTask?.cancel()
            remoteSyncTask = nil
            cloudStatus = "Remote sync stopped"
            return
        }
        guard SupabaseDrawingStore() != nil else {
            cloudStatus = "Supabase is not configured"
            return
        }
        remoteSyncEnabled = true
        remoteSyncLastKnownUpdatedAt = nil
        cloudStatus = "Remote sync started"
        remoteSyncTask = Task {
            await joinRemoteSync()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await runRemoteSyncStep()
            }
        }
    }

    /// Joining an existing remote session should adopt its current state rather than overwrite it;
    /// only push if no remote copy exists yet (first time this document is shared).
    private func joinRemoteSync() async {
        guard let store = SupabaseDrawingStore() else { return }
        do {
            if let remote = try await store.loadDrawing(id: document.id) {
                remoteSyncLastKnownUpdatedAt = try await store.loadDrawingUpdatedAt(id: document.id)
                let decoded = try JSONDecoder().decode(SchematicDocument.self, from: remote.data)
                guard decoded != document else { return }
                isApplyingRemoteDocument = true
                document = decoded
                DispatchQueue.main.async {
                    self.isApplyingRemoteDocument = false
                }
            } else {
                let data = try JSONEncoder().encode(document)
                try await store.saveDrawing(id: document.id, name: document.name, data: data, createdByName: document.createdByName, updatedByName: currentDisplayName)
            }
        } catch {
            recordError("Remote sync join failed: \(cloudErrorText(error))")
        }
    }

    private func runRemoteSyncStep() async {
        guard let store = SupabaseDrawingStore() else { return }
        if remoteSyncDirty {
            remoteSyncDirty = false
            do {
                let data = try JSONEncoder().encode(document)
                try await store.saveDrawing(id: document.id, name: document.name, data: data, createdByName: document.createdByName, updatedByName: currentDisplayName)
            } catch {
                recordError("Remote sync push failed: \(cloudErrorText(error))")
            }
            return // we just pushed our own latest state; no need to immediately pull it back
        }
        do {
            // Cheap timestamp check first, so an idle tick with nobody else editing costs a tiny
            // request instead of fetching and decoding the whole document every 4 seconds.
            guard let remoteUpdatedAt = try await store.loadDrawingUpdatedAt(id: document.id),
                  remoteUpdatedAt != remoteSyncLastKnownUpdatedAt else { return }
            remoteSyncLastKnownUpdatedAt = remoteUpdatedAt
            guard let remote = try await store.loadDrawing(id: document.id) else { return }
            let decoded = try JSONDecoder().decode(SchematicDocument.self, from: remote.data)
            guard decoded != document else { return }
            isApplyingRemoteDocument = true
            document = decoded
            DispatchQueue.main.async {
                self.isApplyingRemoteDocument = false
            }
        } catch {
            recordError("Remote sync pull failed: \(cloudErrorText(error))")
        }
    }

    private func applyRemoteDocument(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(SchematicDocument.self, from: data) else { return }
        isApplyingRemoteDocument = true
        document = decoded
        DispatchQueue.main.async {
            self.isApplyingRemoteDocument = false
        }
    }

    private func saveToCloud() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            let data = try JSONEncoder().encode(document)
            try await store.saveDrawing(id: document.id, name: document.name, data: data, createdByName: document.createdByName, updatedByName: currentDisplayName)
            cloudStatus = "Saved to cloud"
        } catch {
            recordError("Cloud save failed: \(cloudErrorText(error))")
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
            recordError("Cloud list failed: \(cloudErrorText(error))")
        }
    }

    private func loadCloudDrawing(_ drawing: CloudDrawingChoice) {
        do {
            document = try JSONDecoder().decode(SchematicDocument.self, from: drawing.data)
            autoZoomAfterLoad()
            showCloudLibrary = false
            cloudStatus = "Loaded from cloud: \(drawing.name)"
        } catch {
            cloudStatus = "Cloud drawing invalid: \(error.localizedDescription)"
        }
    }

    private func autoZoomAfterLoad() {
        DispatchQueue.main.async {
            zoomToExtents()
        }
    }

    /// Replaces any invalid/unknown SF Symbol name (e.g. a stale value synced from an old Supabase seed) with the target kind's default symbol.
    private func sanitizeTargetDefinitionSymbols() {
        for index in document.targetDefinitions.indices {
            let symbol = document.targetDefinitions[index].symbol
            if UIImage(systemName: symbol) == nil {
                document.targetDefinitions[index].symbol = document.targetDefinitions[index].kind.symbol
            }
        }
        for index in document.targets.indices {
            let symbol = document.targets[index].symbol
            if UIImage(systemName: symbol) == nil {
                document.targets[index].symbol = document.targets[index].kind.symbol
            }
        }
    }

    private func syncLibraries() async {
        guard let store = SupabaseDrawingStore() else {
            cloudStatus = "Supabase is not configured"
            return
        }
        do {
            let targetTypes = try await store.loadTargetTypes()
            let wireDefinitions = try await store.loadWireDefinitions()
            let syncedTargets = targetTypes.compactMap { record -> TargetDefinition? in
                guard let kind = TargetKind(rawValue: record.kind) else { return nil }
                let validSymbol = record.symbol.flatMap { UIImage(systemName: $0) != nil ? $0 : nil } ?? kind.symbol
                return TargetDefinition(kind: kind, name: record.name, maxConnections: record.maxConnections ?? 2, colorHex: record.colorHex, symbol: validSymbol, imageData: nil, connectionAngles: record.connectionAngles, scale: 1)
            }
            if !syncedTargets.isEmpty { document.targetDefinitions = syncedTargets }
            if !wireDefinitions.isEmpty {
                let existingByName = Dictionary(uniqueKeysWithValues: document.lineDefinitions.map { ($0.name, $0) })
                document.lineDefinitions = wireDefinitions.map { record in
                    let existing = existingByName[record.name]
                    return LineDefinition(
                        id: existing?.id ?? record.id,
                        name: record.name,
                        colorHex: existing?.colorHex ?? "31D7E8",
                        wireSize: record.wireSize,
                        wireType: record.wireType,
                        material: ConductorMaterial(rawValue: record.material) ?? .copper,
                        misc: record.misc,
                        displayWidth: existing?.displayWidth ?? 3,
                        description: record.description
                    )
                }
            }
            cloudStatus = "Shared libraries synced"
        } catch {
            recordError("Library sync failed: \(cloudErrorText(error))")
        }
    }

    private func loadWireLibrary() async {
        guard let store = SupabaseDrawingStore() else { return }
        do {
            wireLibraryEntries = try await store.loadWireLibrary()
            wireSizeOptions = try await store.loadWireSizes()
            wireTypeOptions = try await store.loadWireTypes()
            wireMiscOptions = try await store.loadWireMiscOptions()
        } catch {
            recordError("Failed to load wire library: \(error.localizedDescription)")
        }
    }

    private func createWireLibraryEntry() async {
        guard let store = SupabaseDrawingStore(),
              let sizeID = newWireLibrarySizeID,
              let typeID = newWireLibraryTypeID,
              let miscID = newWireLibraryMiscID else { return }
        do {
            let newEntry = try await store.createWireLibraryEntry(
                sizeID: sizeID,
                typeID: typeID,
                miscID: miscID,
                description: newWireLibraryDescription,
                displaySize: newWireLibraryDisplaySize,
                colorHex: newWireLibraryColorHex
            )
            wireLibraryEntries.append(newEntry)
            newWireLibrarySizeID = nil
            newWireLibraryTypeID = nil
            newWireLibraryMiscID = nil
            newWireLibraryDescription = ""
            newWireLibraryDisplaySize = 2.0
            newWireLibraryColorHex = "31D7E8"
            showWireLibraryPanel = false
            cloudStatus = "Wire library entry created"
        } catch {
            recordError("Failed to create wire library entry: \(error.localizedDescription)")
        }
    }

    private func cloudErrorText(_ error: Error) -> String {
        if case let SupabaseDrawingStore.StoreError.requestFailed(code, body) = error {
            return "HTTP \(code) \(body.prefix(120))"
        }
        return error.localizedDescription
    }

    private func recordError(_ message: String) {
        cloudStatus = message
        errorLog.append(LocalErrorEntry(date: Date(), message: message))
        if errorLog.count > 100 { errorLog.removeFirst(errorLog.count - 100) }
        LocalErrorLog.save(errorLog)
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
        autoZoomAfterLoad()
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

    private var versionHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VERSION HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { showVersionHistory = false } label: {
                    Image(systemName: "xmark")
                }
                .foregroundStyle(.white.opacity(0.65))
            }
            Button { promptForVersion() } label: {
                Label("Save current version", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            if document.versionHistory.isEmpty {
                Text("No saved versions yet.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(document.versionHistory) { version in
                            Button { recallVersion(version) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(version.description)
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(version.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                    Text(version.userName.isEmpty ? "Unknown user" : version.userName)
                                        .font(.caption2)
                                        .foregroundStyle(.cyan.opacity(0.75))
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var profilePickerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your display name")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("This is the name others will see during shared editing.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
            ForEach(profileNames, id: \.self) { name in
                Button(name) { selectProfileName(name) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            TextField("Display name", text: $profileNameDraft)
                .textFieldStyle(.roundedBorder)
            Button("Continue") { createAndSelectProfile() }
                .buttonStyle(.borderedProminent)
                .disabled(profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .task { await loadProfiles() }
    }

    private func selectProfileName(_ name: String) {
        currentDisplayName = name
        showProfilePicker = false
    }

    private func loadProfiles() async {
        guard let store = SupabaseDrawingStore() else { return }
        profileNames = (try? await store.loadProfiles().map(\.displayName)) ?? []
    }

    private func createAndSelectProfile() {
        let name = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        currentDisplayName = name
        profileNames.append(name)
        showProfilePicker = false
        Task {
            guard let store = SupabaseDrawingStore() else { return }
            _ = try? await store.createProfile(name: name)
        }
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
                Button { beginNewLineDefinition() } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
                Button { showLineLibrary = false } label: { Image(systemName: "xmark") }.foregroundStyle(.white.opacity(0.65))
            }
            TextField("Search material or wire size", text: $lineLibrarySearch)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(document.lineDefinitions.filter {
                        lineLibrarySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(lineLibrarySearch) || $0.wireSize.localizedCaseInsensitiveContains(lineLibrarySearch) || $0.wireType.localizedCaseInsensitiveContains(lineLibrarySearch)
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { line in
                                HStack(spacing: 8) {
                                    Button {
                                        selectedLineDefinitionID = line.id
                                        if selectedSegmentIDs.count > 1 {
                                            applyLineDefinition(line, to: selectedSegmentIDs)
                                        } else if let selectedSegmentID {
                                            applyLineDefinition(line, to: selectedSegmentID)
                                        }
                                        showLineLibrary = false
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(line.name).font(.system(size: 12, weight: .semibold))
                                            Text("\(line.wireSize) · \(line.wireType)").font(.caption2).foregroundStyle(.white.opacity(0.4))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    Button { beginEditLineDefinition(line) } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.cyan)
                                }
                                .padding(.horizontal, 8)
                                .frame(minHeight: 42)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .padding(12)
        .frame(width: 320, height: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var wireLegendPanel: some View {
        var entries = document.colorLegend
        for segment in document.segments where !entries.contains(where: { $0.colorHex.caseInsensitiveCompare(segment.colorHex) == .orderedSame }) {
            entries.append(ColorLegendEntry(colorHex: segment.colorHex, meaning: ""))
        }
        entries.sort { $0.meaning.localizedCaseInsensitiveCompare($1.meaning) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WIRE LEGEND").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { showWireLegend = false } label: { Image(systemName: "xmark") }.foregroundStyle(.white.opacity(0.65))
            }
            if entries.isEmpty {
                Text("Add a color meaning to a wire definition to see it here.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: entry.colorHex)).frame(width: 16, height: 16)
                        Text(entry.meaning.isEmpty ? "EMPTY" : entry.meaning).font(.caption.weight(.semibold))
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var visualizationsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VISUALIZATIONS").inspectorLabel()
            Toggle("Wire bridges", isOn: $wireBridgesEnabled).toggleStyle(.switch)
            Toggle("Connection names", isOn: $showConnectionNames).toggleStyle(.switch)
            Toggle("Wire color legend", isOn: $showWireLegend).toggleStyle(.switch)
            Toggle("Hide edit box", isOn: Binding(
                get: { !showEditBoxOnSelection },
                set: { showEditBoxOnSelection = !$0 }
            )).toggleStyle(.switch)
            Button("Clear visualization settings") {
                wireBridgesEnabled = false
                showConnectionNames = false
                showWireLegend = false
                showEditBoxOnSelection = false
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 260)
    }

    private var labelsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LABELS").inspectorLabel()
            Toggle("Wire names", isOn: $showWireNames).toggleStyle(.switch)
            Toggle("Lengths", isOn: $showWireLengths).toggleStyle(.switch)
            Toggle("Wire sizes", isOn: $showWireSizes).toggleStyle(.switch)
            Toggle("Materials", isOn: $showWireMaterials).toggleStyle(.switch)
            Toggle("Coverings", isOn: $showWireCoverings).toggleStyle(.switch)
            Toggle("Net names", isOn: $showWireNetNames).toggleStyle(.switch)
            Button("Clear label settings") {
                showWireNames = false
                showWireLengths = false
                showWireSizes = false
                showWireMaterials = false
                showWireCoverings = false
                showWireNetNames = false
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 260)
    }

    private var colorLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COLOR LEGEND").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { beginNewColorLegendEntry() } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
                Button { showColorLibrary = false } label: { Image(systemName: "xmark") }.foregroundStyle(.white.opacity(0.65))
            }
            ForEach(document.colorLegend) { entry in
                HStack {
                    Circle().fill(Color(hex: entry.colorHex)).frame(width: 18, height: 18)
                    Text(entry.meaning).font(.caption.weight(.semibold))
                    Spacer()
                    Button { beginEditColorLegendEntry(entry) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                }
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            if document.colorLegend.isEmpty { Text("No color meanings yet.").font(.caption).foregroundStyle(.white.opacity(0.5)) }
        }
        .padding(12)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showColorLegendEditor) { colorLegendEditor }
    }

    private var colorLegendEditor: some View {
        NavigationStack {
            Form {
                ColorPicker("Color", selection: Binding(get: { Color(hex: colorLegendHexDraft) }, set: { colorLegendHexDraft = $0.hexString }))
                TextField("Meaning (for example, 120 V)", text: $colorLegendMeaningDraft)
            }
            .navigationTitle(editingColorLegendID == nil ? "New Color Meaning" : "Edit Color Meaning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showColorLegendEditor = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveColorLegendEntry() }.disabled(colorLegendMeaningDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
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

    private var lineDefinitionEditor: some View {
        NavigationStack {
            Form {
                Section("Wire") {
                    TextField("Name", text: $lineDefinitionNameDraft)
                    if lineDefinitionUsesCustomSize {
                        HStack {
                            TextField("New size", text: $lineDefinitionSizeDraft)
                            Button("Use saved") { lineDefinitionUsesCustomSize = false }
                        }
                    } else {
                        Picker("Size", selection: $lineDefinitionSizeDraft) {
                            ForEach(lineDefinitionSizeOptions, id: \.self) { Text($0).tag($0) }
                            Text("Add new…").tag("__new_size__")
                        }
                        .onChange(of: lineDefinitionSizeDraft) { _, value in
                            if value == "__new_size__" {
                                lineDefinitionSizeDraft = ""
                                lineDefinitionUsesCustomSize = true
                            }
                        }
                    }
                    if lineDefinitionUsesCustomType {
                        HStack {
                            TextField("New type", text: $lineDefinitionTypeDraft)
                            Button("Use saved") { lineDefinitionUsesCustomType = false }
                        }
                    } else {
                        Picker("Type", selection: $lineDefinitionTypeDraft) {
                            ForEach(lineDefinitionTypeOptions, id: \.self) { Text($0).tag($0) }
                            Text("Add new…").tag("__new_type__")
                        }
                        .onChange(of: lineDefinitionTypeDraft) { _, value in
                            if value == "__new_type__" {
                                lineDefinitionTypeDraft = ""
                                lineDefinitionUsesCustomType = true
                            }
                        }
                    }
                    TextField("Construction / use", text: $lineDefinitionMiscDraft)
                    ColorPicker("Color", selection: Binding(
                        get: { Color(hex: lineDefinitionColorHexDraft) },
                        set: { lineDefinitionColorHexDraft = $0.hexString }
                    ))
                    TextField("Description", text: $lineDefinitionDescriptionDraft)
                }
            }
            .navigationTitle(editingLineDefinitionID == nil ? "New Wire" : "Edit Wire")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLineDefinitionEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLineDefinitionDraft() }
                        .disabled(lineDefinitionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var lineDefinitionSizeOptions: [String] {
        Array(Set(document.lineDefinitions.map(\.wireSize) + [lineDefinitionSizeDraft])).filter { !$0.isEmpty }.sorted()
    }

    private var lineDefinitionTypeOptions: [String] {
        Array(Set(document.lineDefinitions.map(\.wireType) + [lineDefinitionTypeDraft])).filter { !$0.isEmpty }.sorted()
    }

    private var netlistText: String {
        let netNames = generatedNetNames
        return document.targets.map { target in
            let pins = (0..<target.maxConnections).map { slot in
                let pinName = target.connectionNames.indices.contains(slot) ? target.connectionNames[slot] : defaultConnectionName(for: slot)
                let identifier = target.identifier.isEmpty ? target.name : target.identifier
                let netName = netNames[NetEndpoint(targetID: target.id, slot: slot)] ?? "NC"
                return "\(identifier).\(pinName)=\(netName)"
            }.joined(separator: " ")
            return "\(target.identifier.isEmpty ? target.name : target.identifier) \(pins)"
        }.joined(separator: "\n")
    }

    private var generatedNetNames: [NetEndpoint: String] {
        var adjacency: [NetEndpoint: Set<NetEndpoint>] = [:]
        func connect(_ first: NetEndpoint, _ second: NetEndpoint) {
            adjacency[first, default: []].insert(second)
            adjacency[second, default: []].insert(first)
        }

        for segment in document.segments {
            guard let startSlot = segment.startSlot, let endSlot = segment.endSlot else { continue }
            connect(NetEndpoint(targetID: segment.startID, slot: startSlot), NetEndpoint(targetID: segment.endID, slot: endSlot))
        }

        for target in document.targets where target.kind == .junction {
            let endpoints = (0..<target.maxConnections).map { NetEndpoint(targetID: target.id, slot: $0) }
            for endpoint in endpoints.dropFirst() {
                connect(endpoints[0], endpoint)
            }
        }

        var names: [NetEndpoint: String] = [:]
        var visited = Set<NetEndpoint>()
        var nextNumber = 1
        let endpoints = adjacency.keys.sorted { ($0.targetID.uuidString, $0.slot) < ($1.targetID.uuidString, $1.slot) }
        for endpoint in endpoints where !visited.contains(endpoint) {
            let name = String(format: "N%03d", nextNumber)
            nextNumber += 1
            var queue = [endpoint]
            visited.insert(endpoint)
            while let current = queue.popLast() {
                names[current] = name
                for neighbor in adjacency[current, default: []] where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }
        return names
    }

    private func netName(for segment: SchematicSegment) -> String {
        guard let startSlot = segment.startSlot else { return "NC" }
        return generatedNetNames[NetEndpoint(targetID: segment.startID, slot: startSlot)] ?? "NC"
    }

    private var deleteWarningTitle: String {
        if !selectedTargetIDs.isEmpty {
            return selectedTargetIDs.count == 1 ? "Delete selected item?" : "Delete selected items?"
        }
        return selectedSegmentIDs.count == 1 ? "Delete selected wire?" : "Delete selected wires?"
    }

    private func deleteSelectedContent() {
        captureForUndo()
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
                Text("ITEM LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { addTarget(.junction) } label: { Image(systemName: "plus") }.foregroundStyle(.cyan)
            }

            Text("PROJECT ITEMS").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.35))
            ForEach(document.targets) { target in
                Button {
                    selectedTargetIDs = [target.id]
                    selectedSegmentID = nil
                    selectedSegmentIDs.removeAll()
                    showTargetLibrary = false
                } label: {
                    HStack(spacing: 8) {
                        SchematicSymbolView(kind: target.kind, color: Color(hex: target.colorHex)).frame(width: 16, height: 16)
                        Text(target.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(connectionCount(for: target.id)) / \(target.kind == .junction ? "∞" : "\(target.maxConnections)")")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(.white.opacity(0.12))
            Text("SAVED ITEM TYPES").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.35))
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

    private var wireLibraryCreationSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Create Wire Library Entry").font(.headline)
                
                // Size Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Size").font(.caption.weight(.semibold))
                    Picker("", selection: $newWireLibrarySizeID) {
                        Text("Select size").tag(nil as Int?)
                        ForEach(wireSizeOptions) { size in
                            Text(size.sizeValue).tag(size.id as Int?)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Type Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type").font(.caption.weight(.semibold))
                    Picker("", selection: $newWireLibraryTypeID) {
                        Text("Select type").tag(nil as Int?)
                        ForEach(wireTypeOptions) { type in
                            Text(type.typeName).tag(type.id as Int?)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Misc Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Misc").font(.caption.weight(.semibold))
                    Picker("", selection: $newWireLibraryMiscID) {
                        Text("Select misc").tag(nil as Int?)
                        ForEach(wireMiscOptions) { misc in
                            Text(misc.miscValue).tag(misc.id as Int?)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Display Size Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Display Size").font(.caption.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f", newWireLibraryDisplaySize)).font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: $newWireLibraryDisplaySize, in: 0.5...10.0, step: 0.5)
                }
                
                // Color Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color").font(.caption.weight(.semibold))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: newWireLibraryColorHex) ?? .cyan)
                            .frame(width: 32, height: 32)
                        
                        TextField("Hex color (e.g., 31D7E8)", text: $newWireLibraryColorHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .autocapitalization(.allCharacters)
                    }
                }
                
                // Description TextField
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption.weight(.semibold))
                    TextField("Optional description", text: $newWireLibraryDescription)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                
                // Create Button
                HStack(spacing: 12) {
                    Button(action: {
                        newWireLibrarySizeID = nil
                        newWireLibraryTypeID = nil
                        newWireLibraryMiscID = nil
                        newWireLibraryDescription = ""
                        newWireLibraryDisplaySize = 2.0
                        newWireLibraryColorHex = "31D7E8"
                        showWireLibraryPanel = false
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        Task {
                            await createWireLibraryEntry()
                        }
                    }) {
                        Text("Create")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(newWireLibrarySizeID == nil || newWireLibraryTypeID == nil || newWireLibraryMiscID == nil)
                }
            }
            .padding()
        }
    }
    
    private var backgroundImagePanel: some View {
        VStack(spacing: 8) {
            if backgroundImage != nil {
                HStack(spacing: 12) {
                    Text("BACKGROUND").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                    
                    HStack(spacing: 4) {
                        Text("W").font(.caption2).foregroundStyle(.white.opacity(0.65))
                        Slider(value: $backgroundImageSize.width, in: 50...2000)
                            .onChange(of: backgroundImageSize.width) { _, newWidth in
                                if backgroundImageConstrainProportions, let bgImage = backgroundImage {
                                    let aspectRatio = bgImage.size.height / bgImage.size.width
                                    backgroundImageSize.height = newWidth * aspectRatio
                                }
                                saveBackgroundImageState()
                            }
                            .frame(maxWidth: 80)
                        Text("\(Int(backgroundImageSize.width))").font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.65)).frame(width: 35)
                    }
                    
                    HStack(spacing: 4) {
                        Text("H").font(.caption2).foregroundStyle(.white.opacity(0.65))
                        Slider(value: $backgroundImageSize.height, in: 50...2000)
                            .onChange(of: backgroundImageSize.height) { _, newHeight in
                                if backgroundImageConstrainProportions, let bgImage = backgroundImage {
                                    let aspectRatio = bgImage.size.width / bgImage.size.height
                                    backgroundImageSize.width = newHeight * aspectRatio
                                }
                                saveBackgroundImageState()
                            }
                            .frame(maxWidth: 80)
                        Text("\(Int(backgroundImageSize.height))").font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.65)).frame(width: 35)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").font(.caption2)
                        Slider(value: $backgroundImageOpacity, in: 0...1)
                            .onChange(of: backgroundImageOpacity) { _, _ in saveBackgroundImageState() }
                            .frame(maxWidth: 60)
                    }
                    
                    Toggle("", isOn: $backgroundImageConstrainProportions)
                        .onChange(of: backgroundImageConstrainProportions) { _, _ in saveBackgroundImageState() }
                        .scaleEffect(0.8, anchor: .center)
                    
                    Toggle("", isOn: $backgroundImageLocked)
                        .onChange(of: backgroundImageLocked) { _, _ in saveBackgroundImageState() }
                        .scaleEffect(0.8, anchor: .center)
                    
                    Button(role: .destructive) {
                        clearBackgroundImage()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .font(.caption)
                    
                    Button { showBackgroundImagePanel = false } label: {
                        Image(systemName: "xmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 12) {
                    Text("BACKGROUND").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
                    
                    PhotosPicker(selection: $backgroundImagePhotoItem, matching: .images) {
                        Label("Add image", systemImage: "photo.stack")
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button { showBackgroundImagePanel = false } label: {
                        Image(systemName: "xmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func targetBottomPanel(_ target: SchematicTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("COMPONENT ID").inspectorLabel()
                TextField("ID", text: $targetIdentifierDraft).textFieldStyle(.roundedBorder).frame(width: 160)
                Button("Save") { saveTargetIdentifier(target) }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { cancelTargetIdentifier(target) }
                    .buttonStyle(.bordered)
                Spacer()
                if target.kind != .junction {
                    ColorPicker("Item color", selection: targetBinding(target).color).labelsHidden()
                    Text("CUSTOM").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).padding(.trailing, 12)
                    ForEach(document.colorLegend) { entry in
                        Button {
                            targetBinding(target).color.wrappedValue = Color(hex: entry.colorHex)
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: entry.colorHex)).frame(width: 18, height: 18)
                                Text(entry.meaning.isEmpty ? "EMPTY" : entry.meaning).font(.caption2)
                            }
                            .padding(3)
                            .background(Color(hex: target.colorHex).hexString.caseInsensitiveCompare(entry.colorHex) == .orderedSame ? Color.white.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help(entry.meaning.isEmpty ? "Use custom legend color" : entry.meaning)
                    }
                }
                Button(role: .destructive) {
                    showDeleteWarning = true
                } label: {
                    Label("Delete item", systemImage: "trash")
                }
            }

            HStack(spacing: 16) {
                Button {
                    captureForUndo()
                    rotateTarget(target, by: 90)
                } label: {
                    Label("Rotate 90°", systemImage: "rotate.right")
                }
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
                    Label("Use SF Symbol instead", systemImage: "square.grid.2x2")
                }
                .disabled(target.imageData == nil)
                Button { duplicateTarget(target) } label: {
                    Label("Duplicate item", systemImage: "plus.square.on.square")
                }
                Button { saveTargetTemplate(target) } label: {
                    Label("Save as item type", systemImage: "square.and.arrow.down")
                }
            }

            if target.kind == .junction {
                Text("Connections: Unlimited")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                HStack(spacing: 20) {
                    Stepper("Connections: \(target.maxConnections)", value: targetBinding(target).maxConnections, in: 0...32)
                    Stepper("Point rotation: \(target.connectionAngle, specifier: "%.0f")°", value: targetBinding(target).connectionAngle, in: 0...360, step: 15)
                    Stepper("Size: \(target.scale, specifier: "%.1f")x", value: targetBinding(target).scale, in: 0.5...3, step: 0.1)
                    Toggle("Compact item", isOn: targetBinding(target).isCompact)
                }
            }

            if target.maxConnections > 0 {
                Text("PIN NAMES").inspectorLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<target.maxConnections, id: \.self) { slot in
                            HStack(spacing: 4) {
                                Text("Pin \(slot + 1)").font(.caption)
                                TextField("A, B, GND...", text: connectionNameBinding(target, slot: slot))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectionBoxSize: CGSize {
        if selectedTargetIDs.isEmpty && selectedSegmentIDs.isEmpty {
            return CGSize(width: 132, height: 44)
        }
        if selectedTargetIDs.isEmpty && selectedSegmentIDs.count == 1 {
            return CGSize(width: 360, height: 44)
        }
        let actionCount: Int
        if !selectedTargetIDs.isEmpty {
            actionCount = selectedTargetIDs.count == 1 ? (selectedTargetIDs.first.flatMap { target(with: $0) }.map { canRemoveTargetFromWire($0) && $0.kind != .junction } == true ? 7 : 6) : 7
        } else {
            actionCount = selectedSegmentIDs.count == 1 ? 5 : 1
        }
        let buttonWidth: CGFloat = 40
        let countWidth: CGFloat = 16
        let spacing = CGFloat(actionCount) * 8
        let horizontalPadding: CGFloat = 24
        return CGSize(width: countWidth + CGFloat(actionCount) * buttonWidth + spacing + horizontalPadding, height: 44)
    }

    private var selectionBox: some View {
        HStack(spacing: 8) {
            Text(selectedTargetIDs.isEmpty && selectedSegmentIDs.isEmpty ? "NOTHING\nSELECTED" : "\(selectedTargetIDs.isEmpty ? selectedSegmentIDs.count : selectedTargetIDs.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(width: selectedTargetIDs.isEmpty && selectedSegmentIDs.isEmpty ? 108 : 16)
                .accessibilityLabel(selectedTargetIDs.isEmpty && selectedSegmentIDs.isEmpty ? "Nothing selected" : "\(selectedTargetIDs.isEmpty ? selectedSegmentIDs.count : selectedTargetIDs.count) selected")
            if !selectedTargetIDs.isEmpty {
                Button { connectSelectedTargets() } label: { Image(systemName: "link") }
                    .buttonStyle(EditorButtonStyle())
                    .disabled(selectedTargetIDs.count < 2)
                    .opacity(selectedTargetIDs.count < 2 ? 0.4 : 1)
                    .help("Connect selected items")
                    .accessibilityLabel("Connect selected items")
            }
            if selectedTargetIDs.isEmpty, selectedSegmentIDs.count == 1, selectedSegment != nil {
                Button { wirePlacementMode = .connection } label: { Image(systemName: "circle.fill") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Add connection at clicked point")
                    .accessibilityLabel("Add connection at clicked point")
                Button { wirePlacementMode = .bend } label: { Image(systemName: "point.topleft.down.curvedto.point.bottomright.up") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Add bend point at clicked point")
                    .accessibilityLabel("Add bend point at clicked point")
                Button {
                    wireConnectionMoveMode.toggle()
                    wirePinMoveTargetID = nil
                    selectedConnectionSlots.removeAll()
                } label: {
                    Label("Move connection", systemImage: "arrow.uturn.right.circle")
                }
                .buttonStyle(EditorButtonStyle(isActive: wireConnectionMoveMode))
                .help(wireConnectionMoveMode ? "Cancel moving connection" : "Move wire connection")
                .accessibilityLabel(wireConnectionMoveMode ? "Cancel moving connection" : "Move wire connection")
            }
            if selectedTargetIDs.count > 1 {
                Button { alignSelectedTargets(.horizontal) } label: {
                    Image(systemName: "align.horizontal.center")
                }
                .buttonStyle(EditorButtonStyle())
                .help("Align selected items horizontally")
                .accessibilityLabel("Align selected items horizontally")
                Button { alignSelectedTargets(.vertical) } label: {
                    Image(systemName: "align.vertical.center")
                }
                .buttonStyle(EditorButtonStyle())
                .help("Align selected items vertically")
                .accessibilityLabel("Align selected items vertically")
                Button { distributeSelectedTargets(.horizontal) } label: {
                    Image(systemName: "arrow.left.and.right")
                }
                .buttonStyle(EditorButtonStyle())
                .disabled(selectedTargetIDs.count < 3)
                .opacity(selectedTargetIDs.count < 3 ? 0.4 : 1)
                .help("Distribute selected items horizontally")
                .accessibilityLabel("Distribute selected items horizontally")
                Button { distributeSelectedTargets(.vertical) } label: {
                    Image(systemName: "arrow.up.and.down")
                }
                .buttonStyle(EditorButtonStyle())
                .disabled(selectedTargetIDs.count < 3)
                .opacity(selectedTargetIDs.count < 3 ? 0.4 : 1)
                .help("Distribute selected items vertically")
                .accessibilityLabel("Distribute selected items vertically")
                Button { toggleSelectedTargetLocks() } label: {
                    Image(systemName: selectedTargetsAreLocked ? "lock.open" : "lock")
                }
                    .buttonStyle(EditorButtonStyle(isActive: selectedTargetsAreLocked))
                    .help(selectedTargetsAreLocked ? "Unlock selected items" : "Lock selected items")
                    .accessibilityLabel(selectedTargetsAreLocked ? "Unlock selected items" : "Lock selected items")
            }
            if selectedTargetIDs.count == 1, let targetID = selectedTargetIDs.first, let target = target(with: targetID) {
                if canRemoveTargetFromWire(target) && target.kind != .junction {
                    Button { removeTargetFromWire(target) } label: { Image(systemName: "arrow.uturn.right.circle") }
                        .buttonStyle(EditorButtonStyle())
                        .help("Disconnect item from wire and join the wire")
                        .accessibilityLabel("Disconnect item from wire")
                }
                Button { captureForUndo(); rotateTarget(target, by: -90) } label: { Image(systemName: "rotate.left") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Rotate selected item counter-clockwise")
                    .accessibilityLabel("Rotate selected item counter-clockwise")
                Button { captureForUndo(); rotateTarget(target, by: 90) } label: { Image(systemName: "rotate.right") }
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
            if !selectedTargetIDs.isEmpty || !selectedSegmentIDs.isEmpty {
                Button(role: .destructive) {
                    showDeleteWarning = true
                } label: { Image(systemName: "trash") }
                    .buttonStyle(EditorButtonStyle())
                    .help("Delete selected items")
                    .accessibilityLabel("Delete selected items")
            }
        }
        .padding(6)
        .frame(width: selectionBoxSize.width, height: selectionBoxSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1) }
        .overlay(alignment: .bottom) {
            if let wirePlacementMode {
                Text(wirePlacementMode == .connection ? "Click a point to add Junction" : "Click a point to add Bend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.78), in: Capsule())
                    .offset(y: 34)
                    .allowsHitTesting(false)
            }
        }
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
        let viewportCenter = CGPoint(x: editorSize.width / 2, y: editorSize.height / 2)
        let canvasCenter = CGPoint(x: canvasFieldSize / 2, y: canvasFieldSize / 2)
        let scaled = CGPoint(x: (point.x - canvasCenter.x) * canvasScale, y: (point.y - canvasCenter.y) * canvasScale)
        let angle = canvasRotation.radians
        let rotated = CGPoint(
            x: scaled.x * CGFloat(cos(angle)) - scaled.y * CGFloat(sin(angle)),
            y: scaled.x * CGFloat(sin(angle)) + scaled.y * CGFloat(cos(angle))
        )
        return CGPoint(x: rotated.x + viewportCenter.x + canvasOffset.width, y: rotated.y + viewportCenter.y + canvasOffset.height)
    }

    private var selectedSegment: SchematicSegment? { guard let selectedSegmentID else { return nil }; return document.segments.first { $0.id == selectedSegmentID } }
    private func segment(with id: UUID) -> SchematicSegment? { document.segments.first { $0.id == id } }

    private func resetToolbars() {
        itemsPanelOffsetX = 0
        itemsPanelOffsetY = 0
        zoomToolbarOffsetX = 0
        zoomToolbarOffsetY = 2
        targetToolbarOffsetX = 0
        targetToolbarOffsetY = 0

        let selectionWidth = selectionBoxSize.width
        let rightOverlayInset: CGFloat = 24
        let toolbarSpacing: CGFloat = 8
        selectionToolbarOffsetX = editorSize.width / 2
            - (editorSize.width - rightOverlayInset - zoomToolbarWidth - toolbarSpacing - selectionWidth / 2)
        selectionToolbarOffsetY = 0
    }

    private var itemsPanelDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if itemsPanelDragStartOffset == nil {
                    itemsPanelDragStartOffset = CGSize(width: itemsPanelOffsetX, height: itemsPanelOffsetY)
                }
                let start = itemsPanelDragStartOffset ?? .zero
                let proposed = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                itemsPanelOffsetX = proposed.width
                itemsPanelOffsetY = clampedItemsPanelOffset(proposed).height
            }
            .onEnded { value in
                let start = itemsPanelDragStartOffset ?? .zero
                let proposed = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                let topOffset: CGFloat = 0
                let bottomOffset = max(0, editorSize.height - 90 - itemsPanelHeight - 20)
                let nearest = [topOffset, bottomOffset].min { abs(proposed.height - $0) < abs(proposed.height - $1) } ?? proposed.height
                let snappedHeight = abs(proposed.height - nearest) <= 48 ? nearest : proposed.height
                let snapped = clampedItemsPanelOffset(CGSize(width: proposed.width, height: snappedHeight))
                itemsPanelOffsetX = snapped.width
                itemsPanelOffsetY = snapped.height
                itemsPanelDragStartOffset = nil
            }
    }

    private func clampedItemsPanelOffset(_ proposed: CGSize) -> CGSize {
        let bottomOffset = max(0, editorSize.height - 90 - itemsPanelHeight - 20)
        return CGSize(width: proposed.width, height: min(max(proposed.height, 0), bottomOffset))
    }

    private func toolbarOffsetX(isTarget: Bool, isZoom: Bool) -> CGFloat {
        if isTarget { return targetToolbarOffsetX }
        return isZoom ? zoomToolbarOffsetX : selectionToolbarOffsetX
    }

    private func toolbarOffsetY(isTarget: Bool, isZoom: Bool) -> CGFloat {
        if isTarget { return targetToolbarOffsetY }
        return isZoom ? zoomToolbarOffsetY : selectionToolbarOffsetY
    }

    private func toolbarDragGesture(isTarget: Bool, isZoom: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if toolbarDragStartOffset == nil {
                    toolbarDragStartOffset = CGSize(
                        width: toolbarOffsetX(isTarget: isTarget, isZoom: isZoom),
                        height: toolbarOffsetY(isTarget: isTarget, isZoom: isZoom)
                    )
                }
                let start = toolbarDragStartOffset ?? .zero
                let proposed = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                let offset = clampedToolbarOffset(proposed, isTarget: isTarget, isZoom: isZoom)
                if isTarget {
                    targetToolbarOffsetX = offset.width
                    targetToolbarOffsetY = offset.height
                } else if isZoom {
                    zoomToolbarOffsetX = offset.width
                    zoomToolbarOffsetY = offset.height
                } else {
                    selectionToolbarOffsetX = offset.width
                    selectionToolbarOffsetY = offset.height
                }
            }
            .onEnded { value in
                let start = toolbarDragStartOffset ?? .zero
                let proposed = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                let snapped = snappedToolbarOffset(isTarget: isTarget, proposed: proposed, isZoom: isZoom)
                if isTarget {
                    targetToolbarOffsetX = snapped.width
                    targetToolbarOffsetY = snapped.height
                } else if isZoom {
                    zoomToolbarOffsetX = snapped.width
                    zoomToolbarOffsetY = snapped.height
                } else {
                    selectionToolbarOffsetX = snapped.width
                    selectionToolbarOffsetY = snapped.height
                }
                toolbarDragStartOffset = nil
            }
    }

    private func snappedToolbarOffset(isTarget: Bool, proposed: CGSize, isZoom: Bool) -> CGSize {
        let topOffset: CGFloat
        let bottomOffset: CGFloat
        if isTarget {
            topOffset = targetToolbarTopOffset
            bottomOffset = 0
        } else if isZoom {
            topOffset = 2
            bottomOffset = max(0, editorSize.height - 112 - 44)
        } else {
            topOffset = 0
            bottomOffset = max(0, editorSize.height - 112 - selectionBoxSize.height)
        }
        let snapDistance: CGFloat = 48
        let nearest = [topOffset, bottomOffset].min { abs(proposed.height - $0) < abs(proposed.height - $1) } ?? proposed.height
        let snappedHeight = abs(proposed.height - nearest) <= snapDistance ? nearest : proposed.height
        let snapped = CGSize(width: proposed.width, height: snappedHeight)
        return clampedToolbarOffset(snapped, isTarget: isTarget, isZoom: isZoom)
    }

    private func clampedToolbarOffset(_ proposed: CGSize, isTarget: Bool, isZoom: Bool) -> CGSize {
        let topOffset: CGFloat
        let bottomOffset: CGFloat
        if isTarget {
            topOffset = targetToolbarTopOffset
            bottomOffset = 0
        } else {
            let toolbarHeight = isZoom ? CGFloat(44) : selectionBoxSize.height
            topOffset = isZoom ? 2 : 0
            bottomOffset = max(0, editorSize.height - 112 - toolbarHeight)
        }
        return CGSize(
            width: proposed.width,
            height: min(max(proposed.height, topOffset), bottomOffset)
        )
    }

    private let toolbarTopSafeInset: CGFloat = 120

    private var targetToolbarTopOffset: CGFloat {
        targetToolbarHeight + toolbarTopSafeInset + 6 - editorSize.height
    }

    private func recoverToolbarOffsetsIfNeeded() {
        guard editorSize.height > 0 else { return }
        targetToolbarOffsetY = clampedToolbarOffset(
            CGSize(width: targetToolbarOffsetX, height: targetToolbarOffsetY),
            isTarget: true,
            isZoom: false
        ).height
        selectionToolbarOffsetY = clampedToolbarOffset(
            CGSize(width: selectionToolbarOffsetX, height: selectionToolbarOffsetY),
            isTarget: false,
            isZoom: false
        ).height
        zoomToolbarOffsetY = clampedToolbarOffset(
            CGSize(width: zoomToolbarOffsetX, height: zoomToolbarOffsetY),
            isTarget: false,
            isZoom: true
        ).height
    }

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
                Text("WIRE").inspectorLabel()
            }
            TextField("Wire name", text: binding.name).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Size", text: binding.size).textFieldStyle(.roundedBorder)
                TextField("Type", text: binding.type).textFieldStyle(.roundedBorder)
            }
            TextField("Misc", text: binding.misc).textFieldStyle(.roundedBorder)
            TextField("Net name", text: binding.netName).textFieldStyle(.roundedBorder)
            Stepper("Display size: \(wire.displayWidth, specifier: "%.1f") pt", value: binding.displayWidth, in: 1...20, step: 0.5)
        }
        .padding(10)
        .background(.white.opacity(compact ? 0.05 : 0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private func wireBottomPanel(_ wire: SchematicSegment) -> some View {
        let displayWidthBinding = Binding<Double>(
            get: { segment(with: wire.id)?.displayWidth ?? wire.displayWidth },
            set: { value in
                guard let index = document.segments.firstIndex(where: { $0.id == wire.id }) else { return }
                document.segments[index].displayWidth = value
            }
        )
        let colorBinding = Binding<Color>(
            get: { segment(with: wire.id)?.color ?? wire.color },
            set: { value in
                guard let index = document.segments.firstIndex(where: { $0.id == wire.id }) else { return }
                document.segments[index].colorHex = value.hexString
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(selectedSegmentIDs.count > 1 ? "LAST SELECTED\nWIRE" : "SELECTED\nWIRE")
                    .inspectorLabel()
                    .multilineTextAlignment(.leading)
                    .frame(width: 112, alignment: .leading)
                readOnlyWireField("NAME", wire.name).frame(width: 130, alignment: .leading)
                readOnlyWireField("SIZE", wire.size).frame(width: 55, alignment: .leading)
                readOnlyWireField("TYPE", wire.type).frame(width: 90, alignment: .leading)
                readOnlyWireField("MISC", wire.misc).frame(width: 200, alignment: .leading)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button { selectSimilarWires(to: wire) } label: {
                        Label("Similar Wires", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Similar Wires")
                    Button { selectWiresWithSameColor(as: wire) } label: {
                        Label("Same Colors", systemImage: "paintpalette")
                    }
                    .buttonStyle(.bordered)
                    .help("Same Colors")
                    if selectedSegmentIDs.count > 1 {
                        Button("Copy Last To All") { copyLastWireToAll(wire) }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("ITEM\nCOLOR").inspectorLabel().multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ColorPicker("", selection: colorBinding)
                        .labelsHidden()
                        .help("Custom item color")
                    Text("CUSTOM").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).padding(.trailing, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(document.colorLegend) { entry in
                                Button {
                                    colorBinding.wrappedValue = Color(hex: entry.colorHex)
                                } label: {
                                    HStack(spacing: 3) {
                                        Circle().fill(Color(hex: entry.colorHex)).frame(width: 22, height: 22)
                                        Text(entry.meaning.isEmpty ? "EMPTY" : entry.meaning).font(.caption.weight(.semibold))
                                    }
                                    .padding(3)
                                    .background(wire.colorHex.caseInsensitiveCompare(entry.colorHex) == .orderedSame ? Color.white.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help(entry.meaning.isEmpty ? "Use custom item color" : entry.meaning)
                            }
                        }
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(wire.color)
                        .frame(width: 64, height: max(2, CGFloat(wire.displayWidth)))
                    Stepper("\(wire.displayWidth, specifier: "%.1f") pt", value: displayWidthBinding, in: 1...20, step: 0.5)
                        .labelsHidden()
                        .frame(width: 92)
                }
                Button { showLineLibrary = true } label: {
                    Label("Library", systemImage: "books.vertical")
                }
                .buttonStyle(.borderedProminent)
                .help("Open wire library")
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func readOnlyWireField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.55))
            Text(value.isEmpty ? "-" : value).font(.callout.weight(.semibold))
        }
    }

    private func selectSimilarWires(to wire: SchematicSegment) {
        let ids = document.segments.filter {
            $0.size == wire.size && $0.type == wire.type && $0.misc == wire.misc && $0.colorMeaning == wire.colorMeaning
        }.map(\.id)
        selectedSegmentIDs = Set(ids)
        selectedSegmentID = wire.id
        selectedTargetIDs.removeAll()
    }

    private func selectWiresWithSameColor(as wire: SchematicSegment) {
        let ids = document.segments.filter { $0.colorHex.caseInsensitiveCompare(wire.colorHex) == .orderedSame }.map(\.id)
        selectedSegmentIDs = Set(ids)
        selectedSegmentID = wire.id
        selectedTargetIDs.removeAll()
    }

    private func copyLastWireToAll(_ source: SchematicSegment) {
        for index in document.segments.indices where selectedSegmentIDs.contains(document.segments[index].id) {
            guard document.segments[index].id != source.id else { continue }
            document.segments[index].name = source.name
            document.segments[index].colorHex = source.colorHex
            document.segments[index].colorMeaning = source.colorMeaning
            document.segments[index].size = source.size
            document.segments[index].type = source.type
            document.segments[index].misc = source.misc
            document.segments[index].displayWidth = source.displayWidth
            document.segments[index].description = source.description
        }
    }
    
    private func smartWireID(_ wire: SchematicSegment) -> String {
        return "\(wire.size)_\(wire.type)_\(wire.misc)"
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
            let occupied = occupiedSlots(for: id)
            return (0..<target.maxConnections).first { !occupied.contains($0) }
        }
        let occupied = occupiedSlots(for: id)
        return (0..<target.maxConnections).first { !occupied.contains($0) }
    }

    private func closestAvailableSlot(for id: UUID, to otherID: UUID) -> Int? {
        guard let sourceTarget = target(with: id), let otherTarget = target(with: otherID) else { return nil }
        let occupied = occupiedSlots(for: id)
        let availableSlots = (0..<sourceTarget.maxConnections).filter { !occupied.contains($0) }
        guard sourceTarget.kind != .junction else {
            let desiredAngle = atan2(otherTarget.position.y - sourceTarget.position.y, otherTarget.position.x - sourceTarget.position.x) * 180 / Double.pi
            return availableSlots.min { lhs, rhs in
                let lhsDistance = angularDistance(connectionAngle(for: sourceTarget, slot: lhs), desiredAngle)
                let rhsDistance = angularDistance(connectionAngle(for: sourceTarget, slot: rhs), desiredAngle)
                return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
            }
        }
        return availableSlots
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
        if target.kind == .junction {
            let occupied = occupiedSlots(for: target.id).sorted()
            if occupied.count == 2, let firstSlot = occupied.first, let secondSlot = occupied.last {
                let firstAngle = junctionSlotAngle(slot: firstSlot, slotCount: 4)
                return slot == secondSlot ? firstAngle + 180 : firstAngle
            }
            let connectionCount = max(1, occupied.count)
            let slotCount = connectionCount > 4 ? 8 : 4
            return junctionSlotAngle(slot: slot, slotCount: slotCount)
        }
        return (360 * Double(slot) / Double(max(target.maxConnections, 1))) + target.connectionAngle - 90
    }

    private func junctionSlotAngle(slot: Int, slotCount: Int) -> Double {
        let directionIndex: [Int] = slotCount == 8 ? [0, 4, 2, 6, 1, 3, 5, 7] : [0, 2, 1, 3]
        return (360 * Double(directionIndex[min(slot, directionIndex.count - 1)]) / Double(slotCount)) - 90
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
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
        let previousPosition = document.targets[index].position
        document.targets[index].position = snappedPosition(document.targets[index].position)
        let delta = CGSize(width: document.targets[index].position.x - previousPosition.x, height: document.targets[index].position.y - previousPosition.y)
        guard abs(delta.width) > 0.01 || abs(delta.height) > 0.01 else { return }
        for segmentIndex in document.segments.indices where document.segments[segmentIndex].startID == id || document.segments[segmentIndex].endID == id {
            guard document.segments[segmentIndex].routePoints.count > 1 else { continue }
            if document.segments[segmentIndex].startID == id {
                document.segments[segmentIndex].routePoints[0].x += delta.width
                document.segments[segmentIndex].routePoints[0].y += delta.height
            } else {
                let last = document.segments[segmentIndex].routePoints.count - 1
                document.segments[segmentIndex].routePoints[last].x += delta.width
                document.segments[segmentIndex].routePoints[last].y += delta.height
            }
        }
    }

    private func captureAttachedRoutes(for targetID: UUID) {
        for segment in document.segments where segment.startID == targetID || segment.endID == targetID {
            guard let start = target(with: segment.startID), let end = target(with: segment.endID) else { continue }
            var points = orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
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
                // Keep the captured route for connections to stationary items; move only the selected endpoint.
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
                let adjacentIndex = pinIndex == 0 ? 1 : points.count - 2
                // Move the pin while keeping the trunk coordinate fixed so the endpoint stub
                // expands or contracts instead of dragging the whole trunk with the component.
                let sharesX = abs(points[adjacentIndex].x - points[pinIndex].x) < 0.5
                let sharesY = abs(points[adjacentIndex].y - points[pinIndex].y) < 0.5
                points[pinIndex].x += translation.width
                points[pinIndex].y += translation.height
                if sharesX { points[adjacentIndex].x = points[pinIndex].x }
                if sharesY { points[adjacentIndex].y = points[pinIndex].y }
            }
            document.segments[index].routePoints = normalizedRoute(points)
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
            captureForUndo()
            segmentDragStartPoints[id] = cachedWirePoints[id]
                ?? orthogonalPoints(for: document.segments[index], from: start, to: end, avoiding: [])
            let initialRoute = segmentDragStartPoints[id] ?? []
            wireLabelRouteAnchorPoints[id] = labelAnchor(for: document.segments[index], on: initialRoute).point
        }
        guard var points = segmentDragStartPoints[id], sectionIndex >= 0, sectionIndex + 1 < points.count else { return }
        let isEndpointStub = sectionIndex == 0 || sectionIndex + 1 == points.count - 1
        guard !isEndpointStub || points.count <= 3 || sectionIndex > 0 else { return }
        let isVertical = abs(points[sectionIndex].x - points[sectionIndex + 1].x) < 0.5
        if isVertical {
            let movedX = points[sectionIndex].x + translation.width
            points[sectionIndex].x = movedX
            points[sectionIndex + 1].x = movedX
        } else {
            let movedY = points[sectionIndex].y + translation.height
            points[sectionIndex].y = movedY
            points[sectionIndex + 1].y = movedY
        }
        let dragRoute = routeWithOrthogonalDragJoints(points, draggedSectionIndex: sectionIndex, isVertical: isVertical)
        wireAlignmentPreviewSegmentIDs.removeAll()
        cachedWirePoints[id] = dragRoute
        selectedTargetIDs.removeAll()
    }

    private func routeWithOrthogonalDragJoints(_ points: [CGPoint], draggedSectionIndex: Int, isVertical: Bool) -> [CGPoint] {
        guard points.indices.contains(draggedSectionIndex), points.indices.contains(draggedSectionIndex + 1) else { return points }
        return routeWithInsertedOrthogonalJoints(points) { sectionIndex, first, second, currentRoute in
            if sectionIndex == draggedSectionIndex - 1 {
                return isVertical ? CGPoint(x: second.x, y: first.y) : CGPoint(x: first.x, y: second.y)
            }
            if sectionIndex == draggedSectionIndex + 1 {
                return isVertical ? CGPoint(x: first.x, y: second.y) : CGPoint(x: second.x, y: first.y)
            }
            return preferredOrthogonalJoint(from: first, to: second, after: currentRoute)
        }
    }

    private func routeWithInsertedOrthogonalJoints(_ points: [CGPoint], corner: (Int, CGPoint, CGPoint, [CGPoint]) -> CGPoint) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = []
        for sectionIndex in 0..<(points.count - 1) {
            let first = points[sectionIndex]
            let second = points[sectionIndex + 1]
            appendDistinct(first, to: &result)
            if abs(first.x - second.x) > 0.5 && abs(first.y - second.y) > 0.5 {
                appendDistinct(corner(sectionIndex, first, second, result), to: &result)
            }
            appendDistinct(second, to: &result)
        }
        return result
    }

    private func routeWithInsertedOrthogonalJoints(_ points: [CGPoint]) -> [CGPoint] {
        routeWithInsertedOrthogonalJoints(points) { _, first, second, currentRoute in
            preferredOrthogonalJoint(from: first, to: second, after: currentRoute)
        }
    }

    private func preferredOrthogonalJoint(from first: CGPoint, to second: CGPoint, after route: [CGPoint]) -> CGPoint {
        if route.count >= 2 {
            let previous = route[route.count - 2]
            let arrivesVertically = abs(previous.x - first.x) < 0.5
            return arrivesVertically ? CGPoint(x: first.x, y: second.y) : CGPoint(x: second.x, y: first.y)
        }
        return CGPoint(x: second.x, y: first.y)
    }

    private func appendDistinct(_ point: CGPoint, to points: inout [CGPoint]) {
        guard points.last.map({ abs($0.x - point.x) > 0.5 || abs($0.y - point.y) > 0.5 }) ?? true else { return }
        points.append(point)
    }

    private func finalizeWireSectionDrag(_ id: UUID) {
        if let segmentIndex = document.segments.firstIndex(where: { $0.id == id }),
           let start = target(with: document.segments[segmentIndex].startID),
           let end = target(with: document.segments[segmentIndex].endID) {
            var points = cachedWirePoints[id]
                ?? orthogonalPoints(for: document.segments[segmentIndex], from: start, to: end, avoiding: [])
            if let sectionIndex = selectedSegmentSectionIndex,
               sectionIndex + 1 < points.count {
                let sectionStart = points[sectionIndex]
                let sectionEnd = points[sectionIndex + 1]
                let horizontal = abs(sectionStart.y - sectionEnd.y) < 0.5
                let coordinate = horizontal ? sectionStart.y : sectionStart.x
                if let alignment = nearbyParallelAlignment(
                    segmentID: id,
                    sectionStart: sectionStart,
                    sectionEnd: sectionEnd,
                    coordinate: coordinate
                ) {
                    let delta = alignment.coordinate - coordinate
                    if horizontal {
                        points[sectionIndex].y += delta
                        points[sectionIndex + 1].y += delta
                    } else {
                        points[sectionIndex].x += delta
                        points[sectionIndex + 1].x += delta
                    }
                    points = routeWithOrthogonalDragJoints(
                        points,
                        draggedSectionIndex: sectionIndex,
                        isVertical: !horizontal
                    )
                }
            }

            points = routeAroundObstaclesIfNeeded(points, segment: document.segments[segmentIndex], start: start, end: end)

            // Once the drag ends, merge collinear aligned sections and discard only
            // the interior vertices that no longer change the wire's path.
            let normalized = normalizedRoute(points, alignmentTolerance: CGFloat(wireAlignmentTolerance))
            document.segments[segmentIndex].routePoints = normalized
            cachedWirePoints[id] = normalized
        }
        wireAlignmentPreviewSegmentIDs.removeAll()
        wireLabelRouteAnchorPoints.removeValue(forKey: id)
    }

    private func routeAroundObstaclesIfNeeded(_ points: [CGPoint], segment: SchematicSegment, start: SchematicTarget, end: SchematicTarget) -> [CGPoint] {
        guard points.count >= 4 else { return points }
        let obstacles = routingObstacles(excluding: start.id, end.id)
            .filter { $0.kind != .junction }
            .map { obstacleRect(for: $0).insetBy(dx: -wireRoutingClearancePixels, dy: -wireRoutingClearancePixels) }
        guard !obstacles.isEmpty, !pointsAreClear(points, from: obstacles) else { return points }

        let startSlot = segment.startSlot ?? nearestConnectionSlot(for: start, to: points[0])
        let endSlot = segment.endSlot ?? nearestConnectionSlot(for: end, to: points[points.count - 1])
        let startPin = connectionPoint(for: start, slot: startSlot)
        let endPin = connectionPoint(for: end, slot: endSlot)
        let startFallback = escapePoint(for: start, slot: startSlot, toward: end)
        let endFallback = escapePoint(for: end, slot: endSlot, toward: start)
        let startStub = preservedStub(from: startPin, to: points[1], minimumLength: CGFloat(connectionStubLength), fallback: startFallback, matching: startFallback)
        let endStub = preservedStub(from: endPin, to: points[points.count - 2], minimumLength: CGFloat(connectionStubLength), fallback: endFallback, matching: endFallback)
        let detour = orthogonalRoute(from: startStub, to: endStub, avoiding: obstacles)
        let routed = routePreservingStubs(
            start: startPin,
            startStub: startStub,
            middle: detour,
            endStub: endStub,
            end: endPin
        )
        return pointsAreClear(routed, from: obstacles) ? routed : points
    }

    /// "Fix wire": simplifies collinear bend points AND collapses unnecessary out-and-back loops
    /// (e.g. horizontal-vertical-horizontal where the two horizontal legs reverse direction) into a single clean turn.
    private func fixAllWires() {
        guard !document.segments.isEmpty else { return }
        captureForUndo()
        for segment in document.segments {
            fixWire(segment)
        }
    }

    private func fixWire(_ segment: SchematicSegment) {
        guard let index = document.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let route = document.segments[index].routePoints
        let delooped = removeRouteLoops(route)
        let simplified = normalizedRoute(delooped, alignmentTolerance: CGFloat(wireAlignmentTolerance))
        document.segments[index].routePoints = simplified
        if let labelAnchor = wireLabelRouteAnchorPoints[segment.id] {
            updateWireLabelPosition(segment.id, route: simplified, near: labelAnchor)
        }
    }

    /// Detects a horizontal-vertical-horizontal (or vertical-horizontal-vertical) run where the two
    /// parallel legs reverse direction - an unnecessary "out and back" loop - and collapses it to one 90-degree turn.
    private func removeRouteLoops(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 4 else { return points }
        var result = points
        var i = 0
        while i + 3 < result.count {
            let a = result[i], b = result[i + 1], c = result[i + 2], d = result[i + 3]
            let abHorizontal = abs(a.y - b.y) < 0.5
            let cdHorizontal = abs(c.y - d.y) < 0.5
            let bcVertical = abs(b.x - c.x) < 0.5
            if abHorizontal && cdHorizontal && bcVertical, (b.x - a.x) * (d.x - c.x) < 0 {
                result.replaceSubrange(i...(i + 3), with: [a, CGPoint(x: d.x, y: a.y), d])
                continue
            }
            let abVertical = abs(a.x - b.x) < 0.5
            let cdVertical = abs(c.x - d.x) < 0.5
            let bcHorizontal = abs(b.y - c.y) < 0.5
            if abVertical && cdVertical && bcHorizontal, (b.y - a.y) * (d.y - c.y) < 0 {
                result.replaceSubrange(i...(i + 3), with: [a, CGPoint(x: a.x, y: d.y), d])
                continue
            }
            i += 1
        }
        return result
    }

    private func normalizedRoute(_ points: [CGPoint], alignmentTolerance: CGFloat = 0.5) -> [CGPoint] {
        var result = points
        for _ in 0..<max(points.count, 1) {
            let previous = result
            result = collapseAlignedInteriorPoints(removeRouteLoops(result), tolerance: alignmentTolerance)
            if result == previous { break }
        }
        return routeWithInsertedOrthogonalJoints(result)
    }

    private func collapseAlignedInteriorPoints(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var collapsed = [points[0]]
        for point in points.dropFirst() {
            guard let previous = collapsed.last else { continue }
            if abs(point.x - previous.x) <= tolerance && abs(point.y - previous.y) <= tolerance {
                continue
            }
            if collapsed.count >= 2 {
                let before = collapsed[collapsed.count - 2]
                let sharesVerticalAxis = abs(before.x - previous.x) <= tolerance && abs(previous.x - point.x) <= tolerance
                let sharesHorizontalAxis = abs(before.y - previous.y) <= tolerance && abs(previous.y - point.y) <= tolerance
                if sharesVerticalAxis || sharesHorizontalAxis {
                    collapsed[collapsed.count - 1] = point
                    continue
                }
            }
            collapsed.append(point)
        }
        return collapsed
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
        // Saved bends may change, but endpoint stubs are always rebuilt through the same assembler used for new wires.
        let points = orthogonalizedPoints(routePoints, alignmentTolerance: 0)
        guard points.count > 1 else { return points }
        let startSlot = segment.startSlot ?? startTargetSlot(startTarget, point: points[0])
        let endSlot = segment.endSlot ?? endTargetSlot(endTarget, point: points[points.count - 1])
        let startPin = connectionPoint(for: startTarget, slot: startSlot)
        let endPin = connectionPoint(for: endTarget, slot: endSlot)
        let startFallback = escapePoint(for: startTarget, slot: startSlot, toward: endTarget)
        let endFallback = escapePoint(for: endTarget, slot: endSlot, toward: startTarget)
        let startEscape = preservedStub(from: startPin, to: points[1], minimumLength: 15, fallback: startFallback, matching: startFallback)
        let endEscape = preservedStub(from: endPin, to: points[points.count - 2], minimumLength: 15, fallback: endFallback, matching: endFallback)
        let middle: [CGPoint]
        if points.count > 4 {
            middle = Array(points.dropFirst(2).dropLast(2))
        } else if points.count == 3 {
            middle = [points[1]]
        } else {
            middle = []
        }
        return routePreservingStubs(start: startPin, startStub: startEscape, middle: [startEscape] + middle + [endEscape], endStub: endEscape, end: endPin)
    }

    private func preservedStub(from pin: CGPoint, to existingPoint: CGPoint, minimumLength: CGFloat, fallback: CGPoint, matching expected: CGPoint) -> CGPoint {
        let dx = existingPoint.x - pin.x
        let dy = existingPoint.y - pin.y
        let expectedDX = expected.x - pin.x
        let expectedDY = expected.y - pin.y
        let length = hypot(dx, dy)
        let expectedLength = max(hypot(expectedDX, expectedDY), 1)
        let directionMatches = (dx * expectedDX + dy * expectedDY) / max(length * expectedLength, 1) > 0.7
        guard length > 0.5, directionMatches else { return fallback }
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

        let rectangles = obstacles
            .filter { $0.kind != .junction }
            .map { obstacleRect(for: $0).insetBy(dx: -wireRoutingClearancePixels, dy: -wireRoutingClearancePixels) }
        let directPaths = [
            [escapeStart, CGPoint(x: escapeEnd.x, y: escapeStart.y), escapeEnd],
            [escapeStart, CGPoint(x: escapeStart.x, y: escapeEnd.y), escapeEnd]
        ].map { path in
            var adjusted = path
            if adjusted.count > 2 {
                if abs(adjusted[0].y - adjusted[1].y) < 0.5 {
                    adjusted[1].y += segment.bendOffset
                    if snapToGrid { adjusted[1].y = snappedCoordinate(adjusted[1].y) }
                } else {
                    adjusted[1].x += segment.bendOffset
                    if snapToGrid { adjusted[1].x = snappedCoordinate(adjusted[1].x) }
                }
            }
            return adjusted
        }
        let clearDirectPaths = directPaths.filter { rectangles.isEmpty || pointsAreClear($0, from: rectangles) }
        let middlePath = clearDirectPaths.min(by: { pathLength($0) < pathLength($1) })
            ?? orthogonalRoute(from: escapeStart, to: escapeEnd, avoiding: rectangles)

        return routePreservingStubs(start: start, startStub: escapeStart, middle: middlePath, endStub: escapeEnd, end: end)
    }

    private func routePreservingStubs(start: CGPoint, startStub: CGPoint, middle: [CGPoint], endStub: CGPoint, end: CGPoint) -> [CGPoint] {
        let interior = Array(middle.dropFirst().dropLast())
        let route = [start, startStub] + interior + [endStub, end]
        return routeWithInsertedOrthogonalJoints(route) { _, first, second, currentRoute in
            preferredOrthogonalJoint(from: first, to: second, after: currentRoute)
        }
    }

    /// Grid-based orthogonal pathfinder: builds a Manhattan grid from the start/end points plus every
    /// obstacle rectangle's edges, then finds the shortest all-right-angle path that doesn't cross any
    /// obstacle - routing AROUND items rather than behind them. Falls back to a shortest one-bend path if no
    /// obstacle blocks it, or if no clear route can be found at all.
    private func orthogonalRoute(from start: CGPoint, to end: CGPoint, avoiding obstacles: [CGRect]) -> [CGPoint] {
        let directFallbacks = [
            [start, CGPoint(x: end.x, y: start.y), end],
            [start, CGPoint(x: start.x, y: end.y), end]
        ]
        guard !obstacles.isEmpty else {
            return directFallbacks.min(by: { pathLength($0) < pathLength($1) }) ?? [start, end]
        }

        var xs = Set([start.x, end.x])
        var ys = Set([start.y, end.y])
        for rect in obstacles {
            xs.insert(rect.minX); xs.insert(rect.maxX)
            ys.insert(rect.minY); ys.insert(rect.maxY)
        }
        let sortedX = xs.sorted()
        let sortedY = ys.sorted()

        func nearestIndex(_ value: CGFloat, in array: [CGFloat]) -> Int {
            array.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
        }
        func blocked(_ p1: CGPoint, _ p2: CGPoint) -> Bool {
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            return obstacles.contains { $0.contains(mid) }
        }

        struct Node: Hashable { let x: Int; let y: Int }
        let startNode = Node(x: nearestIndex(start.x, in: sortedX), y: nearestIndex(start.y, in: sortedY))
        let endNode = Node(x: nearestIndex(end.x, in: sortedX), y: nearestIndex(end.y, in: sortedY))

        var costSoFar: [Node: CGFloat] = [startNode: 0]
        var cameFrom: [Node: Node] = [:]
        var frontier: [(Node, CGFloat)] = [(startNode, 0)]
        var visited = Set<Node>()

        while !frontier.isEmpty {
            frontier.sort { $0.1 < $1.1 }
            let (current, currentCost) = frontier.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            if current == endNode { break }
            let neighbors = [Node(x: current.x - 1, y: current.y), Node(x: current.x + 1, y: current.y), Node(x: current.x, y: current.y - 1), Node(x: current.x, y: current.y + 1)]
            let p1 = CGPoint(x: sortedX[current.x], y: sortedY[current.y])
            for neighbor in neighbors {
                guard sortedX.indices.contains(neighbor.x), sortedY.indices.contains(neighbor.y), !visited.contains(neighbor) else { continue }
                let p2 = CGPoint(x: sortedX[neighbor.x], y: sortedY[neighbor.y])
                guard !blocked(p1, p2) else { continue }
                let newCost = currentCost + abs(p1.x - p2.x) + abs(p1.y - p2.y)
                if newCost < (costSoFar[neighbor] ?? .greatestFiniteMagnitude) {
                    costSoFar[neighbor] = newCost
                    cameFrom[neighbor] = current
                    frontier.append((neighbor, newCost))
                }
            }
        }

        guard cameFrom[endNode] != nil else {
            return directFallbacks.min(by: { pathLength($0) < pathLength($1) }) ?? [start, end]
        }
        var path = [endNode]
        var node = endNode
        while node != startNode, let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        path.reverse()
        var points = path.map { CGPoint(x: sortedX[$0.x], y: sortedY[$0.y]) }
        points[0] = start
        points[points.count - 1] = end
        return routeWithInsertedOrthogonalJoints(simplifyOrthogonalPoints(points))
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
        return normalizedRoute(result, alignmentTolerance: alignmentTolerance)
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
            ? connectionAngle(for: target, slot: slot) * Double.pi / 180
            : atan2(point.y - target.position.y, point.x - target.position.x)
        let distance: CGFloat = target.kind == .junction ? 0 : max(15, CGFloat(connectionStubLength))
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
        let size = target.kind == .junction ? CGSize(width: 18, height: 18) : target.isCompact ? CGSize(width: 40, height: 40) : CGSize(width: 76, height: 68)
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
            let route = cachedWirePoints[segment.id]
                ?? (segment.routePoints.count > 1
                    ? segment.routePoints
                    : orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id)))
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
        captureForUndo()
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
            document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, startSlot: startSlot, endSlot: firstSlot, name: segment.name + " A", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.first), at: hit.index)
            document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, startSlot: secondSlot, endSlot: endSlot, name: segment.name + " B", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.second), at: hit.index + 1)
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
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: targetID, startSlot: startSlot, endSlot: firstSlot, name: segment.name + " A", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: routeIntoPin(Array(splitRoutes.first.dropLast()), target: document.targets[targetIndex], slot: firstSlot, toward: segment.startID, fallback: junctionPosition)), at: hit.index)
        let secondSlot = closestAvailableSlot(for: targetID, to: segment.endID) ?? (firstSlot == 0 ? 1 : 0)
        document.segments.insert(SchematicSegment(startID: targetID, endID: segment.endID, startSlot: secondSlot, endSlot: endSlot, name: segment.name + " B", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: routeIntoPin(Array(splitRoutes.second.dropFirst()).reversed(), target: document.targets[targetIndex], slot: secondSlot, toward: segment.endID, fallback: junctionPosition).reversed()), at: hit.index + 1)
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
        guard let other = self.target(with: otherID) else { return routeWithInsertedOrthogonalJoints(orthogonalizedPoints(points + [pin])) }
        let escape = escapePoint(for: target, slot: slot, toward: other)
        let previous = points.last ?? fallback
        let pinIsVertical = abs(pin.y - target.position.y) >= abs(pin.x - target.position.x)
        let corner = pinIsVertical ? CGPoint(x: previous.x, y: escape.y) : CGPoint(x: escape.x, y: previous.y)
        return routeWithInsertedOrthogonalJoints(simplifyOrthogonalPoints((points.isEmpty ? [fallback] : points) + [corner, escape, pin]))
    }

    private func splitWire(_ segment: SchematicSegment, at placedPoint: CGPoint? = nil) {
        guard let start = target(with: segment.startID), let end = target(with: segment.endID),
              let index = document.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let route = orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
        let midpoint = placedPoint ?? nearestPoint(on: route, to: CGPoint(x: (start.position.x + end.position.x) / 2, y: (start.position.y + end.position.y) / 2)).point
        let junctionPosition = snapToGrid ? snappedPosition(midpoint) : midpoint
        let splitRoutes = splitRoutePoints(route, at: junctionPosition)
        let junction = SchematicTarget(identifier: nextTargetIdentifier(for: .junction), kind: .junction, name: "Junction", position: junctionPosition, maxConnections: 8, colorHex: TargetKind.junction.defaultColorHex)
        document.targets.append(junction)
        document.segments.remove(at: index)
        document.segments.insert(SchematicSegment(startID: segment.startID, endID: junction.id, startSlot: segment.startSlot, endSlot: 0, name: segment.name + " A", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.first), at: index)
        document.segments.insert(SchematicSegment(startID: junction.id, endID: segment.endID, startSlot: 1, endSlot: segment.endSlot, name: segment.name + " B", colorHex: segment.colorHex, size: segment.size, type: segment.type, misc: segment.misc, netName: segment.netName, displayWidth: segment.displayWidth, description: segment.description, routePoints: splitRoutes.second), at: index + 1)
        selectedSegmentIDs.remove(segment.id)
        selectedSegmentID = nil
    }

    private func placeWirePoint(at screenLocation: CGPoint) {
        guard let mode = wirePlacementMode,
              let segment = selectedSegment,
              let start = target(with: segment.startID),
              let end = target(with: segment.endID) else { return }
        let canvasPoint = canvasDropPoint(screenLocation, canvasSize: editorSize)
        let route = orthogonalPoints(for: segment, from: start, to: end, avoiding: routingObstacles(excluding: start.id, end.id))
        let placedPoint = nearestPoint(on: route, to: canvasPoint).point
        if mode == .connection {
            splitWire(segment, at: placedPoint)
        } else if let index = document.segments.firstIndex(where: { $0.id == segment.id }) {
            let split = splitRoutePoints(route, at: placedPoint)
            document.segments[index].routePoints = orthogonalizedPoints(split.first + Array(split.second.dropFirst()), alignmentTolerance: 0)
        }
        wirePlacementMode = nil
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

    private func segmentBinding(_ segment: SchematicSegment, applyToAll: Bool = false) -> (name: Binding<String>, color: Binding<Color>, size: Binding<String>, type: Binding<String>, displayWidth: Binding<Double>, description: Binding<String>, misc: Binding<String>, netName: Binding<String>) {
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
            Binding(get: { current().size }, set: { value in update { $0.size = value } }),
            Binding(get: { current().type }, set: { value in update { $0.type = value } }),
            Binding(get: { current().displayWidth }, set: { value in update { $0.displayWidth = value } }),
            Binding(get: { current().description }, set: { value in update { $0.description = value } }),
            Binding(get: { current().misc }, set: { value in update { $0.misc = value } }),
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
    
    private func loadBackgroundImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data) else { return }
        backgroundImage = uiImage
        backgroundImageSize = CGSize(width: 200, height: 200)
        backgroundImagePhotoItem = nil
        saveBackgroundImageState()
    }
    
    private func clearBackgroundImage() {
        backgroundImage = nil
        backgroundImagePhotoItem = nil
        document.backgroundImageBase64 = nil
        SchematicDocument.saveLast(document)
    }
    
    private func restoreBackgroundImage() {
        if let base64String = document.backgroundImageBase64, 
           let imageData = Data(base64Encoded: base64String),
           let uiImage = UIImage(data: imageData) {
            backgroundImage = uiImage
            backgroundImageSize = document.backgroundImageSize
            backgroundImagePosition = document.backgroundImagePosition
            backgroundImageOpacity = document.backgroundImageOpacity
            backgroundImageLocked = document.backgroundImageLocked
            backgroundImageConstrainProportions = document.backgroundImageConstrainProportions
        } else {
            // Clear background image if document has no background image
            backgroundImage = nil
            backgroundImageSize = CGSize(width: 500, height: 500)
            backgroundImagePosition = CGPoint(x: 2000, y: 2000)
            backgroundImageOpacity = 1.0
            backgroundImageLocked = false
            backgroundImageConstrainProportions = false
            backgroundImagePhotoItem = nil
        }
    }
    
    private func saveBackgroundImageState() {
        if let bgImage = backgroundImage, let imageData = bgImage.pngData() {
            document.backgroundImageBase64 = imageData.base64EncodedString()
        } else {
            document.backgroundImageBase64 = nil
        }
        document.backgroundImageSize = backgroundImageSize
        document.backgroundImagePosition = backgroundImagePosition
        document.backgroundImageOpacity = backgroundImageOpacity
        document.backgroundImageLocked = backgroundImageLocked
        document.backgroundImageConstrainProportions = backgroundImageConstrainProportions
        SchematicDocument.saveLast(document)
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

    private func saveTargetIdentifier(_ target: SchematicTarget) {
        guard let index = document.targets.firstIndex(where: { $0.id == target.id }) else { return }
        let trimmedIdentifier = targetIdentifierDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedIdentifier.isEmpty,
              !document.targets.enumerated().contains(where: { $0.offset != index && $0.element.identifier.caseInsensitiveCompare(trimmedIdentifier) == .orderedSame }) else { return }
        document.targets[index].identifier = trimmedIdentifier
        targetIdentifierDraft = trimmedIdentifier
    }

    private func cancelTargetIdentifier(_ target: SchematicTarget) {
        targetIdentifierDraft = target.identifier
    }

    private func applyLineDefinition(_ line: LineDefinition, to segmentID: UUID) {
        guard let index = document.segments.firstIndex(where: { $0.id == segmentID }) else { return }
        document.segments[index].name = line.name
        document.segments[index].colorHex = line.colorHex
        document.segments[index].size = line.wireSize
        document.segments[index].type = line.wireType
        document.segments[index].misc = line.misc
        document.segments[index].description = line.description
    }

    private func applyLineDefinition(_ line: LineDefinition, to segmentIDs: Set<UUID>) {
        for segmentID in segmentIDs {
            applyLineDefinition(line, to: segmentID)
        }
    }

    private func beginNewLineDefinition() {
        editingLineDefinitionID = nil
        lineDefinitionUsesCustomSize = false
        lineDefinitionUsesCustomType = false
        lineDefinitionNameDraft = ""
        lineDefinitionSizeDraft = lineDefinitionSizeOptions.first ?? ""
        lineDefinitionTypeDraft = lineDefinitionTypeOptions.first ?? ""
        lineDefinitionMiscDraft = ""
        lineDefinitionColorHexDraft = "31D7E8"
        lineDefinitionDescriptionDraft = ""
        showLineDefinitionEditor = true
    }

    private func beginEditLineDefinition(_ line: LineDefinition) {
        editingLineDefinitionID = line.id
        lineDefinitionUsesCustomSize = false
        lineDefinitionUsesCustomType = false
        lineDefinitionNameDraft = line.name
        lineDefinitionSizeDraft = line.wireSize
        lineDefinitionTypeDraft = line.wireType
        lineDefinitionMiscDraft = line.misc
        lineDefinitionColorHexDraft = line.colorHex
        lineDefinitionDescriptionDraft = line.description
        showLineDefinitionEditor = true
    }

    private func saveLineDefinitionDraft() {
        let material = ConductorMaterial.allCases.first { lineDefinitionTypeDraft.localizedCaseInsensitiveContains($0.rawValue) } ?? .copper
        let definition = LineDefinition(
            id: editingLineDefinitionID ?? UUID(),
            name: lineDefinitionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: lineDefinitionColorHexDraft,
            wireSize: lineDefinitionSizeDraft,
            wireType: lineDefinitionTypeDraft,
            material: material,
            misc: lineDefinitionMiscDraft,
            description: lineDefinitionDescriptionDraft
        )
        if let editingLineDefinitionID, let index = document.lineDefinitions.firstIndex(where: { $0.id == editingLineDefinitionID }) {
            document.lineDefinitions[index] = definition
        } else {
            document.lineDefinitions.append(definition)
        }
        showLineDefinitionEditor = false
    }

    private func beginNewColorLegendEntry() {
        editingColorLegendID = nil
        colorLegendHexDraft = "31D7E8"
        colorLegendMeaningDraft = ""
        showColorLegendEditor = true
    }

    private func beginEditColorLegendEntry(_ entry: ColorLegendEntry) {
        editingColorLegendID = entry.id
        colorLegendHexDraft = entry.colorHex
        colorLegendMeaningDraft = entry.meaning
        showColorLegendEditor = true
    }

    private func saveColorLegendEntry() {
        let entry = ColorLegendEntry(id: editingColorLegendID ?? UUID(), colorHex: colorLegendHexDraft, meaning: colorLegendMeaningDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        if let editingColorLegendID, let index = document.colorLegend.firstIndex(where: { $0.id == editingColorLegendID }) {
            document.colorLegend[index] = entry
        } else {
            document.colorLegend.append(entry)
        }
        showColorLegendEditor = false
    }
}

private struct CloudDrawingChoice: Identifiable {
    let id: UUID
    let name: String
    let data: Data
}

private struct LocalErrorEntry: Codable {
    let date: Date
    let message: String
}

private struct SchematicVersion: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt: Date
    var description: String
    var userName: String
    var data: Data
}

private enum LocalErrorLog {
    private static let key = "easy1line.errorLog"

    static func load() -> [LocalErrorEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([LocalErrorEntry].self, from: data) else { return [] }
        return entries
    }

    static func save(_ entries: [LocalErrorEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func text(_ entries: [LocalErrorEntry]) -> String {
        guard !entries.isEmpty else { return "Easy1Line error log is empty." }
        let formatter = ISO8601DateFormatter()
        return entries.map { "[\(formatter.string(from: $0.date))] \($0.message)" }.joined(separator: "\n")
    }
}

private enum WirePlacementMode {
    case connection
    case bend
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

private struct ColorLegendEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var colorHex: String
    var meaning: String

    init(id: UUID = UUID(), colorHex: String, meaning: String) {
        self.id = id
        self.colorHex = colorHex
        self.meaning = meaning
    }

    static let defaults: [ColorLegendEntry] = [
        ColorLegendEntry(colorHex: "D98B5F", meaning: "120 V"),
        ColorLegendEntry(colorHex: "818CF8", meaning: "240 V")
    ]
}

private struct SchematicDocument: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdByName: String = ""
    var updatedByName: String = ""
    var targets: [SchematicTarget] = []
    var segments: [SchematicSegment] = []
    var lineDefinitions: [LineDefinition] = LineDefinition.defaults
    var colorLegend: [ColorLegendEntry] = ColorLegendEntry.defaults
    var targetDefinitions: [TargetDefinition] = []
    var versionHistory: [SchematicVersion] = []
    var backgroundImageBase64: String? = nil
    var backgroundImageSize: CGSize = CGSize(width: 200, height: 200)
    var backgroundImagePosition: CGPoint = CGPoint(x: 2000, y: 2000)
    var backgroundImageOpacity: Double = 1.0
    var backgroundImageLocked: Bool = false
    var backgroundImageConstrainProportions: Bool = false

    init(name: String, targets: [SchematicTarget] = [], segments: [SchematicSegment] = [], lineDefinitions: [LineDefinition] = LineDefinition.defaults, targetDefinitions: [TargetDefinition] = TargetDefinition.defaults) {
        self.name = name; self.targets = targets; self.segments = segments; self.lineDefinitions = lineDefinitions; self.targetDefinitions = targetDefinitions
        assignMissingTargetIdentifiers()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled schematic"
        createdByName = try container.decodeIfPresent(String.self, forKey: .createdByName) ?? ""
        updatedByName = try container.decodeIfPresent(String.self, forKey: .updatedByName) ?? ""
        targets = try container.decodeIfPresent([SchematicTarget].self, forKey: .targets) ?? []
        assignMissingTargetIdentifiers()
        segments = try container.decodeIfPresent([SchematicSegment].self, forKey: .segments) ?? []
        let savedLineDefinitions = try container.decodeIfPresent([LineDefinition].self, forKey: .lineDefinitions) ?? []
        let isLegacyBulkCatalog = savedLineDefinitions.count > 20 && savedLineDefinitions.allSatisfy { $0.description.contains("Common") || $0.name.contains(" ") }
        lineDefinitions = savedLineDefinitions.isEmpty || isLegacyBulkCatalog ? LineDefinition.defaults : savedLineDefinitions
        colorLegend = try container.decodeIfPresent([ColorLegendEntry].self, forKey: .colorLegend) ?? ColorLegendEntry.defaults
        let savedTargetDefinitions = try container.decodeIfPresent([TargetDefinition].self, forKey: .targetDefinitions) ?? []
        targetDefinitions = savedTargetDefinitions.isEmpty ? TargetDefinition.defaults : savedTargetDefinitions
        versionHistory = try container.decodeIfPresent([SchematicVersion].self, forKey: .versionHistory) ?? []
        backgroundImageBase64 = try container.decodeIfPresent(String.self, forKey: .backgroundImageBase64)
        backgroundImageSize = try container.decodeIfPresent(CGSize.self, forKey: .backgroundImageSize) ?? CGSize(width: 200, height: 200)
        backgroundImagePosition = try container.decodeIfPresent(CGPoint.self, forKey: .backgroundImagePosition) ?? CGPoint(x: 2000, y: 2000)
        backgroundImageOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundImageOpacity) ?? 1.0
        backgroundImageLocked = try container.decodeIfPresent(Bool.self, forKey: .backgroundImageLocked) ?? false
        backgroundImageConstrainProportions = try container.decodeIfPresent(Bool.self, forKey: .backgroundImageConstrainProportions) ?? false
    }

    private mutating func assignMissingTargetIdentifiers() {
        var used = Set(targets.map(\.identifier).filter { !$0.isEmpty })
        var counters: [String: Int] = [:]
        for index in targets.indices where targets[index].identifier.isEmpty {
            let prefix = targets[index].kind.designatorPrefix
            var number = counters[prefix, default: 1]
            var identifier = String(format: "%@%03d", prefix, number)
            while used.contains(identifier) {
                number += 1
                identifier = String(format: "%@%03d", prefix, number)
            }
            targets[index].identifier = identifier
            used.insert(identifier)
            counters[prefix] = number + 1
        }
    }

    static func snapshotData(for document: SchematicDocument) -> Data? {
        var snapshot = document
        snapshot.versionHistory = []
        return try? JSONEncoder().encode(snapshot)
    }

    static func loadLast() -> SchematicDocument {
        guard let data = UserDefaults.standard.data(forKey: "lastSchematic"), let saved = try? JSONDecoder().decode(SchematicDocument.self, from: data) else {
            return SchematicDocument(name: "Untitled schematic", targets: [SchematicTarget(kind: .source, name: "Power source", position: CGPoint(x: 330, y: 270), maxConnections: 2, colorHex: "FF9F43"), SchematicTarget(kind: .ground, name: "Ground", position: CGPoint(x: 650, y: 430), maxConnections: 2, colorHex: "94A3B8")])
        }
        return saved
    }

    static func loadAll() -> [SchematicDocument] { guard let data = UserDefaults.standard.data(forKey: "savedSchematics"), let saved = try? JSONDecoder().decode([SchematicDocument].self, from: data) else { return [] }; return saved }
    static func saveLast(_ document: SchematicDocument) { if let data = try? JSONEncoder().encode(document) { UserDefaults.standard.set(data, forKey: "lastSchematic") } }
    static func saveAll(_ documents: [SchematicDocument]) { if let data = try? JSONEncoder().encode(documents) { UserDefaults.standard.set(data, forKey: "savedSchematics") } }
}

private struct SchematicTarget: Identifiable, Codable, Equatable {
    var id = UUID()
    var identifier: String
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

    init(id: UUID = UUID(), identifier: String = "", kind: TargetKind, name: String, position: CGPoint, maxConnections: Int, colorHex: String, symbol: String? = nil, imageData: Data? = nil, connectionAngle: Double = 0, connectionAngles: [Double] = [], connectionNames: [String] = [], scale: Double = 1, isCompact: Bool = false, locked: Bool = false) {
        self.id = id
        self.identifier = identifier
        self.kind = kind
        self.name = kind.title
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
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? TargetKind.source.rawValue
        kind = TargetKind(rawValue: rawKind) ?? .source
        name = kind.title
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
        TargetDefinition(kind: $0, name: $0.title, maxConnections: 2, colorHex: $0.defaultColorHex, symbol: $0.symbol, imageData: nil, connectionAngles: [], scale: 1)
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
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? TargetKind.source.rawValue
        kind = TargetKind(rawValue: rawKind) ?? .source
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
    var colorMeaning: String
    var size: String // e.g., "14 AWG", "1/0", "2/0"
    var type: String // e.g., "Copper", "Aluminum", "ACSR"
    var misc: String // e.g., "BARE", "INSULATED", "POLYETHYLENE"
    var netName: String
    var displayWidth: Double
    var description: String
    var bendOffset: CGFloat
    var routePoints: [CGPoint]
    var labelPosition: Double
    var labelSectionIndex: Int
    var labelSectionPosition: Double
    var color: Color { Color(hex: colorHex) }

    init(startID: UUID, endID: UUID, startSlot: Int? = nil, endSlot: Int? = nil, name: String, colorHex: String, colorMeaning: String = "", size: String = "14 AWG", type: String = "Copper", misc: String = "BARE", netName: String = "N001", displayWidth: Double = 3, description: String = "", bendOffset: CGFloat = 0, routePoints: [CGPoint] = [], labelPosition: Double = 0.5, labelSectionIndex: Int = -1, labelSectionPosition: Double = 0.5) {
        self.startID = startID; self.endID = endID; self.startSlot = startSlot; self.endSlot = endSlot; self.name = name; self.colorHex = colorHex
        self.colorMeaning = colorMeaning
        self.size = size; self.type = type; self.misc = misc; self.netName = netName; self.displayWidth = displayWidth; self.description = description; self.bendOffset = bendOffset; self.routePoints = routePoints; self.labelPosition = labelPosition; self.labelSectionIndex = labelSectionIndex; self.labelSectionPosition = labelSectionPosition
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
        colorMeaning = try container.decodeIfPresent(String.self, forKey: .colorMeaning) ?? ""
        // Handle both old (wireSize) and new (size) field names
        size = try container.decodeIfPresent(String.self, forKey: .size) ?? "14 AWG"
        // Handle both old (material) and new (type) field names
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Copper"
        // Handle both old (covering) and new (misc) field names
        misc = try container.decodeIfPresent(String.self, forKey: .misc) ?? "BARE"
        netName = try container.decodeIfPresent(String.self, forKey: .netName) ?? "N001"
        displayWidth = try container.decodeIfPresent(Double.self, forKey: .displayWidth) ?? 3
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        bendOffset = try container.decodeIfPresent(CGFloat.self, forKey: .bendOffset) ?? 0
        routePoints = try container.decodeIfPresent([CGPoint].self, forKey: .routePoints) ?? []
        labelPosition = try container.decodeIfPresent(Double.self, forKey: .labelPosition) ?? 0.5
        labelSectionIndex = try container.decodeIfPresent(Int.self, forKey: .labelSectionIndex) ?? -1
        labelSectionPosition = try container.decodeIfPresent(Double.self, forKey: .labelSectionPosition) ?? 0.5
    }
}

private struct LineDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String
    var colorMeaning: String
    var wireSize: String
    var wireType: String
    var material: ConductorMaterial
    var misc: String
    var displayWidth: Double
    var description: String

    init(id: UUID = UUID(), name: String, colorHex: String = "31D7E8", colorMeaning: String = "", wireSize: String, wireType: String = "Copper", material: ConductorMaterial = .copper, misc: String = "BARE", displayWidth: Double = 3, description: String) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.colorMeaning = colorMeaning; self.wireSize = wireSize; self.wireType = wireType; self.material = material; self.misc = misc; self.displayWidth = displayWidth; self.description = description
    }

    static let defaultLine = LineDefinition(name: "14/3 SO", wireSize: "14/3", wireType: "SO", material: .copper, misc: "Flexible cord", description: "Common portable cord")
    static let defaults: [LineDefinition] = [
        LineDefinition(name: "1/0 AAAC", colorHex: "F2C14E", colorMeaning: "15 kV", wireSize: "1/0", wireType: "AAAC", material: .aaac, misc: "Bare overhead", description: "Aluminum alloy overhead conductor"),
        LineDefinition(name: "1/0 ACSR", colorHex: "8C9AA8", colorMeaning: "15 kV", wireSize: "1/0", wireType: "ACSR", material: .acsr, misc: "Bare overhead", description: "Aluminum conductor steel reinforced"),
        LineDefinition(name: "12/3 SO", colorHex: "D98B5F", colorMeaning: "120 V", wireSize: "12/3", wireType: "SO", material: .copper, misc: "Flexible cord", description: "Common portable cord"),
        LineDefinition(name: "14/3 SO", colorHex: "D98B5F", colorMeaning: "120 V", wireSize: "14/3", wireType: "SO", material: .copper, misc: "Flexible cord", description: "Common portable cord"),
        LineDefinition(name: "#4 Solid Copper", colorHex: "818CF8", colorMeaning: "240 V", wireSize: "#4", wireType: "Solid Copper", material: .copper, misc: "Solid", description: "Solid copper conductor")
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Standard wire"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "31D7E8"
        colorMeaning = try container.decodeIfPresent(String.self, forKey: .colorMeaning) ?? ""
        wireSize = try container.decodeIfPresent(String.self, forKey: .wireSize) ?? "14 AWG"
        material = try container.decodeIfPresent(ConductorMaterial.self, forKey: .material) ?? .copper
        wireType = try container.decodeIfPresent(String.self, forKey: .wireType) ?? material.rawValue
        misc = try container.decodeIfPresent(String.self, forKey: .misc) ?? ""
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
    case source, transformer, switchTarget, fuse, recloser, pt, ct, capacitor, ground, threePhaseTransformer, junction
    static let palette: [TargetKind] = [.source, .transformer, .switchTarget, .fuse, .recloser, .pt, .ct, .capacitor, .ground, .threePhaseTransformer, .junction]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: return "Source"; case .transformer: return "Transformer"; case .switchTarget: return "Switch"; case .fuse: return "Fuse"; case .recloser: return "Recloser"; case .pt: return "PT"; case .ct: return "CT"; case .capacitor: return "Capacitor"; case .ground: return "Ground"; case .threePhaseTransformer: return "3-Phase Transformer"; case .junction: return "Junction"
        }
    }
    var symbol: String {
        switch self {
        case .source: return "bolt.fill"; case .transformer: return "arrow.left.arrow.right"; case .switchTarget: return "switch.2"; case .fuse: return "circle.slash.fill"; case .recloser: return "arrow.triangle.2.circlepath"; case .pt: return "bolt.circle"; case .ct: return "smallcircle.filled.circle"; case .capacitor: return "minus.plus.batteryblock"; case .ground: return "arrow.down.to.line"; case .threePhaseTransformer: return "arrow.left.arrow.right"; case .junction: return "circle.fill"
        }
    }
    var defaultColorHex: String {
        switch self {
        case .source: return "FF9F43"; case .transformer: return "F59E0B"; case .switchTarget: return "6EE7B7"; case .fuse: return "F87171"; case .recloser: return "FCA5A5"; case .pt: return "A78BFA"; case .ct: return "818CF8"; case .capacitor: return "F472B6"; case .ground: return "94A3B8"; case .threePhaseTransformer: return "FBBF24"; case .junction: return "31D7E8"
        }
    }

    var designatorPrefix: String {
        switch self {
        case .source: return "SRC"
        case .transformer: return "T"
        case .switchTarget: return "SW"
        case .fuse: return "F"
        case .recloser: return "REC"
        case .pt: return "PT"
        case .ct: return "CT"
        case .capacitor: return "C"
        case .ground: return "GND"
        case .threePhaseTransformer: return "T3"
        case .junction: return "J"
        }
    }
}

private struct MultiuserSessionView: View {
    @ObservedObject var session: MultipeerSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    if session.connectedPeers.isEmpty {
                        Text("Not connected").foregroundStyle(.secondary)
                    } else {
                        Text("Connected: \(session.connectedPeers.map(\.displayName).joined(separator: ", "))")
                            .foregroundStyle(.green)
                    }
                }
                Section("Nearby Devices") {
                    if session.availablePeers.isEmpty {
                        Text("Searching for nearby devices…").foregroundStyle(.secondary)
                    }
                    ForEach(session.availablePeers, id: \.self) { peer in
                        let isConnected = session.connectedPeers.contains(peer)
                        Button {
                            session.invite(peer)
                        } label: {
                            HStack {
                                Text(peer.displayName)
                                Spacer()
                                if isConnected {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(isConnected)
                    }
                }
            }
            .navigationTitle("Multiuser Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Disconnect", role: .destructive) { session.disconnect() }
                }
            }
            .onAppear { session.start() }
        }
    }
}

private struct PaletteItem: View {
    let kind: TargetKind
    let compact: Bool
    var body: some View {
        HStack(spacing: 10) {
            SchematicSymbolView(kind: kind, color: Color(hex: kind.defaultColorHex)).frame(width: 18, height: 18)
            if !compact {
                Text(kind.title).font(.system(size: 14.95, weight: .semibold))
                Spacer()
            }
            Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .clipped()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
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
    let connectionCounts: [Int: Int]
    let selectedSlots: Set<Int>
    let connectionNames: [String]
    let showConnectionNames: Bool
    let baseItemSize: Double
    let selectionHighlightColor: Color
    let connectionMode: Bool
    let connectionMoveMode: Bool
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
                .frame(width: 32, height: 32)
            } else if target.isCompact {
                ZStack {
                    Circle().fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                    Circle().stroke(borderStyle, lineWidth: isSelected || isConnectionStart ? 3 : 2)
                    if let imageData = target.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 24, height: 24).clipShape(Circle())
                    } else {
                        SchematicSymbolView(kind: target.kind, color: Color(hex: target.colorHex)).frame(width: 22, height: 22)
                    }
                }
                .frame(width: 40, height: 40)
            } else {
                ZStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                        if let imageData = target.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            SchematicSymbolView(kind: target.kind, color: Color(hex: target.colorHex)).frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 58, height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: target.colorHex), lineWidth: 1.5)
                    }
                    .position(x: 38, y: 30)
                    Text(target.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 80, height: 24)
                        .position(x: 38, y: 62)
                }
                .frame(width: 76, height: 68)
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
                        .frame(width: 76, height: 68)
                }
            }
        }
        .overlay {
            if (isSelected || isConnectionStart) && !connectionMode {
                if target.kind == .junction {
                    Circle().stroke(selectionHighlightColor, lineWidth: 4).frame(width: 30, height: 30).shadow(color: selectionHighlightColor.opacity(0.95), radius: 12)
                } else if target.isCompact {
                    Circle().stroke(selectionHighlightColor, lineWidth: 4).frame(width: 44, height: 44).shadow(color: selectionHighlightColor.opacity(0.95), radius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 12).stroke(selectionHighlightColor, lineWidth: 4).frame(width: 76, height: 68).shadow(color: selectionHighlightColor.opacity(0.95), radius: 12)
                }
            }
        }
        .overlay {
            if target.kind != .junction {
                ForEach(0..<target.maxConnections, id: \.self) { slot in
                    connectionPoint(slot: slot)
                }
            }
        }
        // Pins sit outside the body frame; widen the hit shape so taps on them don't fall through to wires.
        .contentShape(connectionMode || connectionMoveMode ? AnyShape(Rectangle().inset(by: -48)) : target.kind == .junction ? AnyShape(Rectangle().inset(by: -16)) : targetHitShape)
        .scaleEffect(CGFloat(target.scale * baseItemSize))
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
        let connectionCount = connectionCounts[slot] ?? 0
        let point = Circle()
            .fill(selectedSlots.contains(slot) ? Color.cyan : Color(hex: target.colorHex))
            .frame(width: selectedSlots.contains(slot) ? 14 : 9, height: selectedSlots.contains(slot) ? 14 : 9)
            .overlay { Circle().stroke(selectedSlots.contains(slot) ? Color.white : .black.opacity(0.65), lineWidth: selectedSlots.contains(slot) ? 2 : 1) }
            .overlay {
                if connectionCount > 1 {
                    Circle().stroke(.white, lineWidth: 2).frame(width: 17, height: 17)
                }
            }
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
                    DragGesture(coordinateSpace: .global)
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
                .highPriorityGesture(
                    TapGesture().onEnded { onSelectConnectionPoint(slot) },
                    including: connectionMode || connectionMoveMode ? .all : .gesture
                )
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
            // Wider than the 18pt visual dot — a mouse pointer on Mac needs more room than a fingertip.
            return Circle().path(in: CGRect(x: rect.midX - 16, y: rect.midY - 16, width: 32, height: 32))
        }
        if isCompact {
            return Circle().path(in: CGRect(x: rect.midX - 20, y: rect.midY - 20, width: 40, height: 40))
        }
        return RoundedRectangle(cornerRadius: 10).path(in: CGRect(x: rect.midX - 38, y: rect.midY - 34, width: 76, height: 68))
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
    var onTapAt: ((CGPoint) -> Void)? = nil
    var body: some View {
        path.stroke(Color.white.opacity(0.001), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
            .contentShape((hitPath ?? path).strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)))
            .onTapGesture(perform: onTap)
            .onTapGesture(count: 2, perform: onDoubleTap)
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { value in onTapAt?(value.location) })
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global).onChanged { value in onDrag(value.translation) }.onEnded { _ in onEndDrag() })
    }
}

private struct GridBackground: View {
    let color: Color
    var body: some View {
        // Grid lines temporarily removed: couldn't cover the full pannable canvas without
        // exceeding Metal's max texture size (see repo memory), leaving a partial/lopsided grid.
        color
    }
}

/// Custom vector-drawn ANSI/IEEE-style electrical schematic symbols, replacing generic SF Symbol icons.
private struct SchematicSymbolView: View {
    let kind: TargetKind
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, _ in
                    let lineWidth = max(1.5, min(size.width, size.height) * 0.09)
                    context.stroke(strokePath(in: size), with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    if let fill = fillPath(in: size) {
                        context.fill(fill, with: .color(color))
                    }
                }
                if let letter = letterLabel {
                    Text(letter)
                        .font(.system(size: min(size.width, size.height) * (letter.count > 1 ? 0.3 : 0.42), weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
        }
    }

    private var letterLabel: String? {
        switch kind {
        case .pt: return "PT"
        case .ct: return "CT"
        default: return nil
        }
    }

    private func fillPath(in size: CGSize) -> Path? {
        guard kind == .junction else { return nil }
        var path = Path()
        path.addEllipse(in: CGRect(x: 0.3 * size.width, y: 0.3 * size.height, width: 0.4 * size.width, height: 0.4 * size.height))
        return path
    }

    private func strokePath(in size: CGSize) -> Path {
        let w = size.width, h = size.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        var path = Path()
        switch kind {
        case .source:
            path.addEllipse(in: CGRect(x: 0.08 * w, y: 0.08 * h, width: 0.84 * w, height: 0.84 * h))
            path.move(to: pt(0.28, 0.55))
            path.addCurve(to: pt(0.5, 0.4), control1: pt(0.35, 0.35), control2: pt(0.42, 0.6))
            path.addCurve(to: pt(0.72, 0.55), control1: pt(0.58, 0.2), control2: pt(0.65, 0.75))
        case .transformer:
            path.addEllipse(in: CGRect(x: 0.12 * w, y: 0.2 * h, width: 0.4 * w, height: 0.6 * h))
            path.addEllipse(in: CGRect(x: 0.48 * w, y: 0.2 * h, width: 0.4 * w, height: 0.6 * h))
            path.move(to: pt(0.5, 0.12)); path.addLine(to: pt(0.5, 0.88))
        case .threePhaseTransformer:
            path.addEllipse(in: CGRect(x: 0.04 * w, y: 0.28 * h, width: 0.34 * w, height: 0.44 * h))
            path.addEllipse(in: CGRect(x: 0.33 * w, y: 0.28 * h, width: 0.34 * w, height: 0.44 * h))
            path.addEllipse(in: CGRect(x: 0.62 * w, y: 0.28 * h, width: 0.34 * w, height: 0.44 * h))
            path.move(to: pt(0.21, 0.1)); path.addLine(to: pt(0.21, 0.9))
            path.move(to: pt(0.5, 0.1)); path.addLine(to: pt(0.5, 0.9))
            path.move(to: pt(0.79, 0.1)); path.addLine(to: pt(0.79, 0.9))
        case .switchTarget:
            path.move(to: pt(0.5, 0.08)); path.addLine(to: pt(0.5, 0.42))
            path.move(to: pt(0.5, 0.58)); path.addLine(to: pt(0.5, 0.92))
            path.move(to: pt(0.5, 0.42)); path.addLine(to: pt(0.66, 0.24))
        case .fuse:
            path.addRoundedRect(in: CGRect(x: 0.2 * w, y: 0.32 * h, width: 0.6 * w, height: 0.36 * h), cornerSize: CGSize(width: 0.14 * w, height: 0.18 * h))
            path.move(to: pt(0.06, 0.5)); path.addLine(to: pt(0.94, 0.5))
        case .recloser:
            path.addEllipse(in: CGRect(x: 0.06 * w, y: 0.06 * h, width: 0.88 * w, height: 0.88 * h))
            path.move(to: pt(0.5, 0.3)); path.addLine(to: pt(0.68, 0.5)); path.addLine(to: pt(0.5, 0.7)); path.addLine(to: pt(0.32, 0.5)); path.closeSubpath()
        case .pt:
            path.addEllipse(in: CGRect(x: 0.18 * w, y: 0.18 * h, width: 0.64 * w, height: 0.64 * h))
            path.move(to: pt(0.5, 0.04)); path.addLine(to: pt(0.5, 0.18))
            path.move(to: pt(0.5, 0.82)); path.addLine(to: pt(0.5, 0.96))
        case .ct:
            path.addEllipse(in: CGRect(x: 0.18 * w, y: 0.18 * h, width: 0.64 * w, height: 0.64 * h))
            path.move(to: pt(0.04, 0.5)); path.addLine(to: pt(0.96, 0.5))
        case .ground:
            path.move(to: pt(0.5, 0.08)); path.addLine(to: pt(0.5, 0.5))
            path.move(to: pt(0.22, 0.5)); path.addLine(to: pt(0.78, 0.5))
            path.move(to: pt(0.32, 0.65)); path.addLine(to: pt(0.68, 0.65))
            path.move(to: pt(0.42, 0.8)); path.addLine(to: pt(0.58, 0.8))
        case .capacitor:
            path.move(to: pt(0.08, 0.5)); path.addLine(to: pt(0.42, 0.5))
            path.move(to: pt(0.58, 0.5)); path.addLine(to: pt(0.92, 0.5))
            path.move(to: pt(0.42, 0.22)); path.addLine(to: pt(0.42, 0.78))
            path.move(to: pt(0.58, 0.22)); path.addLine(to: pt(0.58, 0.78))
        case .junction:
            path.addEllipse(in: CGRect(x: 0.3 * w, y: 0.3 * h, width: 0.4 * w, height: 0.4 * h))
        }
        return path
    }
}

private struct EditorButtonStyle: ButtonStyle {
    var isActive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.95, weight: .semibold))
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
    func inspectorLabel() -> some View { font(.system(size: 11.5, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.4)) }

    /// Exactly one single-tap recognizer, never both -- attaching a plain onTapGesture AND a
    /// highPriorityGesture tap to the same view made click recognition unreliable on Mac.
    @ViewBuilder
    func singleTapToSelect(isJunction: Bool, action: @escaping () -> Void) -> some View {
        onTapGesture(perform: action)
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
    
    init?(hex: String?) {
        guard let hex = hex, !hex.isEmpty else { return nil }
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
