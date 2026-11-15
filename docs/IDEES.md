# Idées pour après la V1

Règle : rien ici ne se code tant que la V1 n'est pas en ligne et jouée.

## Drones assignés à un champ (V2, pensé pour la 3D Godot)

Remplace l'ouvrier agricole actuel (`farmhand`, récolte instantanée et aléatoire).

- Chaque drone est **assigné à un champ** par le joueur : c'est une nouvelle décision (où envoyer ses drones).
- Un drone fait des **allers-retours** : hangar, puis champ (récolte jusqu'à remplir sa soute), puis retour au hangar pour déposer et vendre.
- Le rendement dépend de la **distance** hangar-champ, de la **vitesse** et de la **soute**. Ce sont de nouveaux leviers d'amélioration.

### Principe d'architecture (important pour le portage)
La logique simule les trajets avec des **minuteurs**, sans aucune position à l'écran :

```
drone = { id, fieldId, state: "aller" | "recolte" | "retour", timeLeft, cargo }
```

- `js/core/` fait avancer `timeLeft` dans `tick(dt)` et change d'état.
- L'affichage (2D ou 3D) ne fait qu'**interpoler** la position entre le hangar et le champ selon `state` et `timeLeft`.
- Dans Godot, la scène 3D lit le même état : la 3D ne change pas l'équilibrage.

### Données à prévoir
- `fields.json` : une `distance` par champ (secondes de vol à la vitesse de base).
- `upgrades.json` : vitesse des drones, taille de soute, nombre de drones.
- Rejouer la simulation d'équilibrage (agent `equilibrage`) : remplace `autoHarvestRate`.

## Autres pistes (non triées)
- Progression hors ligne (gains pendant que le jeu est fermé).
- Autres cultures, avec un temps de repousse et un prix différents.
