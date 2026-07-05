/**
 * @file data/animations.js
 * @description Defines data-driven animations for the battle system.
 * Each animation object defines visual effects like particle flow, shakes, or flashes.
 */

/**
 * @type {Object.<string, Object>}
 * @property {string} type - The type of animation (e.g., 'text_flow_liquid', 'shake', 'flash').
 * @property {string} [sequence] - The character sequence for text flow animations.
 * @property {number} [duration] - The duration of the animation in milliseconds.
 * @property {number} [interval] - The update interval for frame-based animations.
 * @property {string} [color] - The CSS color string for the animation.
 * @property {string} [targetPart] - The specific part of the UI to target (e.g., 'hp_gauge').
 */
export const animations = {
  // The kaomoji flow animation requested by the user
  healing_sparkle: {
    type: "text_flow_liquid",
    sequence: "⋆｡°✩", // The characters to flow
    duration: 1000,
    interval: 50,
    color: "#aaffaa", // Light green/sparkly
    targetPart: "hp_gauge", // Where to play it
  },
  damage_shake: {
    type: "shake",
    duration: 500,
  },
  attack_flash: {
    type: "flash",
    duration: 200,
    color: "#ffffff"
  },
  death: {
    type: "death_sequence",
    duration: 1000
  }
};
