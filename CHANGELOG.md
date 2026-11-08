# Hidden Numbers - Changelog

## Unreleased

- Blind now has a ? after it on the enemy plate, in the journal and under a boss's bar: the game keeps a Blind flag
  for each enemy, but nothing found in the game builds it up yet.
- The enemy's health at the top of the meter now matches the number by the boss's bar (or over the enemy's head)
  frame for frame. It used to lag a hit or more behind. The fight summary and the journal show the health that
  number last showed.
- Hidden stats: on the item screen, a ring in a pawn's bag is now counted for that pawn (its base stats, defense,
  vocation and whether it has the ring on) instead of for you; a ring in the storage chest is counted for the
  character selected on the left.
- Hidden stats: the rings that only work without pawns no longer give a pawn the status-screen hint when that pawn's
  stats can't be read.
- Hidden stats: the line under a defense total now reads "up to -10% physical damage taken" instead of "≈ -10%
  physical damage taken": the number is the most the extra defense can cut, and its ≈ looked like the legend's "not
  confirmed by other mods". Mettle, Apotropaism and the defense rings no longer end with the grey legend line. Below
  1%, the percent on the defense total and on the damage line under it now has one decimal: Ring of Assurance's +10
  shows, for example, "(+0.6%)" and "up to -0.6% physical damage taken" instead of a rounded 0% or 1%.
- Fewer "Internal game exception ... get_DrawSelf" lines in REFramework's log: the mod now checks whether a closed
  menu or a vanished health bar is still there before it reads it.

## 1.0.0

Released 2026-11-07. The first public release.

- Damage meter and journal: a window over the game with the damage your party deals and takes and the healing, for
  each character and per second, and a summary when the fight is over. The fight journal (F7) goes into a finished
  fight: what each enemy is weak to and resists, the multiplier the game applied to each damage type, every skill's
  hits and damage, a chart and the record of the hits. Damage numbers show where your party's hits land. The last
  fights are kept, and can be saved between sessions.
- Health numbers: an enemy's health over its health bar, a boss's beside the boss bar, and your own health and
  stamina by your bars.
- Weaknesses and buildup: in a fight, a small plate says what the enemies near you are weak to and shrug off, and
  what your current attack does to them. Under a boss's health bar, how close it is to a stagger and a knock-down and
  how far each debilitation has built up.
- Hidden stats of augments and rings: on the vocation guild's augments screen, the item screen and the equipment
  screen, what the augment or ring under the cursor gives, in the game's own numbers. A share of a base stat also
  shows what it comes to for that character, and a defense line shows the total before and after. A line that is not
  settled is marked ≈ (not confirmed by other mods) or ? (a guess).
- Settings window (F8): each part can be switched off and sized, the meter's blocks one by one. F6 hides the meter
  window. English and Russian.
- Read-only: the mod changes nothing in the game and does not touch your saves.
