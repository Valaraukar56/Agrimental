// API du jeu. AUCUN acces au DOM ni a localStorage ici :
// c'est ce fichier qui sera reecrit en GDScript (autoload "Game").
import { Emitter } from './events.js';
import { upgradeCost, computeStats, growTime, completionBonus } from './formulas.js';
import { createState, migrate } from './state.js';

export class Game {
  constructor(data, saved = null) {
    this.data = data;
    this.events = new Emitter();
    this.state = saved ? migrate(saved, data) : createState(data);
    this.autoAcc = 0;
    this.recompute();
  }

  // ---------- Lecture ----------
  recompute() { this.stats = computeStats(this.data, this.state); }
  fieldDef(id) { return this.data.fields.find(f => f.id === id); }
  upgradeDef(id) { return this.data.upgrades.find(u => u.id === id); }
  upgradeLevel(id) { return this.state.upgrades[id] || 0; }
  sackCount() { return Object.values(this.state.sack).reduce((a, b) => a + b, 0); }
  sackValue() {
    return Object.entries(this.state.sack)
      .reduce((sum, [crop, n]) => sum + n * this.data.crops[crop].sellPrice, 0);
  }
  sackFree() { return Math.max(0, this.stats.sackCapacity - this.sackCount()); }
  ripeCount(fieldId) { return this.state.fields[fieldId].tiles.reduce((a, t) => a + t, 0); }
  getUpgradeCost(id) { return upgradeCost(this.upgradeDef(id), this.upgradeLevel(id)); }
  isUpgradeMaxed(id) {
    const def = this.upgradeDef(id);
    return def.maxLevel != null && this.upgradeLevel(id) >= def.maxLevel;
  }
  canBuyUpgrade(id) { return !this.isUpgradeMaxed(id) && this.state.money >= this.getUpgradeCost(id); }
  canUnlockField(id) {
    const f = this.state.fields[id];
    return !f.unlocked && this.state.money >= this.fieldDef(id).unlockCost;
  }

  // ---------- Actions ----------
  addMoney(n) {
    this.state.money += n;
    this.state.totals.earned += n;
  }

  // source : 'player' (va dans le sac) ou 'auto' (vendu directement)
  harvestTile(fieldId, idx, source = 'player') {
    const f = this.state.fields[fieldId];
    if (!f || !f.unlocked || f.tiles[idx] !== 1) return false;
    const def = this.fieldDef(fieldId);
    const amount = this.stats.yieldPerTile;

    if (source === 'player') {
      const free = this.sackFree();
      if (free <= 0) { this.events.emit('sackFull'); return false; }
      this.state.sack[def.crop] = (this.state.sack[def.crop] || 0) + Math.min(amount, free);
    } else {
      this.addMoney(amount * this.data.crops[def.crop].sellPrice);
    }

    f.tiles[idx] = 0;
    f.regrow[idx] = growTime(this.data, this.stats, def.crop);
    this.state.totals.tilesHarvested++;
    this.events.emit('tileHarvested', { fieldId, idx, source, amount });
    if (f.tiles.every(t => t === 0)) this.completeField(fieldId);
    return true;
  }

  // Mode sans grille : recolte le premier epi mur
  harvestNext(fieldId, source = 'player') {
    const idx = this.state.fields[fieldId].tiles.indexOf(1);
    return idx >= 0 && this.harvestTile(fieldId, idx, source);
  }

  // Prime quand toutes les tuiles sont coupees en meme temps
  completeField(fieldId) {
    const bonus = completionBonus(this.data, this.stats, this.fieldDef(fieldId));
    this.addMoney(bonus);
    this.state.totals.fieldsCompleted++;
    this.events.emit('fieldCompleted', { fieldId, bonus });
  }

  sell() {
    const value = this.sackValue();
    if (value <= 0) return 0;
    this.addMoney(value);
    this.state.sack = {};
    this.events.emit('sold', { value });
    return value;
  }

  buyUpgrade(id) {
    if (!this.canBuyUpgrade(id)) return false;
    this.state.money -= this.getUpgradeCost(id);
    this.state.upgrades[id] = this.upgradeLevel(id) + 1;
    this.recompute();
    this.events.emit('upgradeBought', { id, level: this.state.upgrades[id] });
    return true;
  }

  unlockField(id) {
    if (!this.canUnlockField(id)) return false;
    this.state.money -= this.fieldDef(id).unlockCost;
    this.state.fields[id].unlocked = true;
    this.events.emit('fieldUnlocked', { id });
    return true;
  }

  // ---------- Boucle ----------
  tick(dt) {
    this.state.playTime += dt;

    // Repousse tuile par tuile
    for (const def of this.data.fields) {
      const f = this.state.fields[def.id];
      if (!f.unlocked) continue;
      for (let i = 0; i < f.regrow.length; i++) {
        if (f.regrow[i] <= 0) continue;
        f.regrow[i] -= dt;
        if (f.regrow[i] <= 0) {
          f.regrow[i] = 0;
          f.tiles[i] = 1;
          this.events.emit('tileRegrown', { fieldId: def.id, idx: i });
        }
      }
    }

    // Automatisation : ouvriers
    this.autoAcc += this.stats.autoHarvestRate * dt;
    while (this.autoAcc >= 1) {
      const target = this.pickAutoTarget();
      if (!target) { this.autoAcc = 0; break; }
      this.harvestTile(target.fieldId, target.idx, 'auto');
      this.autoAcc -= 1;
    }
  }

  // Epi mur aleatoire dans un champ debloque
  pickAutoTarget() {
    const candidates = this.data.fields.filter(d => {
      const f = this.state.fields[d.id];
      return f.unlocked && f.tiles.includes(1);
    });
    if (!candidates.length) return null;
    const def = candidates[Math.floor(Math.random() * candidates.length)];
    const tiles = this.state.fields[def.id].tiles;
    const ripe = [];
    tiles.forEach((t, i) => { if (t === 1) ripe.push(i); });
    return { fieldId: def.id, idx: ripe[Math.floor(Math.random() * ripe.length)] };
  }

  serialize() {
    return JSON.parse(JSON.stringify(this.state));
  }
}
