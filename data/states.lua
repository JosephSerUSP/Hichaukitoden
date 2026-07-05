local states = {
    dead = {
        id = 'dead',
        name = 'Dead',
        icon = 11,
        restriction = 4,
        priority = 100,
        traits = {}
    },
    sleep = {
        id = 'sleep',
        name = 'Sleep',
        icon = 1,
        restriction = 4,
        duration = 3,
        removeAtDamage = true,
        traits = {}
    },
    regen = {
        id = 'regen',
        name = 'Regeneration',
        icon = 1,
        duration = 5,
        traits = {
            { code = 'HRG', value = 0.05 } -- 5% HP regen per turn
        }
    },
    berserk = {
        id = 'berserk',
        name = 'Berserk',
        icon = 1,
        duration = 3,
        traits = {
            { code = 'PARAM_PLUS', dataId = 'atk', value = 3 }
        }
    },
    weakened = {
        id = 'weakened',
        name = 'Weakened',
        icon = 11,
        duration = 9999,
        traits = {
            { code = 'PARAM_RATE', dataId = 'atk', value = 0.5 },
            { code = 'PARAM_RATE', dataId = 'def', value = 0.5 },
            { code = 'PARAM_RATE', dataId = 'asp', value = 0.5 }
        }
    }
}

return states
