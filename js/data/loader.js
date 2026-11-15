// Charge les fichiers JSON de data/. Equivalent Godot : FileAccess + JSON.parse_string
const FILES = ['crops', 'fields', 'upgrades', 'balance'];

export async function loadData(base = 'data/') {
  const entries = await Promise.all(FILES.map(async name => {
    // no-cache : revalide aupres du serveur, sinon un changement d'equilibrage n'arrive pas
    const res = await fetch(`${base}${name}.json`, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`Impossible de charger ${name}.json`);
    return [name, await res.json()];
  }));
  return Object.fromEntries(entries);
}
