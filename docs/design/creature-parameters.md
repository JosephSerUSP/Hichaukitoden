# Creature Parameters and Growth

Creature parameters are resolved from global system defaults, actor overrides,
level growth, and active traits.

The supported parameters are `maxHp`, `atk`, `def`, `mat`, `mdf`, `mpd`,
`mxa`, and `mxp`. `mxa` is maximum learned actions and `mxp` is maximum learned
passives. They are capacity values and do not grow with level. `mpd` is MP
drain per round and does grow.

Actors may define:

```json
{
  "baseParams": {
    "maxHp": 60,
    "atk": 14,
    "def": 22,
    "mat": 6,
    "mdf": 16,
    "mpd": 2,
    "mxa": 4,
    "mxp": 2
  },
  "growthMultiplier": 1.25
}
```

Missing actor values inherit `system.growth.baseParams`. The actor growth
multiplier defaults to `1.0`; values below or above 1.0 are valid.

For growing parameters, the effective value before traits is:

```text
base × (1 + growthRate × growthMultiplier × (level - 1)^growthExponent)
```

The default exponent is `1.2`, making progression gently superlinear. Growth
rates are decimal fractions (`0.15` means 15%). Defaults are parameter-specific
and live in `system.growth.growthRates`. The current defaults are 12% max HP,
15% ATK/MAT, 13% DEF/MDF, and 5% MPD.

Legacy actor fields such as `maxHp` and `mpd`, and legacy system growth fields,
remain valid fallbacks so existing campaigns and saves need no migration.

`asp` and the battle turn-order speed calculation are intentionally outside
this model until the turn-order system is redesigned.
