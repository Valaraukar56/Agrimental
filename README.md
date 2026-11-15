# Agrimental (prototype)

Jeu incrémental agricole : un hangar central entouré de champs de blé. On balaie les champs pour récolter, on revient vendre au hangar, on améliore ses outils au PC, puis on automatise avec des ouvriers. Vider un champ à 100 % donne une prime.

## Lancer en local

`fetch()` ne marche pas en double-cliquant sur `index.html`, il faut un petit serveur :

```bash
python -m http.server 8080
```

Puis ouvrir http://localhost:8080. Sur GitHub Pages, ça marche tel quel.

## Version Godot 4 (prototype 3D greybox)

Ouvrir le dossier racine dans Godot 4.6 (`project.godot`), puis F5.
- ZQSD ou flèches : bouger. Marcher sur le blé récolte, entrer dans le hangar vend, s'approcher du PC bleu ouvre les améliorations. F9 efface la sauvegarde.
- Elle lit les **mêmes** `data/*.json` que la version web : un changement d'équilibrage s'applique aux deux.
- `godot/core/` : port 1 pour 1 de `js/core/` (même API, signaux à la place des événements).
- `godot/main.gd` : monde 3D construit par code. Ses constantes (distance hangar-champs, vitesse, rayon de récolte) règlent la sensation, pas l'économie.
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
- Principe : les améliorations d'outils (sac, faucille) arrivent AVANT le premier champ. Premier achat vers 25 s, champ 2 vers 5 min.
- Repères simulés (joueur actif ~10 épis/s en marchant, aller-retour hangar 5 à 8 s, achète toujours l'option la moins chère) : champ 2 à 5 min, champ 3 à 9 min, champ 4 à 19 min, champ 5 à 29 min, champ 6 à 43 min, champ 7 à 64 min, champ 8 (dernier) à 1 h 46. Un achat toutes les 10 à 25 s avant 30 min, 30 à 60 s vers 30-60 min, 1 à 2 min après 1 h.
- Les coûts de champ (500, 1 800, 5 400, 16 000, 48 000, 145 000, 440 000, ratio ~3) et les `costGrowth` sont réglés ensemble : si on change l'un, rejouer la simulation.
- Si le joueur attend plus de 2 min entre deux achats, baisser `baseCost` ou `costGrowth`. S'il achète tout sans réfléchir, monter `costGrowth`.

Console du navigateur : `game.state.money += 1000` pour tester.
