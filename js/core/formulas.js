// Formules d'equilibrage. Fonctions pures : (donnees, etat) -> nombre.

// Cout exponentiel classique des jeux idle : base * croissance^niveau
export function upgradeCost(def, level) {
  return Math.ceil(def.baseCost * Math.pow(def.costGrowth, level));
}

// Stats effectives = stats de base + effets de toutes les ameliorations
export function computeStats(data, state) {
  const stats = { ...data.balance.baseStats };
  for (const def of data.upgrades) {
    const lvl = state.upgrades[def.id] || 0;
    if (!lvl) continue;
    if (def.op === 'add') stats[def.stat] += def.value * lvl;
    else if (def.op === 'mul') stats[def.stat] *= Math.pow(def.value, lvl);
  }
  return stats;
}

export function growTime(data, stats, cropId) {
  return data.crops[cropId].growTime * stats.growTimeMult;
}

export function completionBonus(data, stats, fieldDef) {
  const tiles = fieldDef.width * fieldDef.height;
  const price = data.crops[fieldDef.crop].sellPrice;
  return Math.ceil(tiles * stats.yieldPerTile * price * data.balance.completionBonusRatio);
}
