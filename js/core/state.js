// Etat du jeu : uniquement des donnees serialisables (JSON).
// Tuile : 1 = epi mur, 0 = recolte. regrow[i] = secondes avant repousse de la tuile i.

function freshField(def) {
  return {
    unlocked: def.unlockCost === 0,
    tiles: new Array(def.width * def.height).fill(1),
    regrow: new Array(def.width * def.height).fill(0),
  };
}

export function createState(data) {
  const fields = {};
  for (const def of data.fields) fields[def.id] = freshField(def);
  return {
    version: data.balance.saveVersion,
    money: data.balance.startMoney,
    sack: {},              // { cropId: quantite }
    upgrades: {},          // { upgradeId: niveau }
    fields,
    totals: { earned: 0, tilesHarvested: 0, fieldsCompleted: 0 },
    playTime: 0,
  };
}

// Recharge une sauvegarde en tolerant les changements de donnees JSON
// (champ ajoute, taille de grille modifiee, etc.).
export function migrate(saved, data) {
  const state = createState(data);
  if (!saved || typeof saved !== 'object') return state;
  state.money = Number(saved.money) || 0;
  state.sack = saved.sack || {};
  state.upgrades = saved.upgrades || {};
  state.totals = { ...state.totals, ...(saved.totals || {}) };
  state.playTime = Number(saved.playTime) || 0;
  for (const def of data.fields) {
    const s = saved.fields?.[def.id];
    if (!s) continue;
    const f = state.fields[def.id];
    f.unlocked = !!s.unlocked || f.unlocked;
    if (Array.isArray(s.tiles) && s.tiles.length === f.tiles.length) {
      f.tiles = s.tiles.map(t => (t === 1 ? 1 : 0));
      if (Array.isArray(s.regrow) && s.regrow.length === f.tiles.length) {
        f.regrow = s.regrow.map(t => Number(t) || 0);
      } else {
        // ancienne sauvegarde (repousse par champ) : les tuiles coupees repoussent normalement
        const full = data.crops[def.crop].growTime;
        f.regrow = f.tiles.map(t => (t === 1 ? 0 : full));
      }
    }
  }
  return state;
}
