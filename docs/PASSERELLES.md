# Passerelles (interfaces entre les couches)

> Le portage Godot existe : `godot/core/game.gd` (classe `Game`), `game_state.gd`, `formulas.gd`, `data_loader.gd`, `godot/platform/storage.gd`.
> Les noms de fonctions passent en snake_case (`harvestTile` devient `harvest_tile`), les événements deviennent des signaux (`fieldCompleted` devient `field_completed`).
> **La version web est gelée** : `godot/core/` est la référence. Les nouveautés (équipements, puis drones) ne sont codées que côté Godot.
>
> Ajouts Godot uniquement :
> - Données : `data/equipment.json` (paliers : `cost`, `model` = `pied`/`vehicule`, `set` remplace des stats, `add` s'y ajoute). Stats : base, puis `set`, puis `add`, puis améliorations.
> - État : `equipment` (id du palier possédé).
> - API : `equipment_index()`, `current_equipment()`, `next_equipment()`, `can_buy_next_equipment()`, `buy_next_equipment()`. Signal : `equipment_bought(id)`.
> - Drones : `data/drones.json` (améliorations ajoutées à la liste au chargement), stats `droneCount`, `droneSpeed`, `droneCargo`, `droneHarvestRate` dans `balance.baseStats`. L'ouvrier (`farmhand`, marqué `webOnly`) est ignoré par Godot ; une sauvegarde avec N ouvriers reçoit N drones.
> - État : `drones` (un dictionnaire par drone : `phase` idle/aller/recolte/retour, `field`, `t`, `dur`, `cargo`, `tile`) et `droneAssign` (`{ field_id: nombre }`).
> - API drones : `drone_count()`, `assigned_count(field)`, `total_assigned()`, `assign_drone(field, +1/-1)`, `field_distance(field)`. Signal : `drone_delivered(index, value)`. Source de récolte `"drone"` dans `harvest_tile`.
> - Disposition : `godot/core/layout.gd` (`Layout.compute(data)`, lit `balance.world`) sert à la fois au placement 3D et à la distance de vol des drones.

Règle : **données → logique → affichage**, jamais l'inverse.
- `data/*.json` ne contient que des chiffres et des textes.
- `js/core/` ne touche ni au DOM ni à `localStorage`. C'est la partie à réécrire en GDScript.
- `js/ui/` lit l'état et appelle l'API de `Game`. Elle ne modifie jamais `game.state` directement.
- `js/platform/` isole tout ce qui dépend du navigateur (stockage).

## 1. Données (JSON) → logique

| Fichier | Contenu | Lu par | Équivalent Godot |
|---|---|---|---|
| `data/crops.json` | cultures : prix de vente, temps de repousse | `game.js`, `formulas.js` | même JSON, ou `Resource` `CropData` |
| `data/fields.json` | champs : taille de grille, coût de déblocage, position autour du hub | `state.js`, `game.js`, `ui.js` (slot) | même JSON |
| `data/upgrades.json` | améliorations : stat ciblée, opération (`add`/`mul`), coût | `formulas.js` | même JSON |
| `data/balance.json` | stats de départ, ratio de prime, clé et intervalle de sauvegarde | `formulas.js`, `state.js`, `main.js` | même JSON |

Chargement : `js/data/loader.js` → `loadData()` renvoie `{ crops, fields, upgrades, balance }`.
Godot : `FileAccess.get_file_as_string()` + `JSON.parse_string()`.

## 2. Logique → affichage : API publique de `Game` (`js/core/game.js`)

Godot : un autoload `Game.gd` exposant les mêmes fonctions.

**Lecture**
| Fonction | Retour |
|---|---|
| `state` | état brut (argent, sac, niveaux, champs, totaux) |
| `stats` | stats effectives après améliorations |
| `fieldDef(id)` / `upgradeDef(id)` | définition JSON |
| `upgradeLevel(id)`, `getUpgradeCost(id)`, `isUpgradeMaxed(id)`, `canBuyUpgrade(id)` | infos d'amélioration |
| `canUnlockField(id)`, `ripeCount(fieldId)` | infos de champ |
| `sackCount()`, `sackValue()`, `sackFree()` | infos du sac |

**Actions** (renvoient `true`/`false` ou une valeur)
| Fonction | Effet |
|---|---|
| `harvestTile(fieldId, idx, source)` | récolte une tuile (`player` → sac, `auto` → vendu directement) |
| `harvestNext(fieldId)` | récolte le premier épi mûr (mode sans grille) |
| `sell()` | vend le sac au hangar |
| `buyUpgrade(id)` | achète un niveau |
| `unlockField(id)` | débloque un champ |
| `tick(dt)` | avance le temps de `dt` secondes (repousse de chaque épi, ouvriers) |
| `serialize()` | état prêt à sauvegarder |

## 3. Événements (logique → affichage)

`game.events.on(nom, fn)`. Godot : `signal`.

| Événement | Données | Usage UI actuel |
|---|---|---|
| `tileHarvested` | `{ fieldId, idx, source, amount }` | (libre : son, particules) |
| `fieldCompleted` | `{ fieldId, bonus }` (toutes les tuiles coupées en même temps) | flash + texte « Champ propre ! » |
| `tileRegrown` | `{ fieldId, idx }` | (libre ; Godot : signal `tile_regrown`) |
| `sackFull` | - | le sac tremble |
| `sold` | `{ value }` | (libre) |
| `upgradeBought` | `{ id, level }` | (libre) |
| `fieldUnlocked` | `{ id }` | reconstruit la carte |

## 4. Plateforme (`js/platform/storage.js`)

| Fonction | Rôle | Godot |
|---|---|---|
| `loadSave()` / `writeSave(obj)` / `clearSave()` | sauvegarde de l'état de jeu | `FileAccess` sur `user://save.json` |
| `loadPref()` / `savePref()` | préférences d'affichage (grille on/off) | `ConfigFile` |

État d'un champ : `{ unlocked, tiles: [1 mûr | 0 coupé], regrow: [secondes avant repousse, par tuile] }`.

`state.js → migrate()` rend une vieille sauvegarde compatible si les JSON changent (champ ajouté, grille redimensionnée).

## 5. Orchestration (`js/main.js`)

Charge les données, crée `Game`, crée l'UI, boucle `tick(dt)` + `ui.update()` à chaque frame, sauvegarde toutes les `saveIntervalSec` secondes et à la fermeture.
Godot : `_process(delta)` dans la scène principale.
