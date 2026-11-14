## CcImmunity - THE one crowd-control tag vocabulary + the immunity gate.
##
## The status-effect schema has carried immune_stun/slow/silence/fear/root/
## knockback/dot/interrupt and grants_immunity_to()/get_immunity_list() since
## the data layer landed, but nothing read them: a body could never actually
## be immune to a stun. This is the runtime half -- a canonical tag per
## control, the control_type -> tag mapping the factory needs, and the single
## gate every apply path consults.
##
## Lives apart from status_effect.gd on purpose: that file preloads entity.gd,
## so referencing StatusEffect from entity.gd would be a preload cycle. Both
## sides preload this leaf instead.
extends RefCounted
class_name CcImmunity

## Canonical control tags. A `cc_tag` on an incoming effect names one of
## these; an `immune_tags` entry on a carrier refuses one.
const STUN: String = "stun"
const ROOT: String = "root"
const SLOW: String = "slow"
const SILENCE: String = "silence"
const FEAR: String = "fear"
const KNOCKBACK: String = "knockback"

const TAGS: Array[String] = [STUN, ROOT, SLOW, SILENCE, FEAR, KNOCKBACK]

## StatusEffectData.ControlType name -> canonical tag. INCAPACITATE (sleep,
## charm) is a full disable, so it refuses as stun. SNARE is a movement slow.
const CONTROL_TO_TAG := {
        "STUN": STUN,
        "ROOT": ROOT,
        "SNARE": SLOW,
        "FEAR": FEAR,
        "SILENCE": SILENCE,
        "KNOCKBACK": KNOCKBACK,
        "INCAPACITATE": STUN,
}


## The tag a control_type name inflicts, or "" for NONE/unknown.
static func tag_for_control(control_name: String) -> String:
        return str(CONTROL_TO_TAG.get(control_name, ""))


## True when `body` carries any effect that refuses `tag`. Duck-typed over
## `status_effects` so Entity, the player body and Enemy (which each own an
## apply_status_effect choke point) resolve immunity identically.
static func body_is_immune_to(body, tag: String) -> bool:
        if tag.is_empty() or body == null or not ("status_effects" in body):
                return false
        for fx in body.status_effects:
                if fx != null and fx.has_method("grants_immunity_to") and fx.grants_immunity_to(tag):
                        return true
        return false
