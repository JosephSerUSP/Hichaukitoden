import { randInt, shuffleArray, random } from "../src/core/utils.js";

/**
 * @file data/party.js
 * @description Defines logic for generating the starting party configuration.
 */

export const startingParty = {
  /**
   * Generates a random amount of starting gold.
   * @returns {number} The starting gold.
   */
  getGold: () => {
    return randInt(25, 75);
  },

  /**
   * Generates a random starting inventory.
   * @param {Object[]} allItems - All available items from items.json.
   * @returns {Object[]} The starting inventory.
   */
  getInventory: (allItems) => {
    const inventory = [];
    const consumables = allItems.filter(item => item.type === 'consumable' && item.id !== 'hp_tonic');
    const equipment = allItems.filter(item => item.type === 'equipment');

    // 1-3 HP Tonics
    const hpTonic = allItems.find(item => item.id === 'hp_tonic');
    if (hpTonic) {
        const amount = randInt(1, 3);
        for (let i = 0; i < amount; i++) {
            inventory.push(hpTonic);
        }
    }

    // 2 random consumables
    const randomConsumables = shuffleArray(consumables).slice(0, 2);
    inventory.push(...randomConsumables);

    // 2 random pieces of equipment
    const randomEquipment = shuffleArray(equipment).slice(0, 2);
    inventory.push(...randomEquipment);

    return inventory;
  },

  /**
   * Generates the starting party members.
   * @param {Object[]} allActors - All available actors from actors.json.
   * @returns {Object[]} The starting party members configuration.
   */
  getMembers: (allActors) => {
    const availableCreatures = allActors.filter(creature => creature.initialParty);

    if (random() < 0.25) {
      // 2 creatures, one leveled up
      const [creature1, creature2] = shuffleArray(availableCreatures).slice(0, 2);
      return [
        { id: creature1.id, level: creature1.level },
        { id: creature2.id, level: creature2.level + 3 }
      ];
    } else {
      // 3 creatures at base level
      return shuffleArray(availableCreatures)
        .slice(0, 3)
        .map(data => ({ id: data.id, level: data.level }));
    }
  }
};
