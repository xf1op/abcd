'use strict';

(() => {
  const eventName = 'bloximproved:route-change';
  const notify = () => window.dispatchEvent(new Event(eventName));

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    if (typeof original !== 'function' || original.__bloximprovedWrapped) continue;
    const wrapped = function (...args) {
      const result = Reflect.apply(original, this, args);
      queueMicrotask(notify);
      return result;
    };
    Object.defineProperty(wrapped, '__bloximprovedWrapped', { value: true });
    try { history[method] = wrapped; } catch {}
  }

  window.addEventListener('popstate', notify);
  window.addEventListener('hashchange', notify);
})();
