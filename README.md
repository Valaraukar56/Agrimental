# Agrimental (prototype)

Jeu incrémental agricole : un hangar central entouré de champs de blé. On balaie les champs pour récolter, on revient vendre au hangar, on améliore ses outils au PC, puis on automatise avec des ouvriers. Vider un champ à 100 % donne une prime.

## Lancer en local

`fetch()` ne marche pas en double-cliquant sur `index.html`, il faut un petit serveur :

```bash
python -m http.server 8080
```

Puis ouvrir http://localhost:8080. Sur GitHub Pages, ça marche tel quel.

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
- Coût d'une amélioration : `baseCost × costGrowth^niveau` (`costGrowth` entre 1.07 et 1.15 dans les idle "lents", 1.18 à 1.35 ici).
- Effet : `add` (linéaire) ou `mul` (multiplicatif par niveau).
- Prime de champ propre : `nb tuiles × blé par épi × prix × completionBonusRatio`.
- Principe : les améliorations d'outils (sac, faucille) arrivent AVANT le premier champ. Premier achat vers 7 s, champ 2 vers 3 min 30.
- Repères actuels (simulés, joueur actif ~4 épis/s, aller-retour au hangar ~2 s) : champ 3 vers 5 min, champ 5 vers 15 min, champ 7 vers 50 min, champ 8 (dernier) vers 1 h 50. Un achat toutes les 10 à 20 s au début, 1 min vers 30-60 min, 2 à 3 min après 1 h.
- Les coûts de champ (300, 900, 3 000, 12 000, 50 000, 200 000, 800 000) et les `costGrowth` (1,18 à 1,35) sont réglés ensemble : si on change l'un, rejouer la simulation.
- Repère : on vise qu'un nouvel achat prenne de 30 s à 2 min. Si le joueur attend plus, baisser `baseCost` ou `costGrowth`. S'il achète tout sans réfléchir, monter `costGrowth`.

Console du navigateur : `game.state.money += 1000` pour tester.
