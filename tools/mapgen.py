#!/usr/bin/env python3
"""Generates + validates the facility layout (scripts/map_data.gd).

Cells are 3 m. '#' = solid. Floor themes (lowercase): . corridor, c containment,
o office, s server, k control, w warehouse, e medical, h hub, g generator, d dorm,
n6 096 chamber (uses 'v'), 049 chamber (uses 'q').
Markers (placed on floor, theme inferred from neighbours):
 P player, 1 SCP-173, 6 SCP-096, 4 SCP-049, z zombie, a ammo, b battery, + medkit,
 N code note spot, K keypad, x crate, f cabinet, t desk, S server rack, C console,
 T tank, B bed, L lamp-less (dark) corridor cell
Doors: D normal door, H heavy door (placed in wall ring cells).
"""
import collections, sys

W, H = 39, 25
CORR_X = [9, 19, 29]
CORR_Y = [8, 16]
BX = [(1, 8), (10, 18), (20, 28), (30, 37)]
BY = [(1, 7), (9, 15), (17, 23)]

g = [["#"] * W for _ in range(H)]

# corridors (some segments removed for a less regular maze)
for y in CORR_Y:
    for x in range(1, W - 1):
        g[y][x] = "."
for x in CORR_X:
    for y in range(1, H - 1):
        g[y][x] = "."
# remove a few segments
for (x0, x1, y) in [(30, 37, 16)]:
    for x in range(x0, x1 + 1):
        g[y][x] = "#"
for (x, y0, y1) in [(29, 17, 23), (9, 1, 7)]:
    for y in range(y0, y1 + 1):
        g[y][x] = "#"
# short extra corridor stubs
for y in range(17, 24):
    g[y][38 - 1] = "#"

THEME = {
    (0, 0): "c", (1, 0): "o", (2, 0): "s", (3, 0): "k",
    (0, 1): "w", (1, 1): "e", (2, 1): "h", (3, 1): "o",
    (0, 2): "d", (1, 2): "g", (2, 2): "q", (3, 2): "v",
}


def room(bx, by):
    (x0, x1), (y0, y1) = BX[bx], BY[by]
    # shrink toward corridors (leave 1 wall cell where a corridor is adjacent)
    ix0 = x0 + (1 if g[(y0 + y1) // 2][x0 - 1] == "." else 0)
    ix1 = x1 - (1 if x1 + 1 < W and g[(y0 + y1) // 2][x1 + 1] == "." else 0)
    iy0 = y0 + (1 if g[y0 - 1][(x0 + x1) // 2] == "." else 0)
    iy1 = y1 - (1 if y1 + 1 < H and g[y1 + 1][(x0 + x1) // 2] == "." else 0)
    return ix0, ix1, iy0, iy1


ROOMS = {}
for (bx, by), th in THEME.items():
    ix0, ix1, iy0, iy1 = room(bx, by)
    ROOMS[(bx, by)] = (ix0, ix1, iy0, iy1)
    for y in range(iy0, iy1 + 1):
        for x in range(ix0, ix1 + 1):
            g[y][x] = th


def put(x, y, ch):
    assert g[y][x] not in "#", (x, y, ch, g[y][x])
    g[y][x] = ch


def door(x, y, ch="D"):
    assert g[y][x] == "#", ("door not in wall", x, y)
    g[y][x] = ch


# ---- doors (in wall ring cells) ----
for x, y, ch in [
    (4, 7, "H"),                      # SCP-173 chamber
    (14, 7, "D"), (18, 3, "D"),       # offices A
    (24, 7, "D"), (20, 4, "D"),       # server room
    (30, 4, "H"),                     # control room (only entrance)
    (8, 12, "D"), (4, 9, "D"), (4, 15, "D"),     # warehouse
    (14, 9, "D"), (18, 12, "D"),                 # medical
    (20, 12, "D"), (24, 15, "D"), (28, 12, "D"), # hub
    (30, 12, "D"), (34, 9, "D"),                 # offices B
    (33, 16, "H"),                    # offices B <-> SCP-096 chamber
    (8, 20, "D"), (4, 17, "D"),       # dorm (start)
    (14, 17, "D"), (18, 21, "D"),     # generator
    (24, 17, "H"), (20, 20, "D"),     # SCP-049 chamber
    (29, 20, "H"),                    # SCP-049 <-> SCP-096 chamber
]:
    door(x, y, ch)

# ---- markers ----
M = [
    # dorm (start)
    (3, 21, "P"), (1, 18, "B"), (2, 18, "B"), (6, 18, "B"), (7, 18, "B"), (1, 23, "B"), (6, 23, "B"),
    (7, 22, "a"), (1, 20, "N"),
    # SCP-173 chamber
    (4, 2, "1"), (1, 1, "x"), (8, 1, "x"), (8, 6, "N"), (1, 6, "b"),
    # offices A
    (11, 2, "t"), (13, 2, "t"), (15, 2, "t"), (11, 5, "t"), (16, 5, "t"), (10, 6, "f"), (17, 1, "f"),
    (13, 4, "N"), (10, 3, "a"), (17, 6, "+"),
    # server room
    (22, 1, "S"), (23, 1, "S"), (25, 1, "S"), (26, 1, "S"), (22, 3, "S"), (23, 3, "S"), (25, 3, "S"),
    (26, 3, "S"), (27, 5, "N"), (21, 6, "b"), (27, 1, "a"),
    # control room
    (33, 1, "C"), (34, 1, "C"), (35, 1, "K"), (36, 1, "C"), (37, 1, "C"), (37, 4, "C"), (37, 5, "C"),
    (33, 6, "+"),
    # warehouse
    (1, 10, "x"), (2, 10, "x"), (1, 11, "x"), (6, 10, "x"), (6, 14, "x"), (7, 14, "x"), (2, 13, "x"),
    (1, 14, "N"), (7, 11, "a"), (1, 12, "a"), (3, 12, "b"), (6, 12, "z"),
    # medical bay
    (11, 10, "B"), (11, 12, "B"), (11, 14, "B"), (13, 14, "B"), (17, 10, "f"), (16, 14, "+"), (12, 10, "+"),
    (15, 12, "N"), (13, 12, "z"),
    # hub / cafeteria
    (22, 11, "t"), (22, 13, "t"), (26, 11, "t"), (26, 13, "t"), (24, 12, "N"), (21, 14, "a"),
    (27, 10, "z"), (23, 10, "z"),
    # offices B
    (32, 11, "t"), (36, 11, "t"), (32, 14, "t"), (36, 14, "t"), (37, 10, "f"), (37, 15, "f"),
    (35, 13, "N"), (37, 12, "b"), (31, 10, "z"),
    # generator room
    (11, 18, "T"), (11, 20, "T"), (11, 22, "T"), (16, 23, "x"), (17, 18, "x"), (15, 20, "N"),
    (13, 23, "a"), (12, 21, "b"), (14, 22, "z"),
    # SCP-049 chamber
    (24, 21, "4"), (21, 18, "x"), (28, 23, "x"), (28, 18, "N"), (22, 23, "a"), (26, 19, "z"),
    # SCP-096 chamber
    (36, 22, "6"), (37, 18, "x"), (31, 18, "x"), (31, 23, "N"), (37, 23, "a"),
    # corridors
    (19, 5, "a"), (1, 16, "a"), (37, 8, "a"), (9, 23, "a"), (19, 20, "b"), (9, 13, "+"),
    (29, 3, "z"), (12, 8, "z"), (34, 8, "z"), (19, 22, "z"), (6, 16, "z"),
]
for x, y, ch in M:
    put(x, y, ch)

# dark (broken light) corridor cells
for x, y in [(1, 8), (2, 8), (3, 8), (9, 18), (9, 19), (19, 1), (19, 2), (29, 8), (30, 8), (31, 8),
             (19, 10), (19, 11), (26, 16), (27, 16), (28, 16), (9, 22)]:
    if g[y][x] == ".":
        g[y][x] = "L"

rows = ["".join(r) for r in g]

# ---- validation ----
FLOOR = set(".cowskehgdqvLPN146zab+KxftSCTBDH")
WALK_BLOCK = set("xfSCTKB")  # props occupying a cell


def walk(x, y):
    return rows[y][x] in FLOOR and rows[y][x] not in WALK_BLOCK


# doors: two opposite walkable neighbours, other two solid
for y in range(H):
    for x in range(W):
        if rows[y][x] in "DH":
            ns = walk(x, y - 1) and walk(x, y + 1)
            ew = walk(x - 1, y) and walk(x + 1, y)
            solid_ns = rows[y - 1][x] == "#" and rows[y + 1][x] == "#"
            solid_ew = rows[y][x - 1] == "#" and rows[y][x + 1] == "#"
            assert (ns and solid_ew) or (ew and solid_ns), ("bad door", x, y)
# connectivity
start = next((x, y) for y in range(H) for x in range(W) if rows[y][x] == "P")
seen = {start}
q = collections.deque([start])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and walk(nx, ny):
            seen.add((nx, ny))
            q.append((nx, ny))
unreach = [(x, y, rows[y][x]) for y in range(H) for x in range(W) if walk(x, y) and (x, y) not in seen]
assert not unreach, unreach
# all prop cells adjacent to something reachable
cnt = collections.Counter("".join(rows))
print("\n".join(rows))
print({k: v for k, v in cnt.items() if k in "PN146zab+KDH"})

out = "# AUTO-GENERATED by tools/mapgen.py - do not edit by hand\nextends RefCounted\nclass_name MapData\n\nconst LAYOUT: PackedStringArray = [\n"
out += "".join('\t"%s",\n' % r for r in rows)
out += "]\n"
open(sys.argv[1] if len(sys.argv) > 1 else "scripts/map_data.gd", "w").write(out)
