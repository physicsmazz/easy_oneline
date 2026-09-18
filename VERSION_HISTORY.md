# Easy1Line Version History

## 0.11.1

- Added automatic 180-degree component orientation when a new connection benefits from reversing the component.
- Orientation is applied only when the connected-pin alignment improves.
- Junctions are not automatically rotated.

Release commit: `dd3b115`

## 0.11.0

- Added document version history.
- Users can save named document snapshots with a description.
- Each version stores the document data, timestamp, and user name.
- Added a version history panel for recalling saved snapshots.
- Recalled versions remain in the existing saved-document library.

Release commit: `212a2b6`

## 0.10.2

- Refined wire dragging around endpoint stubs.
- Kept the stationary trunk fixed while an endpoint stub expands or contracts.
- Reduced premature obstacle routing caused by excessive clearance.

Release commit: `a5ba9d9`

## 0.10.1

- Changed routing clearance to explicit canvas-pixel units instead of mixing wire display points with routing distance.
- Fixed premature wire bends caused by overly large obstacle clearance.

Release commit: `f9f3940`

## 0.10.0

- Added obstacle-aware wire bends when dragging wires around components.
- Preserved endpoint pin stubs while creating detours.
- Removed unused routing code from earlier experiments.

Release commit: `5897620`

## 0.9.4

- Replaced the old midpoint dogleg with shortest clear one-bend routing.
- Added obstacle-only detours through the orthogonal pathfinder.
- Normalized dragged routes and removed redundant collinear interior points.
- Added project instructions documenting the minimum-bend and stub-routing rules.

Release commit: `0f99918`

## 0.9.3

- Established the 0.9.3 project version baseline.
- Preserved minimum endpoint stubs on newly created wires.

Version commit: `3b4b782`
