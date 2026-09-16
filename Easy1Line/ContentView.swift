//
//  ContentView.swift
//  Easy1Line
//
//  Created by Mike Mazzantini on 9/16/26.
//

import SwiftUI

struct ContentView: View {
    @State private var nodes: [SchematicNode] = [
        SchematicNode(kind: .source, position: CGPoint(x: 330, y: 270)),
        SchematicNode(kind: .load, position: CGPoint(x: 650, y: 430))
    ]
    @State private var segments: [SchematicSegment] = []
    @State private var canvasOffset = CGSize.zero
    @State private var panStart = CGSize.zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var selectedNodeID: UUID?
    @State private var connectionStartID: UUID?
    @State private var showInspector = false

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

            if showInspector, let selectedNode {
                inspector(for: selectedNode)
                    .padding(.trailing, 20)
                    .padding(.top, 84)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedNode: SchematicNode? {
        guard let selectedNodeID else { return nil }
        return nodes.first { $0.id == selectedNodeID }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EASY / ONE LINE")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(1.5)
                Text("Untitled schematic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Button {
                addNode(.junction)
            } label: {
                Label("Add junction", systemImage: "plus.circle")
            }
            .buttonStyle(EditorButtonStyle())

            Button {
                connectionStartID = nil
            } label: {
                Label(connectionStartID == nil ? "Connect" : "Connecting", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(EditorButtonStyle(isActive: connectionStartID != nil))

            Button {
                showInspector.toggle()
            } label: {
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
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPONENTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))

            ForEach(NodeKind.palette) { kind in
                PaletteItem(kind: kind)
                    .draggable(kind.rawValue)
                    .onTapGesture {
                        addNode(kind)
                    }
            }

            Divider()
                .overlay(.white.opacity(0.12))
                .padding(.vertical, 4)

            Text("Drag to place\nTap to add at center")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 158)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func schematicCanvas(in size: CGSize) -> some View {
        ZStack {
            GridBackground()
                .contentShape(Rectangle())
                .gesture(panGesture)

            Canvas { context, _ in
                for segment in segments {
                    guard let start = node(with: segment.startID), let end = node(with: segment.endID) else { continue }
                    let path = orthogonalPath(from: start.position, to: end.position)
                    context.stroke(path, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(.cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(false)

            ForEach(nodes) { node in
                NodeView(node: node, isSelected: node.id == selectedNodeID, isConnectionStart: node.id == connectionStartID)
                    .position(node.position)
                    .gesture(nodeDragGesture(for: node, canvasSize: size))
                    .onTapGesture {
                        nodeTapped(node)
                    }
            }
        }
        .offset(canvasOffset)
        .dropDestination(for: String.self) { items, location in
            guard let rawKind = items.first, let kind = NodeKind(rawValue: rawKind) else { return false }
            let worldPoint = CGPoint(x: location.x - canvasOffset.width, y: location.y - canvasOffset.height)
            nodes.append(SchematicNode(kind: kind, position: worldPoint))
            return true
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                canvasOffset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
            }
            .onEnded { _ in
                panStart = canvasOffset
            }
    }

    private func nodeDragGesture(for node: SchematicNode, canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard connectionStartID == nil else { return }
                guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }
                if dragStartPositions[node.id] == nil {
                    dragStartPositions[node.id] = nodes[index].position
                }
                guard let startPosition = dragStartPositions[node.id] else { return }
                nodes[index].position = CGPoint(x: startPosition.x + value.translation.width, y: startPosition.y + value.translation.height)
                selectedNodeID = node.id
            }
            .onEnded { _ in
                dragStartPositions.removeValue(forKey: node.id)
                snapNode(node.id, canvasSize: canvasSize)
            }
    }

    private func nodeTapped(_ node: SchematicNode) {
        if let connectionStartID, connectionStartID != node.id {
            if !segments.contains(where: { ($0.startID == connectionStartID && $0.endID == node.id) || ($0.startID == node.id && $0.endID == connectionStartID) }) {
                segments.append(SchematicSegment(startID: connectionStartID, endID: node.id))
            }
            self.connectionStartID = nil
        } else {
            selectedNodeID = node.id
            connectionStartID = connectionStartID == node.id ? nil : node.id
        }
    }

    private func snapNode(_ id: UUID, canvasSize: CGSize) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position.x = min(max(nodes[index].position.x, 180), max(180, canvasSize.width - 80))
        nodes[index].position.y = min(max(nodes[index].position.y, 120), max(120, canvasSize.height - 80))
    }

    private func addNode(_ kind: NodeKind) {
        nodes.append(SchematicNode(kind: kind, position: CGPoint(x: 480 - canvasOffset.width, y: 330 - canvasOffset.height)))
        selectedNodeID = nodes.last?.id
    }

    private func node(with id: UUID) -> SchematicNode? {
        nodes.first { $0.id == id }
    }

    private func orthogonalPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        let midpointX = (start.x + end.x) / 2
        path.move(to: start)
        path.addLine(to: CGPoint(x: midpointX, y: start.y))
        path.addLine(to: CGPoint(x: midpointX, y: end.y))
        path.addLine(to: end)
        return path
    }

    private func inspector(for node: SchematicNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELECTED")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.4))
            HStack {
                Image(systemName: node.kind.symbol)
                    .foregroundStyle(node.kind.color)
                Text(node.kind.title)
                    .font(.headline)
                Spacer()
                Button {
                    segments.removeAll { $0.startID == node.id || $0.endID == node.id }
                    nodes.removeAll { $0.id == node.id }
                    selectedNodeID = nil
                    connectionStartID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red.opacity(0.8))
            }
            Text("Tap another icon to connect")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(16)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SchematicNode: Identifiable {
    let id = UUID()
    let kind: NodeKind
    var position: CGPoint
}

private struct SchematicSegment: Identifiable {
    let id = UUID()
    let startID: UUID
    let endID: UUID
}

private enum NodeKind: String, CaseIterable, Identifiable {
    case source
    case load
    case switchNode
    case junction

    static let palette: [NodeKind] = [.source, .load, .switchNode]
    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .load: return "Load"
        case .switchNode: return "Switch"
        case .junction: return "Junction"
        }
    }

    var symbol: String {
        switch self {
        case .source: return "bolt.fill"
        case .load: return "lightbulb.fill"
        case .switchNode: return "switch.2"
        case .junction: return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .source: return .orange
        case .load: return .yellow
        case .switchNode: return .mint
        case .junction: return .cyan
        }
    }
}

private struct PaletteItem: View {
    let kind: NodeKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind.color)
                .frame(width: 24)
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct NodeView: View {
    let node: SchematicNode
    let isSelected: Bool
    let isConnectionStart: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.10, green: 0.14, blue: 0.16))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected || isConnectionStart ? node.kind.color : .white.opacity(0.18), lineWidth: isSelected || isConnectionStart ? 2 : 1)
                Image(systemName: node.kind.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(node.kind.color)
            }
            .frame(width: 58, height: 48)

            Text(node.kind.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(width: 92, height: 76)
        .contentShape(Rectangle())
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 32
            var path = Path()
            stride(from: 0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }
        .background(Color(red: 0.07, green: 0.09, blue: 0.105))
    }
}

private struct EditorButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? .cyan : .white.opacity(0.82))
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(isActive ? .cyan.opacity(0.12) : .white.opacity(configuration.isPressed ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? .cyan.opacity(0.45) : .white.opacity(0.1), lineWidth: 1)
            }
    }
}

#Preview {
    ContentView()
}
