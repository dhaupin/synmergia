# Synmergia

An open-world MMORPG built with Godot 4.2+, inspired by RYL2 combat and Ultima Online depth.

## Tech Stack

- **Engine:** Godot 4.2+ (MIT License)
- **Language:** GDScript
- **Platforms:** Android, iOS, PC
- **Architecture:** Client + Authoritative Server

## Project Structure

```
godot-project/
├── core/           # Core systems (autoload singletons)
│   ├── autoload/   # GameManager, NetworkManager, InputManager, etc.
│   ├── entities/   # Base entity classes
│   └── combat/     # Combat system
├── entities/       # Game object scenes and scripts
│   ├── player/    # Player controller, states, camera
│   ├── enemies/   # Enemy AI and types
│   └── npcs/      # NPC types
├── ui/             # User interface
│   ├── hud/        # In-game HUD
│   └── menus/      # Menu screens
├── networking/     # Multiplayer systems
├── data/           # Game resources (.tres files)
└── assets/         # External assets

prd-synmergia.md  # Complete Product Requirements Document
```

## Getting Started

### Prerequisites

- Godot 4.2+ ([godotengine.org](https://godotengine.org))
- Android SDK (for mobile builds)

### Running the Project

1. Clone the repository
2. Open Godot 4.2+
3. Import `godot-project/project.godot`
4. Press F5 to run

### Building

#### Android
1. Go to Project > Export
2. Select Android preset
3. Click Export

#### Server
```bash
godot --headless --server --path res://
```

## Features

- ✅ 3D third-person combat
- ✅ Touch controls + keyboard/mouse
- ✅ State machine player controller
- ✅ Client-server multiplayer architecture
- ✅ Resource-based game data

## Documentation

See [PRD-World-Smith.md](./prd-synmergia.md) for full game design.

## License

MIT License - See Godot licensing for engine details.