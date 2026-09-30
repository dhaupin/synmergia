# core/frame/srv/ -- frame SERVICE logic

Godot GDScript frame primitives only: pure logic, no autoload, no
class_name, no GameManager dependency (the labs/README rules).
Tests are co-located (foo.gd + test_foo.gd) and registered in
scripts/godot_test_runner.sh's DEFAULT_SET via the frame/ prefix.

Residents: swim/glider state machines, the ferry schedule,
rules/scope engine, star cells, world registry.

NOT this folder: services in other languages, sidecars, servers,
and their manifests. Those live under srv/ with the other bridges
(the Julia orchestrator at srv/julia-bridge/ -- relocated
2026-09-30; MultiIsoService reaches it over HTTP, never by path).
