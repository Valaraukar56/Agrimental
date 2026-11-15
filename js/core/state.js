// Etat du jeu : uniquement des donnees serialisables (JSON).
// Tuile : 1 = epi mur, 0 = recolte.

function freshField(def) {
  return {
    unlocked: def.unlockCost === 0,
    tiles: new Array(def.width * def.height).fill(1),
    regrowLeft: 0,
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
      f.tiles = s.tiles;
      f.regrowLeft = Number(s.regrowLeft) || 0;
    }
  }
  return state;
}
