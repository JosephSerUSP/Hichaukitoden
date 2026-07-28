# Creature naming language

St. Maria may have a Portuguese colonial visual and cultural foundation without
giving its creatures a list of ordinary Portuguese words as pet names.
Creature names should feel as though that influence passed through another
language, an old localization, local superstition, or several centuries of
phonetic drift.

**Model transformation:** `Sabão → Saban` (preferred) or `Shabon`.

`Saban` retains the sound and private origin of the word, but belongs naturally
beside names drawn from Japanese games, mythology, invented fantasy and damaged
translations. The player need not recognize the source for the name to work.

## Naming layers

Do not apply one naming rule to everything.

- **Town and human names** can be recognizably Portuguese, Catholic,
  immigrant, or locally hybrid. St. Maria, Ines and Agnes help locate the
  settlement culturally.
- **Species names** should remain legible archetypes where appropriate: Moa,
  Kappa, Mandrake, Pixie.
- **Individual creature names** should feel intimate and eclectic, but not like
  a bilingual vocabulary list.
- **Ritual and Labyrinth names** may be stranger, older and less traceable than
  ordinary human names.

## Transformation methods

Use one or two operations, not a substitution cipher:

- remove diacritics and alter the final vowel: `Sabão → Saban`;
- preserve sound through foreign-looking spelling: `Sabão → Shabon`;
- clip or soften a word: `Brasa → Brase`, `Pavio → Pavi`;
- combine a root with another naming tradition: `Luar → Luaren`;
- let consonants drift: `Pedra → Petra` or `Peder`;
- keep a Portuguese word only when it already reads like a proper name in the
  game's wider register: `Rosa`, for example, may survive sparingly.

The result should not make every creature sound generically Japanese. The
desired texture is a lost game's inconsistent but compelling localization.

## Current roster audit

The following random-name entries in `data/actors.json` are conspicuously
literal and should be revised as a group before the pools are treated as final:

| Current root | Appears in | Possible direction |
|---|---|---|
| Sangue, Brasa, Cinza | Crimson Lord, Flauros, Cerberus | Sange, Brase, Cinzae |
| Chama, Pavio, Vela | Candle | Shama, Pavi, Vella |
| Sombra, Silêncio | Shadow Stalker | Sombre, Silen |
| Azul, Luar | Undine / Proteus | Azel, Luaren |
| Seda, Farol, Opala, Lua | Cocoon / Notiluca | Sera, Farun, Opal, Luma |
| Raiz, Dália, Nabo, Salsa | Mandrake / Alraune | Rais, Dalia, Nabu, Salza |
| Três, Cão, Guardião | Cerberus | Tres, Kaon, Gardian |
| Rocha, Bento, Colosso | Giants | Rokka, Benten, Colos |
| Caixa, Trinco, Boca, Dobra, Tesouro | Mimic / Pandora | Kaixa, Trinko, Boka, Dovra, Tesra |
| Estrela, Neve, Lança | Unicorn line | Estra, Neva, Lanza |
| Pedra, Vigia, Sino, Chuva, Gárgula | Gargoyle line | Petra, Vigel, Sino, Shuva, Gargula |
| Pepino, Beto, Pingo | Kappa | Pepin, Betto, Pinka |
| Rosa, Bico, Nuvem, Pompom, Pluma | Moa | Roza, Biko, Nuven, Pom, Plumae |

These are directions, not an approved mass rename. Each pool should also be
audited for jokes and generic English placeholders (`Rocky`, `Bandage`,
`Calcium`, `Flubber`) so the fix does not merely remove Portuguese while
leaving a different kind of tonal incoherence.

## Test for a candidate name

A creature name is promising when:

1. it can be spoken naturally in an emotional sentence;
2. it does not immediately translate into a mundane object for a large part of
   the intended audience;
3. it plausibly belongs to this particular strange, localized game;
4. it does not make the Portuguese influence disappear completely;
5. several names in the same pool do not reveal an obvious construction rule.
