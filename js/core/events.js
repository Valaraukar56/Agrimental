// Bus d'evenements minimal. Equivalent Godot : les signaux.
export class Emitter {
  constructor() { this.handlers = {}; }
  on(name, fn) { (this.handlers[name] ||= []).push(fn); }
  emit(name, payload) { (this.handlers[name] || []).forEach(fn => fn(payload)); }
}
