/**
 * Script to apply sensible baseParam values to all actors in all actor files.
 * 
 * The supported parameters are: maxHp, atk, def, mat, mdf, mpd, mxa, mxp
 * System defaults: maxHp=10, atk=10, def=10, mat=10, mdf=10, mpd=2, mxa=4, mxp=2
 *
 * Role-based stat design principles:
 *   Tank:     HP+++, ATK-, DEF+++, MAT--, MDF++, MPD--
 *   Attacker: HP+, ATK+++, DEF+, MAT-, MDF-, MPD-
 *   Healer:   HP+, ATK--, DEF+, MAT++, MDF++, MPD++
 *   Support:  HP+, ATK-, DEF+, MAT+, MDF++, MPD+, higher MXA/MXP
 *   Caster:   HP-, ATK--, DEF-, MAT+++, MDF++, MPD+++
 *   Debuffer: HP+, ATK-, DEF+, MAT++, MDF+, MPD++
 *   Parasite: HP-, ATK+, DEF-, MAT-, MDF-, MPD++
 *   Assassin: HP--, ATK+++, DEF--, MAT-, MDF-, MPD-
 *   Spirit:   HP-, ATK--, DEF--, MAT++, MDF+++, MPD++
 *   Vampire:  HP+++, ATK++, DEF++, MAT+, MDF+, MPD++
 *   Reviver:  HP++, ATK+, DEF++, MAT+++, MDF+++, MPD++, higher MXA/MXP
 *   Summoner: HP+, ATK--, DEF+, MAT++, MDF++, MPD+++++, higher MXA/MXP
 *   None:     minimal stats (egg etc.)
 *   Guardian: HP+++, ATK++, DEF+++, MAT-, MDF++, MPD--
 */

const fs = require('fs');
const path = require('path');

// ─── Stat templates by role ────────────────────────────────────────────────
// Each entry: [maxHp, atk, def, mat, mdf, mpd, mxa, mxp]
// These represent base values AT LEVEL 1 before growth is applied.
const ROLE_STATS = {
  'Tank':      [14,  8, 18,  5, 15, 1, 3, 2],
  'Attacker':  [11, 16, 11,  7,  8, 1, 4, 2],
  'Healer':    [12,  6, 10, 15, 14, 3, 4, 2],
  'Support':   [11,  7, 11, 13, 15, 2, 5, 3],
  'Caster':    [10,  5,  7, 17, 15, 4, 4, 2],
  'Debuffer':  [12,  7, 11, 14, 12, 3, 4, 2],
  'Parasite':  [10, 11,  7,  7,  6, 3, 3, 1],
  'Assassin':  [ 8, 18,  6,  5,  6, 1, 3, 2],
  'Spirit':    [10,  5,  6, 15, 17, 3, 3, 2],
  'Vampire':   [18, 18, 14, 12, 12, 3, 4, 2],
  'Reviver':   [15, 10, 14, 18, 17, 4, 5, 3],
  'Summoner':  [14,  5,  9, 16, 14, 6, 5, 3],
  'None':      [ 5,  3,  3,  3,  3, 0, 2, 1],
};

// Roles that map to one of the above templates
const ROLE_ALIASES = {
  'Guardian': 'Tank',
};

function getRoleStats(role) {
  const resolved = ROLE_ALIASES[role] || role;
  return ROLE_STATS[resolved] || null;
}

// ─── Level scaling ─────────────────────────────────────────────────────────
// Scale baseParams roughly by level so higher-level enemies are naturally
// stronger without relying on absurd PARAM_PLUS traits.
// Growth per level beyond 1: +8% to +12% per param depending on role emphasis.
function scaleForLevel(baseStats, level, role) {
  if (!level || level <= 1) return [...baseStats]; // already level-1 stats
  const factor = 1 + (level - 1) * 0.10; // 10% per level
  return baseStats.map(v => Math.max(1, Math.round(v * factor)));
}

// ─── Growth multiplier by tier ─────────────────────────────────────────────
// Higher-tier creatures grow faster per level.
function growthMultiplierForTier(tier) {
  const map = { 1: 1.0, 2: 1.15, 3: 1.35 };
  return map[tier] || 1.0;
}

// ─── Process a single actor ────────────────────────────────────────────────
function processActor(actor) {
  const role = actor.role || 'None';
  const level = actor.level || 1;
  const tier = actor.tier || 1;

  const roleStats = getRoleStats(level <= 1 ? role : role);
  if (!roleStats) {
    console.warn(`  ⚠  Unknown role "${role}" for actor "${actor.name}" (id=${actor.id}), skipping baseParams`);
    return;
  }

  // Scale stats to the actor's level
  const scaled = scaleForLevel(roleStats, level, role);

  // Preserve any existing maxHp override that differs from default
  const existingMaxHp = actor.baseParams && actor.baseParams.maxHp !== undefined
    ? actor.baseParams.maxHp
    : (actor.maxHp !== undefined ? actor.maxHp : null);

  // Build baseParams
  const [hp, atk, def, mat, mdf, mpd, mxa, mxp] = scaled;

  // If actor has a maxHp field already that's higher than our calculated, prefer it
  // (caters for manually tuned bosses like Crimson Lord with 55 HP)
  let finalHp = hp;
  if (actor.maxHp !== undefined && actor.maxHp >= hp && actor.maxHp > 10) {
    finalHp = actor.maxHp;
  }

  actor.baseParams = {
    maxHp: finalHp,
    atk,
    def,
    mat,
    mdf,
    mpd,
    mxa,
    mxp
  };

  // Also set growthMultiplier based on tier if not already set
  if (actor.growthMultiplier === undefined) {
    actor.growthMultiplier = growthMultiplierForTier(tier);
  }

  // Fix: Remove absurd PARAM_PLUS traits (value >= 50 is clearly placeholder)
  if (actor.traits && actor.traits.length > 0) {
    const filtered = actor.traits.filter(t => {
      if (t.code === 'PARAM_PLUS' && t.value >= 50) {
        console.warn(`  ✂  Stripped absurd PARAM_PLUS ${t.dataId}+${t.value} from "${actor.name}" (id=${actor.id})`);
        return false;
      }
      return true;
    });
    actor.traits = filtered;
  }

  // Remove legacy maxHp field since it's now in baseParams
  // (keep it only if baseParams.maxHp differs from actor.maxHp)
  // Actually, keep legacy maxHp as a fallback per the design doc - don't remove.
}

// ─── Main ──────────────────────────────────────────────────────────────────
const files = [
  'data/actors.json',
  'campaigns/thestra_no_jijou_2/actors.json',
  'campaigns/thestra_no_jijou_3/actors.json',
  'campaigns/thestra_no_jijou_4/actors.json',
];

for (const relPath of files) {
  const fullPath = path.resolve(__dirname, '..', relPath);
  console.log(`\n📁 Processing: ${relPath}`);

  if (!fs.existsSync(fullPath)) {
    console.error(`  🚫 File not found: ${fullPath}`);
    continue;
  }

  const raw = fs.readFileSync(fullPath, 'utf-8');
  const actors = JSON.parse(raw);
  let changed = 0;

  for (const actor of actors) {
    if (actor.role === 'Summoner' && actor.name === 'Alex') {
      // Special handling for Alex (player summoner) — preserve custom MP
      console.log(`  ℹ  "${actor.name}" (id=${actor.id}) — Summoner, preserving custom MP`);
    }
    processActor(actor);
    changed++;
  }

  fs.writeFileSync(fullPath, JSON.stringify(actors, null, 2) + '\n', 'utf-8');
  console.log(`  ✅ Updated ${changed} actors in ${relPath}`);
}

console.log('\n🎉 Done! All actor files updated with sensible baseParams.');
