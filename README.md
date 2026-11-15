# Agrimental (prototype)

Jeu incrémental agricole : un hangar central entouré de champs de blé. On balaie les champs pour récolter, on revient vendre au hangar, on améliore ses outils au PC, puis on automatise avec des ouvriers. Vider un champ à 100 % donne une prime.

> **Version de référence : Godot (3D).** La version web est **gelée** depuis l'ajout des équipements : elle reste en ligne comme V1, ne reçoit plus de nouveautés, et ignore `data/equipment.json`. On la corrige seulement si un changement de `data/` la casse.

## Lancer la version web (gelée)

`fetch()` ne marche pas en double-cliquant sur `index.html`, il faut un petit serveur :

```bash
python -m http.server 8080
```

Puis ouvrir http://localhost:8080. Sur GitHub Pages, ça marche tel quel.

## Version Godot 4 (prototype 3D greybox)

Ouvrir le dossier racine dans Godot 4.6 (`project.godot`), puis F5.
- ZQSD ou flèches : bouger. Marcher sur le blé récolte, entrer dans le hangar vend, s'approcher du PC bleu ouvre les améliorations et les équipements. F9 efface la sauvegarde. F8 donne +10 000 (Maj+F8 : +1 000 000), seulement depuis l'éditeur.
- Équipements à paliers (`data/equipment.json`) : Faucille, Faux, Débroussailleuse, Moissonneuse (véhicule). Chaque palier remplace le précédent et fixe le rayon de récolte (`harvestRadius`, visible au sol) et la vitesse (`moveSpeed`).
- `godot/core/` : logique pure, issue du port de `js/core/` (même API, signaux à la place des événements). Les équipements n'existent que côté Godot.
- `godot/main.gd` : monde 3D construit par code. Ses constantes (écart hangar-champs, caméra) règlent la sensation, pas l'économie.
- Tests headless :
  `Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://godot/tests/test_game.gd` (même chose avec `test_scene.gd`).
- Les dossiers `js/`, `css/` et `docs/` contiennent un `.gdignore` pour que Godot les ignore.

## Structure

```
index.html          page unique
css/style.css       style (volontairement moche)
data/*.json         TOUT l'équilibrage : cultures, champs, améliorations, constantes
js/core/            logique pure (portable vers Godot)
js/ui/ui.js         affichage DOM
js/platform/        localStorage
js/data/loader.js   chargement des JSON
js/main.js          boucle de jeu et branchements
docs/PASSERELLES.md liste de chaque interface entre couches
```

## Équilibrer

Tout se règle dans `data/`, sans toucher au code.
- Coût d'une amélioration : `baseCost × costGrowth^niveau`.
- Effet : `add` (linéaire) ou `mul` (multiplicatif par niveau).
- Repousse par épi : chaque épi récolté repousse seul après `crops.wheat.growTime × growTimeMult` secondes (base 40 s). Débit max d'un champ = tuiles / temps de repousse.
- Prime de champ propre : `nb tuiles × blé par épi × prix × completionBonusRatio`, quand toutes les tuiles sont récoltées en même temps (vider le champ plus vite qu'il ne repousse).
- Échelle : champs de 15x10 à 30x25, épi de base à 1 pour 1 : c'est l'échelle des coûts qui donne la sensation "l'épi vaut peu".
- Principe : les améliorations d'outils (sac, lame) arrivent AVANT le premier champ. Premier achat vers 25 s.
- Équipements (`data/equipment.json`, Godot) : débit en marchant ≈ `moveSpeed × 2 × harvestRadius` épis/s. Le sac doit rester assez grand pour que ce débit compte (sinon le joueur passe son temps en trajets) : c'est pourquoi "Grand sac" donne +150 places par niveau.
- Principe de phases : chaque outil a sa propre phase de jeu, on ne passe pas au suivant en quelques minutes. Repères simulés (joueur actif, achète toujours l'option la moins chère) : Faux à 15 min, Débroussailleuse à 35 min, Moissonneuse à 67 min. Durées : Faucille 15 min, Faux 20 min, Débroussailleuse 32 min, Moissonneuse 50 min jusqu'au dernier champ. Champs 2 à 8 : 3,5 / 8,8 / 16 / 24 / 37 / 77 / 118 min. Pendant chaque phase on continue d'acheter (améliorations, champs) : 85 / 66 / 40 / 30 achats, écart max 30 / 30 / 75 / 146 s.
- Prix des paliers : Faux 7 000, Débroussailleuse 65 000, Moissonneuse 300 000. Rayons 0,9 / 1,5 / 2,2 / 3,2 et vitesses 6 / 6 / 7 / 10 inchangés.
- Les coûts de champ (250, 2 700, 8 100, 24 000, 72 000, 400 000, 900 000), les prix de paliers et les `costGrowth` (lame 1,11, sac 1,15, engrais 1,2, ouvrier 1,12) sont réglés ensemble : si on change l'un, rejouer `python tools/sim_equilibrage.py` (il lit les JSON, y compris growTime et capacité de départ).
- Si le joueur attend plus de 2 min entre deux achats, baisser `baseCost` ou `costGrowth`. S'il achète tout sans réfléchir, monter `costGrowth`.

Pour tester : console du navigateur `game.state.money += 1000` (web), ou modifier `user://save.json` (Godot).
