# Spherical World & Navigation — Current Reference

> **Status:** ACTIVE REFERENCE (2026-11-14). This replaces the 2026-09-06
> draft. The spherical world is shipped: the code and its probes are the
> truth, and this page records the conventions they use.
>
> **Execution record:** [`prd-spherical-mvp.md`](./prd-spherical-mvp.md)
> (waves, locked decisions, pickup protocol).
> **Topology:** [`prd-world.md`](./prd-world.md).
> **Addressing:** [`prd-geometry.md`](./prd-geometry.md).
> **Math:** `game/core/frame/math/spherical.gd` (cited as §8 formulas and §9
> constants).

---

## 1. What is live

- **One sphere, 20 km radius for v1.** The live world is spherical; the
  clipmap renders the ground and the walk surface samples the analytic
  terrain law.
- **Positions are Vector3 metres.** Latitude and longitude are derived for
  navigation, maps, and authored data, not stored as the primary position.
- **Gravity is radial on the globe.** It is quarantined to the spherical
  ground path. Instances (arena, duel, dungeon) keep planar AABB geometry and
  vanilla -Y gravity.
- **Navigation primitives ship:** haversine distance, initial geodesic
  bearing, great-circle interpolation, spherical/cartesian conversion,
  compass bearing, waypoints, world map, and minimap.

| Surface | Code |
| --- | --- |
| Spherical math | `game/core/frame/math/spherical.gd` |
| Icosahedral addressing | `game/core/frame/math/icosahedral.gd`, `nsc9.gd` |
| Globe / clipmap | `game/scenes/worlds/globe_world.tscn`, `globe_clipmap.gd` |
| Compass | `game/ui/components/compass.gd` |
| World map / minimap | `game/ui/components/world_map.gd`, `minimap.gd` |
| Waypoints | `game/core/services/waypoint_service.gd` |

---

## 2. Coordinate convention

### 2.1 Units and storage

World positions are `Vector3(x, y, z)` in integer metres. `y` is the north
pole axis. Altitude is metres above the mean sphere; a position length of
`PLANET_RADIUS_METERS + alt` is the radius at that point.

### 2.2 Latitude and longitude

- Latitude: `-90` (south pole) to `+90` (north pole), degrees.
- Longitude: `-180` to `+180`, degrees; `0` is the prime meridian.
- Lat/lon are derived from the position for navigation and authored anchors.
  They are not a second source of truth.

### 2.3 Axis convention

`+Y` points at the north pole. At `lat = 0, lon = 0` the position is
`(R, 0, 0)`; increasing longitude rotates toward `+Z`. The icosahedral
projection uses the same convention.

### 2.4 Conversions

```gdscript
# Spherical (degrees + altitude above surface) -> Cartesian metres.
func spherical_to_cartesian(lat: float, lon: float, alt: float = 0.0,
        radius: float = PLANET_RADIUS_METERS) -> Vector3:
    var r := radius + alt
    var phi := deg_to_rad(90.0 - lat)   # polar angle from +Y
    var theta := deg_to_rad(lon)
    return Vector3(
        r * sin(phi) * cos(theta),
        r * cos(phi),
        r * sin(phi) * sin(theta)
    )

# Cartesian metres -> Vector2(lat, lon) degrees. Altitude is projected out.
func cartesian_to_spherical(pos: Vector3,
        radius: float = PLANET_RADIUS_METERS) -> Vector2:
    var r := pos.length()
    if r < 0.0000001:
        return Vector2.ZERO
    var lat := 90.0 - rad_to_deg(acos(clampf(pos.y / r, -1.0, 1.0)))
    var lon := rad_to_deg(atan2(pos.z, pos.x))
    return Vector2(lat, lon)
```

### 2.5 Convention summary

`phi = 90 - lat` (polar angle), `theta = lon`, `+Y` is the north pole axis.
This is the convention `spherical.gd` implements and the icosahedral
projection expects. The `radius` parameter defaults to the v1 planet radius;
`Earth` values are only for known-answer tests.

---

## 3. Navigation

### 3.1 Distance

`Spherical.haversine(lat1, lon1, lat2, lon2)` returns metres along the
great-circle surface. It accepts an optional radius; the default is the v1
planet. Distances are shape-gated: spherical worlds measure great-circle,
planar instances keep Euclidean distance.

### 3.2 Bearing

`Spherical.geodesic_bearing` returns the initial bearing in degrees,
`0 = north`, `90 = east`, normalized to `[0, 360)`. Coincident points return
`0`. The compass reads true north, not a magnetic model.

### 3.3 Great-circle path

`Spherical.great_circle_intermediate` returns `Vector2(lat, lon)` at fraction
`f` along the great circle. It is used for curved waypoint guides and map
paths. Antipodal paths are degenerate; `f = 0` or a near-zero angular
distance returns the first point.

### 3.4 Waypoints

`WaypointService` stores world positions and displays great-circle distance
and bearing on spherical worlds. The compass and minimap consume the same
bearing law. Waypoint activation and routing are service concerns, not a
separate spherical coordinate system.

### 3.5 Map and minimap

The map surfaces are `ui/components/world_map.gd` and `minimap.gd`. The map
is north-up and uses the shared `lat_lon_to_uv` projection for authored
landmarks. Local zoom may treat curvature as negligible; regional and global
views use the sphere projection rather than a flat world image.

---

## 4. Zones and instances

- Open-world zones are contiguous geographic regions. Zone boundaries are
  data lines used for rules (PvP mode, level gates, spawn ownership, quest
  credit), not loading screens.
- Movement between distant places is explicit: waypoint gateways, ferries,
  and instance portals.
- Arenas, duels, and dungeons are separate planar scopes. They do not use the
  icosahedral mesh or radial gravity. See `core/schemas/instance_contract.gd`
  and [`prd-world.md`](./prd-world.md) §2c.

---

## 5. Implementation status

| System | Status | Receipt / code |
| --- | --- | --- |
| Haversine, bearing, intermediate point, conversions | SHIPPED | `core/frame/math/spherical.gd`; `test_spherical.gd` |
| Icosahedral addressing + NSC-9 | SHIPPED | `core/frame/math/icosahedral.gd`, `nsc9.gd`; probes |
| Streamed globe / clipmap ground | SHIPPED | `globe_world.tscn`, `globe_clipmap.gd`; `probe_globe_world.gd` |
| Radial gravity and curved walk | SHIPPED | globe body path; spherical MVP S3 |
| True-north compass and great-circle waypoints | SHIPPED | `compass.gd`, `waypoint_service.gd` |
| World map / minimap | SHIPPED | `world_map.gd`, `minimap.gd`; wiring receipt |
| Polar caps | SHIPPED (v12) | `probe_polar_caps.gd` |
| Planet-wide flyover rendering | OPEN | see [`prd-terrain.md`](./prd-terrain.md) §6 |
| Floating islands | DESIGNED, NOT BUILT | see [`prd-terrain.md`](./prd-terrain.md) §6 |

The legacy icosahedral terrain streamer is deleted. The clipmap is the sole
renderer; `globe_world.terrain_render` is a compatibility read that warns and
falls back to `clipmap`.

---

## 6. Historical gaps (pre-globe snapshot)

The original §6 checklist was written before the globe shipped. It is kept
only as history; §5 is the current status. The retired list included
"icosahedral mesh implementation", "NSC-9 integration", "globe view", and
"full spherical collision/physics" as open items. All four shipped in the
spherical MVP and the globe rounds. Do not re-open them from this section.

---

## 7. Feature matrix

| System | Current state |
| --- | --- |
| Position storage | `Vector3` metres; lat/lon derived |
| Distance | Haversine on spherical worlds; Euclidean in planar instances |
| Compass bearing | Geodesic, true north |
| Minimap zoom | Local flat approximation; regional/global sphere projection |
| World map | North-up map using shared lat/lon projection |
| Waypoints | Great-circle distance and bearing |
| Zone transitions | Seamless open world; explicit gateways/portals for jumps and instances |
| North indicator | True north |

---

## 8. Key formulas

These are the formulas `spherical.gd` implements. Angles are radians in the
math; inputs and outputs are degrees at the API boundary.

### 8.1 Haversine distance

```
phi1, phi2 = lat1, lat2 in radians
dphi = phi2 - phi1
dlmb = lon2 - lon1 in radians
a = sin²(dphi/2) + cos(phi1) * cos(phi2) * sin²(dlmb/2)
c = 2 * atan2(sqrt(a), sqrt(1 - a))
d = R * c
```

### 8.2 Initial geodesic bearing

```
y = sin(dlmb) * cos(phi2)
x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dlmb)
theta = atan2(y, x)
bearing = degrees(theta) normalized to [0, 360)
```

### 8.3 Intermediate point

```
d = angular distance between the points (radians)
A = sin((1 - f) * d) / sin(d)
B = sin(f * d) / sin(d)
x = A * cos(phi1) * cos(lmb1) + B * cos(phi2) * cos(lmb2)
y = A * cos(phi1) * sin(lmb1) + B * cos(phi2) * sin(lmb2)
z = A * sin(phi1) + B * sin(phi2)
lat = atan2(z, sqrt(x² + y²))
lon = atan2(y, x)
```

The old draft's §8.3 printed a malformed planar interpolation. The form
above is the spherical one the code uses.

---

## 9. Constants

```gdscript
const PLANET_RADIUS_METERS: float = 20000.0       # v1 game planet
const EARTH_RADIUS_METERS: float = 6371000.0      # known-answer tests only

# Derived at the v1 radius:
# circumference          = TAU * R          = 125,663.706 m
# metres per degree lat  = R * PI / 180     = 349.066 m
# metres per degree lon  = 349.066 * cos(lat)
```

`111,320 m/degree` is an Earth constant. It is not the game's scale and must
not be used for v1 distances. The old draft's `PLANET_CIRCUMFERENCE_METERS`
(40,075 km) and `DEGREE_LAT_TO_METERS` (111,320 m) were Earth values; they are
retired.

For a different radius, derive the values from `R`; do not copy the v1
constants into a world with another radius. `Spherical.haversine` and the
conversion functions accept a `radius` argument for that reason.

---

## 10. Decisions (resolved)

| Question | Decision |
| --- | --- |
| Store position as Vector3 or lat/lon? | `Vector3` metres is primary; lat/lon is derived. |
| Prime meridian? | `lon = 0` at the `+X` axis. |
| Map orientation? | North-up. |
| Multiple planets? | One live planet plus the moon as a separate world scene. |
| Wrap at ±180°? | Trigonometry handles it; no special longitude wrap branch. |
| Seamless zones or loading screens? | Seamless on the open world; explicit gateways/portals for jumps and instances. |
| Planet radius? | 20 km for v1. |

---

## 11. Sources

- [`prd-spherical-mvp.md`](./prd-spherical-mvp.md) — execution record and locked decisions.
- [`prd-world.md`](./prd-world.md) — planet topology and zone law.
- [`prd-geometry.md`](./prd-geometry.md) — NSC-9 and icosahedral addressing.
- [`prd-terrain.md`](./prd-terrain.md) — ground law and open build items.
- `game/core/frame/math/spherical.gd` — the canonical math.
