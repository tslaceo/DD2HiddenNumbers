# Hidden Numbers - Damage Meter, Boss and Enemy HP, Weaknesses, Augment Stats

Shows the numbers Dragon's Dogma 2 keeps to itself: enemy HP, what each enemy is weak to, boss stagger and
debilitation buildup, a damage meter for your party, and what augments and rings really give. Read-only.

A REFramework Lua mod. It only watches what the game reports and reads the game's own tables; it does not change
damage, healing or your saves. The amounts of damage, healing and health are the game's own numbers for every hit and
heal, and so are the multipliers the game applied to your hits. Who gets the credit for a heal area, an item or a
status condition is the mod's own attribution, and the "health saved by armor" line is a recalculation.

## What it shows

### Damage meter and journal

- During a fight, a window over the game with three blocks: Damage to enemies (total, per second, and a bar for
  everyone who hit an enemy: damage, per second, share), Damage to party (who hurt whom: "Goblin ×4 → Guts"; the same
  enemies are added up) and Healing (total, per second, a bar for everyone who healed). The header shows the main
  enemy with its health ("31 200 / 80 000") and the fight timer.
- After a fight the window turns into a summary: the enemies with their full health and whether they were killed;
  how much each character dealt and healed, with healing by items counted for whoever used the item; and the armor
  lines ("Enemy defence absorbed", "Party armor absorbed") as "≈ health saved" with the share of the damage the armor
  took off. The summary stays until you hide it, or until it hides itself (see Settings).
- Character details. With REFramework's menu open, click a character in the window: a table of its skills, normal
  attacks (one row) and status damage (burning, poison, shock, frost) with hits, total, max, share and perfect-timing
  hits, then the full damage with overkill, what the enemies' defence took off, what the character's armor took off
  and what the shield blocked.
- The fight journal (F7): a large window with seven tabs about a finished fight. Above all, what each enemy is weak
  to and resists (as the game says it), the damage it took by type with the multiplier the game really applied, and
  who dealt what with which skill. See "The journal" below.
- Damage numbers where a hit lands on an enemy: the damage the meter counts for it, in the attacker's colour, rising
  and fading or on a small plate (`damage_numbers_style`). Quick hits of one attacker's skill add up into one number.
  A hit is marked when the game adds a bonus for the enemy's state (a downed enemy, for example): bigger with "!"
  when rising, a bigger plate with a gold border on plates. Buffs such as the Trickster's incense or a jump attack are
  not marked. A weak-point hit has a small diamond. `damage_numbers` switches them off, `damage_numbers_size` sets
  their size (50 to 300 %).
- History. The last fights (10 by default, up to 32) can be paged with the arrows in the summary's header and in the
  journal. If you want, they are kept in a file and are still there after a restart of the game.

How a fight is counted:

- A fight starts with the game's own battle mode, the one the battle music follows, and ends 3 seconds after the
  game's battle ends. If the battle comes back within those 3 seconds, or your party hits an enemy of that fight, the
  fight goes on; a hit on another enemy starts a new fight. A fight also starts at the first blow between your party
  and an enemy, so an ambush counts from the first blow. Hits between enemies and other people do not start a fight.
- Only enemies that fought your party are counted. An enemy joins a fight when your party hits it or it hits your
  party. From then on what allies (people on your side who are not in your party, such as a guard) do to it counts
  too, and they are shown as grey rows. A guard's own fight with a monster your party never touches is not counted.

### Health numbers

- Over enemies: above the game's health bar over an enemy's head, "12 340 / 18 000 · 69%", in the look of the pawns'
  names. At a boss: a little bigger, to the right of the boss's health bar at the top of the screen.
  `enemy_hp_numbers` and `boss_hp_numbers` pick what each shows or switch it off, and `enemy_hp_size` sets the size of
  both (50 to 300 %).
- Your own health and stamina: above the right end of your health bar at the bottom of the screen (where the whole
  bar ends, so the numbers stay put while it empties), your health and its max ("3 031 / 3 031"); while damage has cut
  the max, the full max follows in brackets ("3 031 / 3 031 (3 100)"). The same for your stamina under the right end
  of its bar ("1 202 / 1 300"). Only yours, not your pawns', and only while the game shows its own bars.
  `player_numbers` switches them off; `enemy_hp_size` sets their size.

### Weaknesses and buildup

- Enemy plate. In a fight, a small plate left of the boss's health bar, or at the top of the screen without a boss,
  tells what the enemies near you are weak to and shrug off. It is a table with a column per damage type (slash,
  blunt, ranged, fire, ice, lightning, holy, magic) and a row per kind of enemy with how many there are ("Goblin ×5")
  and what each type does to its body in the game's table in use ("0.8", "1.0"). A row for its weak spot and one for
  its head follow when they take clearly more or less than the body ("·" where the part takes what the body takes).
  The best value of each row is underlined; "no data" stands across a row whose table could not be read. Below the
  table: the status conditions that do not work on each kind (under a boss, on the boss), then a "you:" line with
  what you hit with now and what it gets there (your hits of the last 10 seconds, or before your first hit your weapon
  and its enchant). A table too wide for its place is drawn with a smaller font, so the plate stays clear of the
  boss's bar. It shows while a fight is open or an enemy's health bar is drawn, and for 3 seconds after.
  `enemy_plate` switches it off, `enemy_plate_size` sets its size (50 to 300 %).
- Status buildup at the boss. Under the boss's health bar, first how far the boss is from a stagger and from a
  knock-down (Stagger "41 841 / 65 000", Knock down), then a row for each status building on it (poison, burning,
  stun...; not an enemy's own elemental aura, nor a status it is immune to): its name, how far it is ("1 800 / 5 000")
  and about how many more hits set it off ("≈ 7 hits", from its last rises), over a thin bar in its colour as wide as
  the boss's bar. Once a status sets off, its row shows how long it still lasts ("8 s left") on a bar that drains.
  Each trigger makes the boss resist that status more, and its row then says how much ("resistance 20%", then 50% and
  80%); the hits estimate starts anew. A row goes when it is back to 0 (the boss staggered, the status worn off or
  over). `buildup_bars` switches them off; `enemy_hp_size` sets their size.

### Hidden stats of augments and rings

On the vocation guild's augments screen, the item screen and the equipment screen, a small panel by the game's
description says what the augment or ring under the cursor gives, in the game's own numbers ("+200 max health"), each
line marked by how sure its reading is. See "Hidden stats" below. `hidden_stats` switches it off; `hidden_stats_size`
sets its size.

### Everywhere

- While the game is paused in a menu (the pause menu, the map...), the window, the health numbers, the status buildup,
  your health and stamina numbers, the enemy plate and the damage numbers are hidden until it closes. The journal
  (F7) and the settings window (F8) still work, and the window shows while the settings window is open.
- Each part has a switch and a size in the settings window (F8). F6 hides the meter window (a new fight brings it
  back), and each block of it during a fight and of the summary has its own switch: a block that is off is not built
  or drawn, and the data are still collected for the journal.
- English and Russian, following the game's language by default.

## Requirements

- Dragon's Dogma 2 on PC (tested on `DD2.exe` 4.2.0.0).
- [REFramework](https://www.nexusmods.com/dragonsdogma2/mods/8) from its Nexus page. Tested on build 01422, the one on
  that page, and on nightly 01433; you do not need a nightly. Nothing else is needed.

## Install

1. Install REFramework in the game folder (the one that contains `DD2.exe`).
2. Extract the release archive (`HiddenNumbers-<version>.zip`) into the game folder. The mod's script files are named
   DD2DamageMeter, the name it had while it was being made: you get `reframework\autorun\DD2DamageMeter.lua` and the
   folder `reframework\autorun\DD2DamageMeter\`, which also holds this README and the LICENSE. The archive puts nothing
   else into the game folder.
3. Start the game. Your settings are saved to `reframework\data\DD2DamageMeter\settings.json` (see Settings).

Uninstall: delete `reframework\autorun\DD2DamageMeter.lua` and the folder `reframework\autorun\DD2DamageMeter\`
(the README and LICENSE are in it) and, if you want your settings (and `history.json`) gone too, the folder
`reframework\data\DD2DamageMeter\`.

## Compatibility

The mod has not been tested together with Better Better Item Description or Clear Effect Descriptions.

- Better Better Item Description adds text to augment descriptions. The guild panel finds the augment under the
  cursor by its description, so with that mod the panel may not show on the guild's augments screen. The item and
  equipment screens find a ring by its id and are not affected.
- Clear Effect Descriptions changes the game's text files. It has not been tested with this mod either.

## Keys and mouse

| Key | What it does |
|---|---|
| F6 | Show / hide the window (the key can be changed, see Settings) |
| F7 | Open / close the fight journal (the key can be changed, see Settings); its own keys are under "The journal" |
| F8 | Open / close the settings window (the key can be changed in it); its own keys are under "Settings" |
| Insert | REFramework's own menu; while it is open the mod's windows take the mouse |

The window does not take the mouse or the keyboard while you play. Only while REFramework's menu is open (Insert)
does the window react to the mouse:

- click a character's name or bar: that character's details; the ‹ at the top left goes back;
- the arrows ‹ › in the summary's header page through the last fights (they show once there are two);
- the × at the top right hides the window (F6 shows it again; a new fight brings it back by itself);
- drag the window to move it; the place is saved.

## The journal

F7 opens a large dark window in the middle of the screen (85 % of its width and height) on the fight the summary
shows, and F7 closes it again. While it is open the fight window and the summary are not drawn; they come back when
it closes. A fight that starts or ends while it is open does not close it: the journal stays on the fight it shows,
or, if it showed the newest fight, goes on to the one just finished. It shows finished fights only; with no finished
fight yet it says "No fights yet".

At the top: the tabs, the fight's line ("Victory · 4:15 · Ogre, Saurian ×2") with ‹ fight 2 of 10 › to page through
the last fights, and five numbers: damage dealt, damage per second, damage taken, healing, and the share of the
party's damage the enemies' defence took off. The tabs:

1. Summary - each character's share of the damage (as in the window, larger), the enemies of the fight, the armor.
2. Enemies - the main tab. On the left the fight's enemies, one row each, with a health bar and "killed"; enemies of
   one kind (say five goblins) are listed under a row "Goblin ×5" whose card adds them up. On the right the card of
   the selected row:
   - when it died and who dealt the killing blow;
   - What the game says: what it is weak to and what it resists (the game's own tags, the ones your pawns talk
     about), the status conditions that do not work on it, its defense and magick defense. "no data" when the game
     did not tell (an enemy that was gone before the mod could read it);
   - What hit it: the damage it took by type (slash, blunt, ranged, fire, ice, lightning, holy, dark, magic, status
     damage, other) with a bar, the multiplier the game applied to those hits, and the game's own scale for it: "no
     effect" (×0 or less), "poor" (under ×0.5), nothing for a normal hit, "good" (×1.5 and more). Under it a line such
     as "Slash: head ×1.4 · body ×1.0" for the damage type that did the most damage of those that hit both the head
     and the body, when its two multipliers differ;
   - Who dealt what: each party member (allies grey) with hits, damage and share, and under them their skills with
     hits, damage, average, largest hit and the multiplier;
   - Whom it hit: whom the enemy hit and how hard, each attack as its damage type and element with the number of hits
     ("Blunt ×5, Fire ×1").
3. Skills - every skill of the party against all enemies: hits, damage, average, largest, damage per second, share;
   for the whole party or for one member.
4. Damage to party - for each party member, which enemies hit them, how hard and with what (damage type and element,
   as in "Whom it hit"), and what their armor saved.
5. Healing - who healed whom and with what (the skill, the item by its name), and "Other".
6. Chart - a column for each party member, split into pieces by skill in shades of the member's colour: that
   member's own four largest skills and "Rest"; beside the columns, the selected member's skills.
7. Record - the fight's hits and heals in order: time, who, whom, with what, how much (the latest 2000 of a fight;
   the line at the top says how many earlier ones were not kept).

Keys while the journal is open (the game receives them too: the journal does not take the keyboard):

| Key | What it does |
|---|---|
| F7 | Close the journal |
| PgUp / PgDn | The previous / next tab |
| Home / End | A newer / older fight |
| Up / Down | Select: an enemy in Enemies, the whole party or a member in Skills, a member in Chart |
| Left / Right | The previous / next page of a long tab |

With REFramework's menu open (Insert) the journal also takes the mouse: click a tab, the ‹ › of the fights or of
the pages, a row of the enemy list, a member in Skills or a bar in Chart; the × at the top right closes it. Without
the menu the mouse goes to the game.

## Hidden stats

The game says what an augment or a ring raises, but not by how much. On the vocation guild's augments screen, the
item screen and the equipment screen, the mod puts a small panel by the game's description that says what the
augment or ring under the cursor gives, in numbers: "+200 max health", "+45 and +30% of your base defense (380) —
+159 now". On the item and equipment screens it sits under the description. On the guild's screen it sits at the
bottom of the description's area, right above the header of the augments in use, and grows upwards (at a large panel
size it can cover the last lines of a long description). The numbers come from the game's own tables while you play,
so a patch that changes them changes the panel too; only the sentence around each number is the mod's. The panel
shows on those three screens only, also while they pause the game, and not while the journal is open.

Each line says how sure that reading is. The readings were cross-checked against two other mods that show these
numbers: [Clear Effect Descriptions 2.0](https://www.nexusmods.com/dragonsdogma2/mods/314) by Filipe Ramos and
[Better Better Item Description](https://www.nexusmods.com/dragonsdogma2/mods/338) by xyzkljl1. A line without a mark
is settled by a developers' note, a field name or a check in the game, or both of those mods read the number the same
way we do. ≈ marks a line they do not confirm: what the number does is clear, but one of them says nothing about it or
reads its unit or formula differently. ? marks a guess: the game has the number, but what it does is not clear. A
panel with a ≈ or ? line ends with a grey line that repeats this. "no number found in the game" means the effect
should have a number and none was found.

For an augment or ring that adds a share of a base stat, the line also says what that comes to for the character the
screen shows, you or a pawn (not for a pawn on a ring that works only without pawns). When the mod cannot read that
character's base, the line points to the number in brackets on the status screen instead. A line that adds to
defense or magick defense is followed by what it does to that character's total on the status screen, with or
without it ("defense 1486 → 1645 (+11%)"), and by a ≈ line with the damage taken that comes of it ("≈ -10% physical
damage taken"), an estimate that leaves out the enemy's side of the game's formula. A ring whose numbers depend on the
vocation is read for the vocation of the character the screen shows.

## Help check the hidden stats

A line marked ≈ or ? is not settled yet. With ≈ the number is the game's and what it does is clear, but Clear Effect
Descriptions or Better Better Item Description says nothing about it or reads it otherwise, and nobody has checked it
in the game yet. With ? we only guess what the number does.

[RINGS.md](https://github.com/tslaceo/DD2HiddenNumbers/blob/main/RINGS.md) lists every ring and augment with the
panel's lines and their marks. The open lines come first, each with what would settle it.

Checked in the game so far: the Ring of Quickening (its panel says +10%, and timed with and without it, stamina
refilled about 12 % faster: a percentage on the refill speed, not 10 a second), the Ring of Reversal's drain (120
health a second in battle) and the Ring of Enervation's return (20 % of a weapon skill's stamina cost, about a second
after the skill). Fortuity's chances of extra gold and meat and the steps of the rings of Brawn and Proximity were read
in the running game. All these lines are plain.

Lines that change your own numbers take a minute to settle:

1. Turn on Debug in the settings window (F8, under Other).
2. Change one augment at a vocation guild, or one ring on the equipment screen.
3. Go back to the game for a couple of seconds.
4. Zip `reframework\data\DD2DamageMeter\collect.jsonl` (GitHub does not take a .jsonl file as it is) and attach the
   zip to a [Hidden stats check](https://github.com/tslaceo/DD2HiddenNumbers/issues/new?template=hidden_stats_check.yml)
   on GitHub, or post a link to it in the Bugs tab of the mod's Nexus page. Its `stat_check` lines are enough.

You do not need to open the status screen. While Debug is on and the game is not paused, the mod notes your numbers
every two seconds: strength, defense, magick, magick defense, knockdown power and knockdown resistance with every part
the game keeps of them (the number in brackets and what is added to it), max health, stamina and carry weight, and
your gear's resistances. When your augments or equipment change and your numbers change with them, it writes one
`stat_check` line with what came in, what went out and every number that changed. Change one thing at a time: two
changes in one visit to a menu end up in one line. A level up or a meal changes your numbers but not your equipment,
so it writes nothing.

Other lines change nothing the status screen shows and need a fight or a stopwatch. If you try one of these, tell us
what you saw:

- The Ring of Gallantry: the damage you take from ranged attacks from the front and from hits in the back. Take the
  same enemy's attack both ways; the journal's Damage to party tab shows the difference.
- The Ring of Audacity: how much health it takes each second while you do not attack, and how soon after an attack.
- The Ring of Imperception: at how much health it hides you, for how many seconds, and how long until it works again.
- The Ring of Benevolence: how big a hit starts the healing and how long the healing lasts.
- The Ring of Reversal: how much an enemy's hit heals you.
- Exaltation: how much faster your stamina refills, timed from empty to full with and without it.

## Settings

F8 opens the mod's settings window beside the fight window, on the side with more room, and F8 closes it; it and
the journal are never open together. Its groups: Meter look, What to show, Damage numbers, Health numbers, Enemy
plate, Hidden stats, Journal, Keys, Other. Under the settings a few lines tell what the selected one does. The
window is as wide as its widest row needs in the language shown (320 to 480 px times Size).
While it is open the fight window is shown even if you hid it (the fight going on, else the last fight's summary),
so each change is seen at once; it is hidden again when the settings window closes, if it was. Changes apply at
once and are saved to `reframework\data\DD2DamageMeter\settings.json` when the settings window closes (and
REFramework's menu, if it is open), or every 5 seconds while it is open.

| Key | What it does |
|---|---|
| Up / Down | Select a setting |
| Left / Right | Change it: a switch flips, a choice goes to the previous / next one, a number goes down / up by a step (1 for whole numbers, 10 px for the position, 5 % for the size and the background, 10 % for the shadow and the sizes of the numbers, of the enemy plate and of the hidden stats panel). In the table of What to show: the Fight / Summary cell |
| Enter | Flip a switch or the selected cell of the table; on a key, wait for the key you press next (Esc cancels, so does opening or closing REFramework's menu; a key another setting has is not taken) |
| PgUp / PgDn | The previous / next group |
| F8 | Close the window |

The game receives these keys too. With REFramework's menu open (Insert) the window also takes the mouse: click a
setting (a switch flips, a key waits for a key), a cell of the table (it flips), the ‹ › of a choice or a number,
or the × to close the window. In REFramework's menu (Script Generated UI -> Hidden Numbers) there are a button that
opens the settings window and the settings window key's button, in case F8 is taken.

Meter look (more in "The look of the window" below):

| Setting | Key in settings.json | Default | What it does |
|---|---|---|---|
| Style | `style` | `frameless` | `frameless` (No panel): text and bars straight over the scene; `panel` (Panel): a dark panel |
| Size | `scale` | `1.0` | Size of the window, the journal and their text (60 to 200 %) |
| Background | `opacity` | `0.78` | How dark the panel, or without the panel the soft halo, is (20 to 100 %) |
| Shadow | `shadow` | `0.8` | How strong the dark shadow under the text is (0 = none, up to 100 %) |
| Outline | `outline` | `true` | A thin dark outline around the numbers |
| Halo | `halo` | `false` | A dark patch behind the text that fades out at its edges, as dark as Background; shown only without the panel |
| Bars | `bar_px` | `3` | How thick the bars are (1 to 8 px; Size makes them thicker too); shown only without the panel |
| Position X | `window_x` | `40` | Pixels from the left edge of the screen |
| Position Y | `window_y` | `300` | Pixels from the top edge of the screen |

What to show: a table with a row per block of the window and two cells, Fight (the window during a fight) and
Summary; a "—" cell means that window has no such block. A block or rows that are off are not built or drawn; the
mod still collects everything, and the journal shows it all.

| Row | Fight (key, default) | Summary (key, default) | What it shows |
|---|---|---|---|
| Enemies | — | `summary_enemies`, `true` | The enemies of the fight with their health |
| Dealt | `live_damage`, `true` | `summary_damage`, `true` | The "Damage to enemies" block during a fight; how much each party member dealt in the summary |
| Taken | `live_taken`, `true` | — | The "Damage to party" block |
| Healing | `live_heal`, `true` | `summary_heal`, `true` | Who healed how much |
| Armor | — | `summary_armor`, `true` | The armor lines ("Enemy defence absorbed", "Party armor absorbed") |
| Allies | `show_allies`, `true` | `summary_allies`, `true` | Grey rows for people on your side who are not in your party, such as a guard. They are not in the totals or shares |
| Other | `live_other`, `true` | `summary_other`, `true` | The grey "Other" rows (status damage and healing with no known source) and "Falls and environment" (damage enemies did to themselves that nobody on your side caused in the 3 seconds before) |

Under the table:

| Setting | Key in settings.json | Default | What it does |
|---|---|---|---|
| Summary hides after | `summary_autohide` | `0` (never) | The summary hides itself this many seconds after the fight ends or after you last used it (0 to 600); it waits while REFramework's menu, the journal or the settings window is open |

Damage numbers (Show, Style, Size), Health numbers (At the boss, Over enemies, My health and stamina, Status buildup,
Size) and Enemy plate (Show, Size) are described at the top of this page. Health numbers name what they show: off,
HP, HP / max, %, HP and %, HP / max and %.

Hidden stats (see "Hidden stats" above):

| Setting | Key in settings.json | Default | What it does |
|---|---|---|---|
| Show | `hidden_stats` | `true` | The panel with the numbers of the augment or ring under the cursor on the guild's augments screen, the item screen and the equipment screen. Off: those screens are not read and nothing is drawn |
| Size | `hidden_stats_size` | `1.0` | Size of the panel's text (50 to 300 %), on top of Size under Meter look |

The journal and the history, under Journal:

| Setting | Key in settings.json | Default | What it does |
|---|---|---|---|
| Keep a journal | `journal` | `true` | Off: the journal key does nothing and the journal is never drawn |
| Fights kept | `history_size` | `10` | How many finished fights are kept for the summary and the journal (1 to 32) |
| Save between sessions | `history_file` | `false` | Keeps the fights in `history.json`, so that they are still there after a restart of the game, see "Files the mod writes" |

Without "Save between sessions" the history is kept only while the game runs; it is empty after a restart.

Keys and Other:

| Setting | Key in settings.json | Default | What it does |
|---|---|---|---|
| Meter | `toggle_key` | `117` (F6) | Shows / hides the window. A Windows virtual-key code: select it, press Enter, then the key you want |
| Journal | `journal_key` | `118` (F7) | The same. No two of the three keys can be one key (a show/hide key of F7 gives the journal F8 and the settings window F9) |
| Settings | `settings_key` | `119` (F8) | The same |
| Language | `language` | `auto` | `auto` (Same as game) follows the game's language (English or Russian; any other game language gives English), or `en`, `ru` |
| Debug | `debug` | `false` | Writes `debug.log` and `collect.jsonl`, see below |

## The look of the window

The window is drawn in the colours of the game's own menus and HUD, in one of two looks (Style under Meter look in
the settings):

- No panel (`frameless`, the default). Like the game's control hints: light warm text straight over the scene, a
  header with a larger title and a thin bronze line under it, and under each character's name a thin bar on a dark
  track. Each block (damage, damage to the party, healing, and in the summary the enemies, allies and armor) starts on
  a dark band that fades out to the right, with a short coloured mark at its left and the block's title in its colour
  (gold for damage, light purple for the damage to the party and the enemies, light green for healing, dim for the
  rest). The damage, damage to the party and healing blocks also show their total at the right of the band. Who hit
  your party ("Goblin → Guts") is written in light purple. In the summary each enemy has a purple diamond, an empty
  one with a dim name once it (or every enemy of its row) was killed. In a character's details the column headings
  sit on such a band and every second row is faintly darker. For bright scenes (snow, the sky) you can turn on a soft
  dark halo behind the text.
- Panel (`panel`). The bars as wide as a row with the names and numbers on them, on a dark warm panel with square
  corners and thin bronze lines between the rows.

In both looks the text has a dark shadow and the numbers a thin dark outline, so they stay readable on any scene.

The colour of a bar tells who it is. Your party's bars, for damage and for healing, have the colour of each
character's vocation, like its crest: Fighter red, Archer gold, Mage light blue, Thief green, Warrior dark red,
Sorcerer blue, Mystic Spearhand red-brown, Magick Archer steel blue, Trickster purple, Warfarer bronze. When two or
three party members have the same vocation, the second is a lighter and the third a darker shade of it (by their
place in the party: you, then the main pawn, then the support pawns). A party member whose vocation the mod could
not read is grey. Allies are a warm grey, "Other" a darker grey, and the rows of "Damage to party" purple like the
game's enemy health bars. The mod reads the vocations with the party, so a fight in the history keeps the colours
it had. The journal uses the same bands and colours on its own dark panel.

The mouse works the same in both looks: with REFramework's menu open, click a name or its bar to see the details,
use the ‹, the arrows and the ×, and drag the window by its header or a block's title to move it. Halo and Bars are
in the settings list only without the panel.

## Files the mod writes

The mod's own files are only under `reframework\data\DD2DamageMeter\`. It also writes a few lines to REFramework's
log, `re2_framework_log.txt` in the game folder, such as its name and version when it loads.

- `settings.json` - your settings.
- `debug.log` - only with Debug on: notes for the developer. A line for every finished or dropped fight, followed by
  the enemy plate's cost (frames shown, builds, average and largest time per frame in ms) and the time the reads for
  `collect.jsonl` took; the hidden stats panel's cost each time it stops being shown; a fight that goes on after a
  short break of the battle; once a game session, each screen whose panel was placed at a spot measured beforehand
  because a part of the game's layout could not be read, and augments that cannot be read for `collect.jsonl`; when
  the player character goes or comes back and when the scene changes (a load, a return to the title); a file the mod
  could not write; and the errors it caught (a handler that fails again and again is reported now and then, not every
  time). It starts afresh in each game session (each start of the game, or REFramework's "Reset Scripts"), replacing
  the previous session's log, and stops growing at 5 MB.
- `collect.jsonl` - only with Debug on, and never while the game is paused: what the mod meets in the game, so that
  the developer can check the enemy plate, the damage figures and the hidden stats against it. One line of JSON for
  each new thing: each kind of enemy's damage table in each of its states, each weapon in each hand and every change
  of its enchant, each attack that got the game's bonus for the enemy's state, each kind of hit on an enemy that had
  no source (a fall, a slam, a burn nobody can be blamed for), every time the game recreates a party member's
  character, and every change of your augments or equipment that changed your numbers (a `stat_check` line, at most
  300 a game session; see "Help check the hidden stats"). A thing already written comes again only in a later game
  session. It is kept across game sessions: new lines go at the end, and it stops growing at 200 MB (`debug.log` then
  says so). You can delete it at any time.
- `history.json` - only with "Save between sessions" on: the kept fights, newest first, with everything the
  journal shows. It is written again after every kept fight and when you switch the setting on, and read once per
  game session (when the game starts, or when you switch the setting on); its fights come after the ones of this
  session, as many as "Fights kept" allows. It never grows past 4 MB: the oldest fights that do not fit are left out.
  A file that is broken or of another format is ignored (the next kept fight writes a new one). With the setting off
  the mod never reads, writes or deletes it.

## Known limits

- The multipliers in the journal are measured on the hits of your party and its allies: an enemy part or damage
  type none of them hit has none, and the "What the game says" tags can differ from them (an enemy can take ×0.5
  from lightning without the game's "resists" tag); the journal shows both, each under its own title.
- Arrows to the head show ×1.0: that is what the game applies to them, whatever its own tables say.
- The names of the elements (fire, ice, lightning, holy, dark) are the mod's own words; the game has none of its
  own for them. The status names and the defense labels are the game's.
- Enemy attacks have no names in the journal: the game has only internal names for them, so an attack is its damage
  type and element with the number of hits ("Blunt ×5, Fire ×1").
- Of the heal skills only the mage's healing spot and Argent Tonic are recognised (a heal with no other source up to
  10 frames after a party member's Argent Tonic ends is hers): healing of a party member or an ally by any other
  skill is that character's own "Regeneration" (see below), in the window and in the journal's Healing tab.
- The damage that counts is the health actually taken off: a hit of 4694 on an enemy with 28 health counts as 28.
  The full damage with overkill is in a character's details.
- Burning, poison, shock and other status conditions: their damage is credited to whoever applied the condition
  when the game tells it. Otherwise such a tick on an enemy is a grey "Other" row in the "Damage to enemies" block
  and in the summary, and damage to your party with no known source is an `Other → <member>` row. Grey rows are
  not in the totals or shares.
- What a character does to itself is not "Other". A party member's own health cost is a `Blood Pact → <member>` row
  (the Warrior's Blood Pact equipped; else `Self → <member>`), never damage dealt. The healing of a party member or an
  ally with no known source is that character's own: "Lifesteal" when it is at least 10 health and comes from the
  start of a hit of theirs on an enemy to 3 frames after it (whether or not the hit took any health), else
  "Regeneration".
- A hit on an enemy with no attacker that is no status tick (a fall, a slam after being blown away, a part breaking
  off) is the damage of whoever on your side (party or ally) hit that enemy last, if that was at most 3 seconds
  before: it counts in the skill of that hit, and its damage number is in that character's colour. Otherwise it is
  the grey "Falls and environment" row, shown and hidden with "Other"; on enemies "Other" keeps only the status
  ticks nobody can be found for. An enemy of two bodies with one health pool (the Evil Eye) loses on its other body
  what the hit body lost: that copy is not counted at all, and the two bodies are one enemy.
- Healing goes to whoever used the item, or to the mage whose healing area touches the character. The game goes on
  healing for about 4 seconds after the area stops touching someone, so a small heal (up to 50 health at a time) up
  to 6 seconds after the area last touched that character is still the mage's (the mage whose area touched last, if
  two mages heal). Anything else that heals a character a little at a time in those 6 seconds is counted for the
  mage too. A pause in the middle of such a heal can push the rest of it to "Regeneration": the mod's clock, like
  the fight timer, runs on in the pause menu. The 6 seconds do not reach into a new fight, unless the area touched
  the character just as the fight began. Healing the mod cannot link to a mage or an item, such as a heal that
  starts long after the area is gone, or more than 50 health at once after the area stopped touching (a sudden jump
  to full health), is the character's own "Regeneration".
- "Enemy defence absorbed", "Party armor absorbed" and (in a character's details) "Armor absorbed" show the
  percentage the game's calculation took off, and the health it saved is recalculated from it, hence the "≈". They
  cover armor and defence only, not the body-part multiplier or a shield block (the shield has its own line in the
  details, "Blocked by shield").
- Enemy names come in the game's language, not the mod's. Skill and item names follow the mod's language, whatever
  language the game runs in (the game has them in every language).
- An enemy the game has no name for shows as "Unnamed enemy".
- A pawn's name in the window can switch between its name and its nickname, exactly as the game does.
- If a game update changes something the mod needs, "Game update? Methods not found: N" shows as the last line of
  the window during a fight (and under the summary), and always in the mod's part of REFramework's menu; the mod
  keeps doing what it still can. REFramework's log (`re2_framework_log.txt` in the game folder) lists the missing
  methods.
- REFramework's log can also show an "Internal game exception" error that names get_DrawSelf when a menu closes or
  an enemy dies or disappears. That is the game reporting that a screen or health bar the mod was watching is gone;
  the mod catches it and goes on, and it does no harm.
- Loading a save ends the fight in progress.
- The summary appears 3 seconds after the battle music stops, since a fight ends 3 seconds after the game's battle
  does. Those 3 seconds are not in the fight's length.
- A fight that started with a hit, and that the battle mode never confirmed, ends after 10 seconds without a hit
  between your party and an enemy (burn, poison and other status ticks do not count as hits).
- A creature with less than 100 health, such as a chicken, is never an enemy, even when the game calls it hostile:
  hitting it starts no fight and it is not listed (a deer, 250 health, is an enemy).
- The journal leaves out rows of 0 (a blocked blow, a grab), except a damage type or skill the enemy fully absorbed
  ("no effect"), and the Record leaves out hits that took no health, unless one killed; the totals are the same
  either way.
- Fire, poison and other status damage that your party's characters apply counts as their damage and makes the enemy
  part of the fight; a blow on a corpse does not. What others did to an enemy before your party fought it is added
  once it does (in the debug log, `held=` is the number of hits that waited and never got counted).
- A fight in which no direct hit passed between your party and a living enemy (only battle music, or only
  burn/poison ticks) is not kept.
- The fight timer also counts the time spent in the pause menu, so the per-second figures drop after a pause.
- The window uses REFramework's default font; there is no font setting. Japanese, Chinese and Korean text is not
  a goal of this version.
- Health numbers appear only where the game shows its own health bar: over an enemy's head or at the boss bar at
  the top of the screen. An enemy whose bar the game does not show gets none.
- At the boss bar the numbers are the boss's whole health, not the 50 000-health segments of the game's bar (each
  diamond under the bar is one more segment): a boss with 150 000 health can show "120 000 / 150 000 · 80%" beside
  a bar that looks full.

## Report a bug

1. In the settings window (F8) turn on Debug (under Other).
2. Repeat what went wrong.
3. Report it in the Bugs tab of the mod's Nexus page or in the [Issues of its GitHub repository](https://github.com/tslaceo/DD2HiddenNumbers/issues),
   and attach `reframework\data\DD2DamageMeter\debug.log` (before the next game session, which replaces it) and
   REFramework's log, `re2_framework_log.txt` in the game folder. If it is about the enemy plate (a weakness that is
   wrong or missing), attach `reframework\data\DD2DamageMeter\collect.jsonl` too: it holds every enemy table the mod
   read while Debug was on. Say what you saw and what you expected, and give the game version, the REFramework version
   and the mod's version. The mod's version is in the name of the archive (`HiddenNumbers-<version>.zip`) and in
   REFramework's log: look for "Hidden Numbers", the line `[DD2DamageMeter] Hidden Numbers <version> loaded ...`.

## Build from source

- Tests: Lua 5.4 - `for f in tests/*_test.lua; do lua "$f" || exit 1; done` (Git Bash, from the repository root).
- Deploy into the game: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -GameDir "<game folder>"`
  (keeps your settings).
- Release archive: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1` ->
  `out\HiddenNumbers-<version>.zip`.

## Credits

- praydog and the REFramework contributors.
- The public sources of the [Damage Number](https://www.nexusmods.com/dragonsdogma2/mods/148) mod by xyzkljl1
  ([xyzkljl1/MyDD2Mod](https://github.com/xyzkljl1/MyDD2Mod) on GitHub) and gigvit's public DD2 modding notes (in
  [docs/archive](https://github.com/gigvit/Pawn-Hybrid-Vocations-AI/tree/main/docs/archive) of his Pawn Hybrid
  Vocations AI repository on GitHub) were read to learn which game methods report a hit and a status condition. No
  code of theirs is used.
- The hidden stats were checked against
  [Clear Effect Descriptions 2.0](https://www.nexusmods.com/dragonsdogma2/mods/314) by Filipe Ramos and
  [Better Better Item Description](https://www.nexusmods.com/dragonsdogma2/mods/338) by xyzkljl1. Where both read a
  number the same way and we read it differently, the panel takes their reading. No code or text of theirs is used.

## AI disclosure

The code, tests and documentation of this mod were written by Claude (Anthropic's AI model) under the direction
of tslaceo, who chose what it does, tested it in the game and decided what ships.

## License

MIT - see [LICENSE](LICENSE). The mod ships no extracted game data, assets or game text: every name it shows is read
from the running game. The code holds a few fragments of the game's internal Japanese attack names, used only to
recognise attacks (in `names.lua`, `game\hits.lua`, `view.lua` and `journal_tabs.lua` in
`reframework\autorun\DD2DamageMeter`).
