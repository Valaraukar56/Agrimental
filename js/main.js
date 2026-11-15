// Point d'entree : relie donnees, logique, sauvegarde et affichage.
import { loadData } from './data/loader.js';
import { Game } from './core/game.js';
import { setSaveKey, loadSave, writeSave, clearSave } from './platform/storage.js';
import { createUI } from './ui/ui.js';

async function start() {
  const data = await loadData();
  setSaveKey(data.balance.saveKey);

  const game = new Game(data, loadSave());
  window.game = game; // pratique pour tester dans la console

  const ui = createUI(document.getElementById('app'), game, {
    onReset: () => { clearSave(); location.reload(); },
  });

  const save = () => writeSave(game.serialize());
  window.addEventListener('beforeunload', save);
  document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });

  let last = performance.now(), saveAcc = 0;
  function frame(now) {
    const dt = Math.min((now - last) / 1000, 1);
    last = now;
    game.tick(dt);
    ui.update();
    saveAcc += dt;
    if (saveAcc >= data.balance.saveIntervalSec) { save(); saveAcc = 0; }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

start().catch(err => {
  document.getElementById('app').innerHTML =
    `<p class="error">Erreur de chargement : ${err.message}<br>
     Lance le jeu via un serveur local (voir README), pas en double-cliquant sur index.html.</p>`;
  console.error(err);
});
