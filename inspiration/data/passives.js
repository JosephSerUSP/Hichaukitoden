/**
 * @file data/passives.js
 * @description Defines the passive abilities available in the game.
 * Passives provide static bonuses or triggered effects via Traits.
 */

/**
 * @typedef {Object} Passive
 * @property {string} id - Key used for lookup/referencing.
 * @property {string} name - Display name.
 * @property {string} description - Flavor text (Line 1 of tooltip).
 * @property {string} effect - Functional description (Line 2 of tooltip).
 * @property {number} icon - Icon ID (from spritesheet).
 * @property {Array<Object>} traits - List of traits applied by this passive.
 */

export const passives = {
    // Existing
    postBattleHeal: {
        id: 'postBattleHeal',
        name: 'Trick Heal',
        description: 'A playful mending art.',
        effect: 'Restores 1 HP to party on victory.',
        icon: 1,
        traits: [{ code: 'POST_BATTLE_HEAL', value: 1 }]
    },
    goldDigger: {
        id: 'goldDigger',
        name: 'Gold Digger',
        description: 'Greed is good.',
        effect: 'Increases gold found by 5.',
        icon: 1,
        traits: [{ code: 'GOLD_DIGGER', value: 5 }]
    },
    parasite: {
        id: 'parasite',
        name: 'Hunger',
        description: 'An insatiable void.',
        effect: 'Drains 2 HP from a nearby ally every turn.',
        icon: 1,
        traits: [{ code: 'PARASITE', value: 2 }]
    },
    battleStartDamage: {
        id: 'battleStartDamage',
        name: 'Ambush',
        description: 'Strike from the shadows.',
        effect: 'Deals damage to an enemy at start of battle.',
        icon: 1,
        traits: [{ code: 'BATTLE_START_DAMAGE', value: 2 }]
    },
    moveHeal: {
        id: 'moveHeal',
        name: 'Regeneration',
        description: 'Life finds a way.',
        effect: 'Restores HP when moving.',
        icon: 1,
        traits: [{ code: 'MOVE_HEAL', value: 1 }]
    },
    recoveryXpBonus: {
        id: 'recoveryXpBonus',
        name: 'Scholar',
        description: 'Knowledge is power.',
        effect: 'Gains bonus XP at recovery sites.',
        icon: 1,
        traits: [{ code: 'RECOVERY_XP_BONUS', value: 5 }]
    },
    fleeChanceBonus: {
        id: 'fleeChanceBonus',
        name: 'Coward',
        description: 'He who fights and runs away...',
        effect: 'Increases chance to flee.',
        icon: 1,
        traits: [{ code: 'FLEE_CHANCE_BONUS', value: 0.1 }]
    },
    dealDamageMod: {
        id: 'dealDamageMod',
        name: 'Strength',
        description: 'Raw power.',
        effect: 'Increases damage dealt.',
        icon: 1,
        traits: [{ code: 'PARAM_PLUS', dataId: 'atk', value: 1 }]
    },
    rebirth: {
        id: 'rebirth',
        name: 'Rebirth',
        description: 'Rising from the ashes.',
        effect: 'On death: Restore 20% HP, lose 2 levels.',
        icon: 1,
        traits: [{ code: 'ON_PERMADEATH', value: 1 }]
    },
    seeTraps: {
        id: 'seeTraps',
        name: 'Trap Sense',
        description: 'Eyes that see what others miss.',
        effect: 'Detects hidden traps.',
        icon: 1,
        traits: [{ code: 'SEE_TRAPS', value: 1 }]
    },
    sense: {
        id: 'sense',
        name: 'Sense',
        description: 'Heightened awareness.',
        effect: 'Reveals breakable walls.',
        icon: 1,
        traits: [{ code: 'SEE_WALLS', value: 1 }]
    },

    // New
    undeadFortitude: {
        id: 'undeadFortitude',
        name: 'Undead Fortitude',
        description: 'Bones harder than steel.',
        effect: 'Max HP +20%.',
        icon: 1,
        traits: [{ code: 'PARAM_RATE', dataId: 'maxHp', value: 1.2 }]
    },
    holyAura: {
        id: 'holyAura',
        name: 'Holy Aura',
        description: 'Bathed in divine light.',
        effect: 'Regenerates 5% HP each turn.',
        icon: 1,
        traits: [{ code: 'HRG', value: 0.05 }]
    },
    nightVision: {
        id: 'nightVision',
        name: 'Night Vision',
        description: 'Pierces the dark.',
        effect: 'Detects traps and secrets (Level 2).',
        icon: 1,
        traits: [{ code: 'SEE_TRAPS', value: 2 }]
    },
    etherealBody: {
        id: 'etherealBody',
        name: 'Ethereal',
        description: 'Hard to touch.',
        effect: 'Chance to avoid physical damage (Not Implemented Yet, using HP buff).',
        icon: 1,
        traits: [{ code: 'PARAM_RATE', dataId: 'maxHp', value: 1.1 }]
    },
    chaosPact: {
        id: 'chaosPact',
        name: 'Chaos Pact',
        description: 'Power at a price.',
        effect: 'Atk +15%.',
        icon: 1,
        traits: [{ code: 'PARAM_RATE', dataId: 'atk', value: 1.15 }]
    },
    mischief: {
        id: 'mischief',
        name: 'Mischief',
        description: 'Always up to no good.',
        effect: 'Gold found +2.',
        icon: 1,
        traits: [{ code: 'GOLD_DIGGER', value: 2 }]
    },
    symbiosis: {
        id: 'symbiosis',
        name: 'Symbiosis',
        description: 'A life-giving bond.',
        effect: 'Heals neighbor 2 HP/turn.',
        icon: 1,
        traits: [{ code: 'SYMBIOSIS', value: 2 }]
    },
    initiative: {
        id: 'initiative',
        name: 'Initiative',
        description: 'A chance to act before the enemy.',
        effect: '25% chance of a first strike.',
        icon: 1,
        traits: [{ code: 'INITIATIVE', value: 0.25 }]
    },
    rearGuard: {
        id: 'rearGuard',
        name: 'Rear Guard',
        description: 'Protects against ambushes.',
        effect: 'Negates enemy first strikes.',
        icon: 1,
        traits: [{ code: 'REAR_GUARD', value: 1 }]
    }
};
