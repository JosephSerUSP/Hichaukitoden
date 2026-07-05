local skills = {
    windBlade = {
        id = 'windBlade',
        name = 'Wind Blade',
        target = 'enemy-any',
        element = 'Green',
        description = "Strikes a foe with a blade of wind.",
        effects = {
            { type = 'hp_damage', formula = '6 + 1.2 * a.level' }
        }
    },
    soothingMote = {
        id = 'soothingMote',
        name = 'Soothing Mote',
        target = 'ally-any',
        element = 'White',
        description = "Heals a small amount of HP for an ally.",
        effects = {
            { type = 'hp_heal', formula = '5 + 1.5 * a.level' }
        }
    },
    boneRush = {
        id = 'boneRush',
        name = 'Bone Rush',
        target = 'enemy-any',
        element = 'Black',
        description = "A reckless charge.",
        effects = {
            { type = 'hp_damage', formula = '7 + 1.2 * a.level' }
        }
    },
    holySmite = {
        id = 'holySmite',
        name = 'Holy Smite',
        target = 'enemy-any',
        element = 'White',
        description = "Smite evil with holy light.",
        effects = {
            { type = 'hp_damage', formula = '6 + 1.4 * a.level' }
        }
    },
    divineFavor = {
        id = 'divineFavor',
        name = 'Divine Favor',
        target = 'ally-any',
        element = 'White',
        description = "Grants regeneration to an ally.",
        effects = {
            { type = 'add_status', status = 'regen', chance = 1.0, duration = 3 }
        }
    },
    shadowClaw = {
        id = 'shadowClaw',
        name = 'Shadow Claw',
        target = 'enemy-any',
        element = 'Black',
        description = "Tears at the enemy from the shadows.",
        effects = {
            { type = 'hp_damage', formula = '8 + 1.3 * a.level' }
        }
    },
    infernalPact = {
        id = 'infernalPact',
        name = 'Infernal Pact',
        target = 'self',
        element = 'Red',
        description = "Sacrifice safety for power. (Grants Berserk)",
        effects = {
            { type = 'add_status', status = 'berserk', chance = 1.0, duration = 3 }
        }
    },
    wait = {
        id = 'wait',
        name = 'Wait',
        target = 'self',
        element = 'White',
        description = "Do nothing.",
        effects = {}
    },
    flameRebirth = {
        id = 'flameRebirth',
        name = 'Flame Rebirth',
        target = 'self',
        element = 'Red',
        description = "Rise from the ashes.",
        effects = {}
    },
    needleShot = {
        id = 'needleShot',
        name = 'Needle Shot',
        target = 'enemy-any',
        element = 'Black',
        description = "A precise strike that injects toxins.",
        effects = {
            { type = 'hp_damage', formula = '5 + 1.2 * a.level' },
            { type = 'add_status', status = 'poison', chance = 0.4, duration = 3 }
        }
    },
    fieldSurgery = {
        id = 'fieldSurgery',
        name = 'Field Surgery',
        target = 'ally-any',
        element = 'Black',
        description = "Emergency medical attention. It might hurt.",
        effects = {
            { type = 'hp_heal', formula = '10 + 2.0 * a.level' }
        }
    },
    drainKiss = {
        id = 'drainKiss',
        name = 'Drain Kiss',
        target = 'enemy-any',
        element = 'Black',
        description = "Steals vitality and puts the target to sleep.",
        effects = {
            { type = 'hp_drain', formula = '4 + 0.6 * a.level' },
            { type = 'add_status', status = 'sleep', chance = 0.5, duration = 3 }
        }
    },
    attack = {
        id = 'attack',
        name = 'Attack',
        target = 'enemy',
        element = nil,
        description = "A basic physical attack.",
        spCost = 0,
        mpCost = 0,
        speed = 0,
        effects = {
            {
                type = 'hp_damage',
                formula = 'a.atk'
            }
        }
    }
}

return skills
