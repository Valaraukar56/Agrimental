// Acces au stockage du navigateur. Equivalent Godot : FileAccess sur user://save.json
let key = 'agrimental.save';
let disabled = false;

export function setSaveKey(k) { key = k; }

export function loadSave() {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

export function writeSave(obj) {
  if (disabled) return;
  try { localStorage.setItem(key, JSON.stringify(obj)); } catch { /* stockage indisponible */ }
}

export function clearSave() {
  disabled = true; // empeche la sauvegarde "beforeunload" de reecrire
  try { localStorage.removeItem(key); } catch { }
}

// Preferences d'affichage (pas de l'etat de jeu)
export function loadPref(name, fallback) {
  try { const v = localStorage.getItem('agrimental.pref.' + name); return v === null ? fallback : JSON.parse(v); }
  catch { return fallback; }
}
export function savePref(name, value) {
  try { localStorage.setItem('agrimental.pref.' + name, JSON.stringify(value)); } catch { }
}
