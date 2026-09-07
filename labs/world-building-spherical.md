# Synmergia — Spherical World & Navigation PRD

> **Status:** Draft — 2026-09-06
> **Updated:** 2026-09-07 to align with world-building.md
> **Sources:** [`world-building.md`](../world-building.md), [`world-building-arch.md`](./world-building-arch.md)
> **Purpose:** Design for spherical planet map and navigation systems

---

## 1. Overview

Synmergia uses an **icosahedral** geometric addressing layer on top of a
spherical planet. This document outlines:

1. **Spherical Coordinates** — How position is stored and calculated on a sphere
2. **Icosahedral Mesh** — The address space for spherical worlds
3. **Navigation Systems** — How map/minimap/compass work on a sphere
4. **Zone System** — How zones map to spherical regions
5. **Implementation Gaps** — What needs to be built

**Key reference from world-building.md:**
- World coordinates are integer meters in a fixed unit
- Shape: "planar" | "spherical" in world config
- Chunk size: ~64m edge length for spherical

---

## 2. Spherical World Design (per world-building.md)

### 2.1 Coordinate System

**World Coordinate (W):**
```
Position: Vector3(x, y, z) in integer meters
- Shape-agnostic, fixed unit system
- Internal representation doesn't change between planar/spherical
```

**Spherical projection:**
```
Quantize(W, chunk_size_m) on icosahedral mesh
→ Triangular cell on subdivided icosahedron
```

### 2.2 Icosahedral Mesh (per world-building.md §3.5)

The icosahedron IS the address space:
- **20 triangular faces** base
- **Subdivision level** = chunk size (~64m edge for Earth-sized planet)
- Each face subdivided into triangular cells
- Vertex = address `(face_id, u, v)` or `(x_cell, y_cell, z_cell)`

```
Earth-sized planet (radius 6,371 km):
- Edge length: ~62m per subdivision level
- One icosahedron subdivision = one chunk

Game-scale planet (radius 100 km, surface area 125,663 km²):
- ~500,000 chunks at 1-subdivision level
- ~125,000 chunks at 2-subdivision level
```

### 2.3 Planet Parameters (from world-building.md)

| Parameter | Value | Notes |
|-----------|-------|-------|
| Planet Radius | 6,371 km (Earth) or 100 km (game-scale) | Configurable |
| Chunk Size | ~64m edge length | Tunable per world |
| Starting Continent | Northern hemisphere | Future expansion |
| Vertical Axis | `y` (planar) or `z_cell` (spherical with face_id) | See §3.7 |

### 2.4 NSC-9 + Icosahedral (from world-building.md §6)

The geometric addressing layer combines:
- **NSC-9:** Integer lattice system for addressing
- **Icosahedral:** Triangular mesh for spherical projection
- **Quasicrystal:** Future Penrose tiling support

```
World → (face_id, u, v) → NSC-9 cell
                         ↓
                   Spherical projection
```

**Geo-cache:** Spatial index on Redis using NSC-9 + icosahedral cells
- ~5 bytes per key × 50,000 cached regions
- Fast spatial queries for nearby entities

### 2.5 Coordinate Conversion

```gdscript
# Spherical to Cartesian
func spherical_to_cartesian(lat: float, lon: float, alt: float) -> Vector3:
    var r := PLANET_RADIUS + alt
    var phi := deg_to_rad(90 - lat)  # polar angle
    var theta := deg_to_rad(lon)
    
    return Vector3(
        r * sin(phi) * cos(theta),
        r * cos(phi),
        r * sin(phi) * sin(theta)
    )

# Cartesian to Spherical
func cartesian_to_spherical(pos: Vector3) -> Dictionary:
    var r := pos.length()
    var lat := rad_to_deg(acos(pos.y / r)) - 90
    var lon := rad_to_deg(atan2(pos.z, pos.x))
    var alt := r - PLANET_RADIUS
    return {"lat": lat, "lon": lon, "alt": alt}
```

---

## 3. Navigation Systems

### 3.1 Compass on a Sphere

**Current:** Flat bearing (0-360° relative to player's facing)

**Spherical:**
- **True North** always points to geographic north pole
- Compass needle always points north
- Distance calculated as great-circle distance
- Bearing calculated as geodesic (great-circle) bearing

```gdscript
# Great-circle distance
func haversine_distance(pos1: Vector3, pos2: Vector3) -> float:
    var r := PLANET_RADIUS
    var d := pos1.normalized().dot(pos2.normalized())
    return r * acos(clamp(d, -1.0, 1.0))

# Geodesic bearing
func geodesic_bearing(from: Vector3, to: Vector3) -> float:
    var n_from := from.normalized()
    var n_to := to.normalized()
    var east := Vector3.UP.cross(n_from).normalized()
    var north := n_from.cross(east)
    return rad_to_deg(atan2(east.dot(n_to), north.dot(n_to)))
```

### 3.2 Minimap on a Sphere

**Current Issues:**
- Uses flat grid projection
- Doesn't account for curvature at world scale
- Zoom levels work for flat, need rethinking for sphere

**Requirements:**
- Local area zoom (10m-1km): Can use flat projection (curvature negligible)
- Regional zoom (10km+): Need equirectangular or Mercator projection
- Continental: Need curved map UI or globe view

**Proposed Zones:**
| Zoom Level | Radius | Projection |
|------------|--------|------------|
| Micro | 50m | Flat (negligible curvature) |
| Local | 500m | Flat with compass correction |
| Regional | 5km | Equirectangular |
| Continental | 50km+ | Globe or Mercator |

**Integration with NSC-9:**
- Use NSC-9 cells for spatial queries
- Redis geo-cache for nearby entity lookups
- LOD-aware marker culling

### 3.3 World Map

**Current:** Pan/zoom on flat image

**Spherical World Map:**
- Option A: 2D equirectangular projection (like real world maps)
- Option B: 3D globe that player can rotate
- Option C: Hybrid (2D with "globe" button)

**Per world-building.md:**
- World config: `shape: "planar" | "spherical"`
- Spherical: `spatial_partition: [lat_min, lon_min, lat_max, lon_max]`
- T3 state tree stores zone boundaries

---

## 4. Zone System for Spherical World

### 4.1 Zone Definitions

```gdscript
class Zone:
    var zone_id: String
    var bounds: SphereRegion  # lat/lon bounds
    var altitude_range: Vector2  # min/max altitude
    var zone_type: ZoneType  # continent, ocean, mountain, etc.
    var display_name: String

class SphereRegion:
    var lat_min: float  # -90 to 90
    var lat_max: float
    var lon_min: float  # -180 to 180
    var lon_max: float
```

### 4.2 Zone Transitions

Players transition zones based on:
1. **Geographic bounds** — Entering new lat/lon area
2. **Altitude** — Entering mountain/ocean zones
3. **Instance** — Dungeon portals, instanced areas

---

## 5. Waypoint System on Sphere

### 5.1 Current Features

- Create/delete waypoints at position
- Distance display
- Active waypoint tracking
- Quest waypoints

### 5.2 Spherical Enhancements Needed

| Feature | Implementation |
|---------|----------------|
| **Great-circle path** | Show curved line on minimap for distant waypoints |
| **Polar distance** | Haversine formula for accurate distances near poles |
| **North indicator** | Always show true north, not magnetic |
| **Altitude display** | Show if waypoint is significantly above/below player |
| **Zone boundary warning** | Alert when waypoint is in different zone |

### 5.3 Compass Behavior at Poles

**Problem:** At geographic north/south pole, longitude is undefined.

**Solution:**
```gdscript
func get_compass_direction_at_pole(player_pos: Vector3, waypoint: Vector3) -> String:
    var is_north_pole := player_pos.y > (PLANET_RADIUS * 0.99)
    var is_south_pole := player_pos.y < -(PLANET_RADIUS * 0.99)
    
    if is_north_pole:
        return "South" if waypoint.y < 0 else "North"
    if is_south_pole:
        return "North" if waypoint.y > 0 else "South"
    
    return normal_compass_direction(player_pos, waypoint)
```

---

## 6. Current Gaps & TODO

### 6.1 Immediate (Phase 1)

- [ ] Implement haversine distance function
- [ ] Compass: Add true-north bearing calculation
- [ ] Waypoint: Update distance calc to haversine
- [ ] NSC-9 cell calculation for position→cell mapping

### 6.2 Medium Term (Phase 2)

- [ ] Icosahedral mesh implementation (see `labs/multi-iso/`)
- [ ] NSC-9 integration with position system
- [ ] Regional map zoom with projection correction
- [ ] Globe view for world map
- [ ] Zone boundary transition handling (per world config)
- [ ] Redis geo-cache for spatial queries

### 6.3 Future (Phase 3)

- [ ] Full spherical collision/physics
- [ ] Atmosphere/fog at horizon
- [ ] Multi-icosahedron worlds (multiple planets)
- [ ] Orbital mechanics for moons (if any)

---

## 7. Feature Matrix

| System | Flat World | Spherical World | Status |
|--------|------------|----------------|--------|
| Position storage | Vector3 | Vector3 (on sphere) or lat/lon | ⚠️ Needs conversion |
| Distance calc | `distance()` | Haversine | ⚠️ TODO |
| Compass bearing | Euler angle | Geodesic bearing | ⚠️ TODO |
| Minimap zoom | Linear | Curvature-aware | ⚠️ TODO |
| World map | Flat image | 2D projection or globe | ⚠️ TODO |
| Waypoints | Flat distance | Great-circle | ⚠️ TODO |
| Zone transitions | Grid-based | Geographic bounds | ⚠️ TODO |
| North indicator | Player-relative | True north | ⚠️ TODO |

---

## 8. Key Formulas

### 8.1 Haversine Distance
```
a = sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlon/2)
c = 2 * atan2(√a, √(1-a))
d = R * c
```

### 8.2 Geodesic Bearing
```
θ = atan2(sin(Δlon) * cos(lat2), 
           cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(Δlon))
```

### 8.3 Intermediate Point
For waypoint pathfinding:
```
a = sin((1-f)/2) / sin(f/2)
b = sin(f/2) / sin(f)
x = a * cos(lat1) * cos(lon1*2) + b * cos(lat2) * cos(lon2)
```

---

## 9. Constants

```gdscript
const PLANET_RADIUS_METERS: float = 6371000.0
const PLANET_CIRCUMFERENCE_METERS: float = 40075000.0
const DEGREE_LAT_TO_METERS: float = 111320.0
const DEGREE_LON_AT_EQUATOR: float = 111320.0
const DEGREE_LON_AT_LAT(lat): float = 111320.0 * cos(lat)
```

---

## 10. Open Questions

- [ ] Do we store position as Vector3 or lat/lon in DB?
- [ ] Is equator the prime meridian reference?
- [ ] Do we support arbitrary rotation (not north-up)?
- [ ] Multiple planets or single planet?
- [ ] Wrap-around at ±180° longitude?
- [ ] Seamless zones or loading screens?
