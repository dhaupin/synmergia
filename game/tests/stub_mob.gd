## stub_mob.gd - minimal duck-typed mob for headless projection tests.
## Deliberately NOT an Entity subclass: proves the projection's duck
## typing accepts any Node3D with the expected surface (entity_id,
## display_name, level, enemy_data, health_component). entity_type uses
## the Entity enum VALUE so EntityService's `entity.entity_type ==
## Entity.EntityType.ENEMY` classification accepts it.
extends Node3D

var entity_id: String = ""
var display_name: String = "StubMob"
var level: int = 1
var entity_type: int = 2         # Entity.EntityType.ENEMY (bitfield enum)
var seed: String = ""           # opt-in to seed derivation
var enemy_data = null            # EnemyData Resource or stub Dictionary
var health_component = null      # HealthComponent-like (current/max)
