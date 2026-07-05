/**
 * @file data/states.js
 * @description Defines the states (status effects) available in the game.
 * States are containers for Traits and can affect battler behavior and stats.
 */

/**
 * @typedef {Object} Trait
 * @property {string} code - The code identifying the trait (e.g., 'PARAM_PLUS', 'HRG').
 * @property {string|number} [dataId] - Additional data for the trait (e.g., 'atk', 'sleep').
 * @property {number} value - The value of the trait.
 */

/**
 * @typedef {Object} State
 * @property {string} id - The unique ID of the state.
 * @property {string} name - The display name.
 * @property {number} icon - The icon ID.
 * @property {number} [restriction] - Restriction level (4 = Cannot Act).
 * @property {number} [duration] - Default duration in turns.
 * @property {boolean} [removeAtDamage] - Whether the state is removed upon taking damage.
 * @property {Trait[]} traits - List of traits applied by this state.
 */

export const states = {
    dead: {
        id: 'dead',
        name: 'Dead',
        icon: 11, // Skull-like icon if available, or placeholder
        restriction: 4, // Cannot act
        priority: 100,
        traits: []
    },
    sleep: {
        id: 'sleep',
        name: 'Sleep',
        icon: 1,
        restriction: 4,
        duration: 3,
        removeAtDamage: true,
        traits: []
    },
    regen: {
        id: 'regen',
        name: 'Regeneration',
        icon: 1,
        duration: 5,
        traits: [
            { code: 'HRG', value: 0.1 } // Heals 10% max HP per turn
        ]
    },
    berserk: {
        id: 'berserk',
        name: 'Berserk',
        icon: 1,
        duration: 3,
        traits: [
            { code: 'PARAM_PLUS', dataId: 'atk', value: 3 }
        ]
    },
    weakened: {
        id: 'weakened',
        name: 'Weakened',
        icon: 11,
        duration: 9999,
        traits: [
            { code: 'PARAM_RATE', dataId: 'atk', value: 0.5 },
            { code: 'PARAM_RATE', dataId: 'def', value: 0.5 },
            { code: 'PARAM_RATE', dataId: 'asp', value: 0.5 }
        ]
    }
};
