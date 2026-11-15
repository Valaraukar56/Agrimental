// Affichage DOM. Ne modifie JAMAIS l'etat directement : passe par l'API de Game.
import { loadPref, savePref } from '../platform/storage.js';

const fmt = n => {
  n = Math.floor(n);
  if (n < 1e4) return String(n);
  const units = ['k', 'M', 'G', 'T'];
  let u = -1;
  while (n >= 1000 && u < units.length - 1) { n /= 1000; u++; }
  return n.toFixed(n < 10 ? 2 : n < 100 ? 1 : 0) + units[u];
};

export function createUI(root, game, { onReset }) {
  const { data } = game;
  let gridMode = loadPref('gridMode', true);
  let sweeping = false;
  const els = { fields: {} };

  // ---------- Construction ----------
  function build() {
    root.innerHTML = '';
    const map = document.createElement('div');
    map.className = 'map';

    // Hub central (hangar)
    const hub = document.createElement('section');
    hub.className = 'hub';
    hub.style.gridColumn = 2; hub.style.gridRow = 2;
    hub.innerHTML = `
      <h2>🏚️ Hangar</h2>
      <div class="money">💰 <span data-ref="money"></span></div>
      <div class="sack">
        <div>🎒 Sac : <span data-ref="sackText"></span></div>
        <div class="bar"><div class="bar-fill" data-ref="sackBar"></div></div>
      </div>
      <button class="sell" data-ref="sellBtn">Vendre la récolte</button>
      <h3>💻 PC d'amélioration</h3>
      <div class="upgrades" data-ref="upgrades"></div>
      <div class="options">
        <label><input type="checkbox" data-ref="gridToggle"> Afficher la grille</label>
        <button class="reset" data-ref="resetBtn">Réinitialiser</button>
      </div>
      <div class="stats" data-ref="stats"></div>`;
    const ref = name => hub.querySelector(`[data-ref="${name}"]`);
    Object.assign(els, {
      money: ref('money'), sackText: ref('sackText'), sackBar: ref('sackBar'),
      sellBtn: ref('sellBtn'), upgrades: ref('upgrades'), stats: ref('stats'),
      sackBox: hub.querySelector('.sack'),
    });
    ref('sellBtn').onclick = () => game.sell();
    ref('gridToggle').checked = gridMode;
    ref('gridToggle').onchange = e => { gridMode = e.target.checked; savePref('gridMode', gridMode); build(); };
    ref('resetBtn').onclick = () => { if (confirm('Effacer la sauvegarde ?')) onReset(); };

    els.upgradeRows = {};
    for (const def of data.upgrades) {
      const btn = document.createElement('button');
      btn.className = 'upgrade ' + def.category;
      btn.innerHTML = `<span class="u-name">${def.icon} ${def.name} <small data-r="lvl"></small></span>
        <span class="u-desc">${def.desc}</span><span class="u-cost" data-r="cost"></span>`;
      btn.onclick = () => game.buyUpgrade(def.id);
      els.upgrades.appendChild(btn);
      els.upgradeRows[def.id] = { btn, lvl: btn.querySelector('[data-r="lvl"]'), cost: btn.querySelector('[data-r="cost"]') };
    }
    map.appendChild(hub);

    // Champs autour
    els.fields = {};
    for (const def of data.fields) map.appendChild(buildField(def));
    root.appendChild(map);
    update();
  }

  function buildField(def) {
    const f = game.state.fields[def.id];
    const card = document.createElement('section');
    card.className = 'field' + (f.unlocked ? '' : ' locked');
    card.style.gridColumn = def.slot.col; card.style.gridRow = def.slot.row;
    const e = { card, tiles: [] };
    card.innerHTML = `<h4>${def.name}</h4>`;

    if (!f.unlocked) {
      const btn = document.createElement('button');
      btn.className = 'unlock';
      btn.textContent = `🔒 Débloquer (${fmt(def.unlockCost)} 💰)`;
      btn.onclick = () => game.unlockField(def.id);
      card.appendChild(btn);
      e.unlockBtn = btn;
    } else {
      const info = document.createElement('div');
      info.className = 'field-info';
      card.appendChild(info);
      e.info = info;

      if (gridMode) {
        const grid = document.createElement('div');
        grid.className = 'grid';
        grid.style.gridTemplateColumns = `repeat(${def.width}, var(--tile))`;
        for (let i = 0; i < def.width * def.height; i++) {
          const t = document.createElement('div');
          t.className = 'tile';
          t.dataset.field = def.id; t.dataset.idx = i;
          grid.appendChild(t);
          e.tiles.push(t);
        }
        card.appendChild(grid);
      } else {
        const btn = document.createElement('button');
        btn.className = 'harvest';
        btn.textContent = `${data.crops[def.crop].icon} Récolter`;
        btn.onclick = () => game.harvestNext(def.id);
        const bar = document.createElement('div');
        bar.className = 'bar';
        bar.innerHTML = '<div class="bar-fill"></div>';
        card.append(btn, bar);
        e.harvestBtn = btn; e.bar = bar.firstChild;
      }
    }
    els.fields[def.id] = e;
    return card;
  }

  // ---------- Mise a jour ----------
  function update() {
    const s = game.state, st = game.stats;
    els.money.textContent = fmt(s.money);
    const sc = game.sackCount();
    els.sackText.textContent = `${fmt(sc)} / ${fmt(st.sackCapacity)}`;
    els.sackBar.style.width = Math.min(100, sc / st.sackCapacity * 100) + '%';
    els.sellBtn.disabled = sc === 0;
    els.sellBtn.textContent = sc ? `Vendre la récolte (+${fmt(game.sackValue())} 💰)` : 'Sac vide';

    for (const def of data.upgrades) {
      const r = els.upgradeRows[def.id];
      const maxed = game.isUpgradeMaxed(def.id);
      r.lvl.textContent = `niv. ${game.upgradeLevel(def.id)}`;
      r.cost.textContent = maxed ? 'MAX' : `${fmt(game.getUpgradeCost(def.id))} 💰`;
      r.btn.disabled = !game.canBuyUpgrade(def.id);
    }

    els.stats.textContent =
      `Épis récoltés : ${fmt(s.totals.tilesHarvested)} · Champs finis : ${s.totals.fieldsCompleted} · Auto : ${st.autoHarvestRate} épi/s`;

    for (const def of data.fields) {
      const f = s.fields[def.id], e = els.fields[def.id];
      if (!f.unlocked) { e.unlockBtn.disabled = !game.canUnlockField(def.id); continue; }
      const total = f.tiles.length, ripe = game.ripeCount(def.id);
      e.info.textContent = f.regrowLeft > 0
        ? `🌱 Repousse dans ${Math.ceil(f.regrowLeft)} s`
        : `${ripe} / ${total} épis`;
      e.card.classList.toggle('regrowing', f.regrowLeft > 0);
      if (gridMode) {
        for (let i = 0; i < total; i++) {
          const ripeNow = f.tiles[i] === 1;
          if (e.tiles[i]._ripe !== ripeNow) {
            e.tiles[i]._ripe = ripeNow;
            e.tiles[i].classList.toggle('ripe', ripeNow);
          }
        }
      } else {
        e.harvestBtn.disabled = ripe === 0;
        e.bar.style.width = (total - ripe) / total * 100 + '%';
      }
    }
  }

  // ---------- Entrees : "balayage" souris/tactile sur la grille ----------
  function tryTileAt(x, y) {
    const t = document.elementFromPoint(x, y);
    if (t && t.classList.contains('tile')) game.harvestTile(t.dataset.field, Number(t.dataset.idx));
  }
  root.addEventListener('pointerdown', ev => {
    if (!ev.target.classList.contains('tile')) return;
    sweeping = true;
    ev.preventDefault();
    tryTileAt(ev.clientX, ev.clientY);
  });
  window.addEventListener('pointermove', ev => { if (sweeping) tryTileAt(ev.clientX, ev.clientY); });
  window.addEventListener('pointerup', () => { sweeping = false; });
  window.addEventListener('pointercancel', () => { sweeping = false; });

  // ---------- Retours visuels sur evenements ----------
  function floatText(fieldId, text) {
    const e = els.fields[fieldId];
    if (!e) return;
    const span = document.createElement('span');
    span.className = 'float';
    span.textContent = text;
    e.card.appendChild(span);
    setTimeout(() => span.remove(), 1200);
  }
  game.events.on('fieldCompleted', ({ fieldId, bonus }) => {
    const card = els.fields[fieldId]?.card;
    if (card) { card.classList.remove('flash'); void card.offsetWidth; card.classList.add('flash'); }
    floatText(fieldId, `✨ Champ propre ! +${fmt(bonus)} 💰`);
  });
  game.events.on('sackFull', () => {
    els.sackBox.classList.remove('shake'); void els.sackBox.offsetWidth; els.sackBox.classList.add('shake');
  });
  game.events.on('fieldUnlocked', () => build());

  build();
  return { update };
}
