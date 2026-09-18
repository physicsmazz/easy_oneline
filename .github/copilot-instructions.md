# Easy1Line project rules

## Wire routing

- Default wires must use the fewest possible orthogonal bends.
- A clear connection should be straight when possible, or use one bend when one bend is sufficient.
- Add additional interior bends only when a component actually blocks the simpler route and the wire must route around it.
- Do not create interior junctions, connection points, or split wire segments automatically.
- Preserve a deliberate wire route only when the user explicitly drags the wire or places a component onto the wire to create that connection.
- Do not reintroduce the old unconditional midpoint dogleg route.
