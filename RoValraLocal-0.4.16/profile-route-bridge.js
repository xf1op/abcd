'use strict';

(() => {
  const eventName = 'rvlocal:route-change';
  const notify = () => window.dispatchEvent(new Event(eventName));

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    if (typeof original !== 'function' || original.__rvlocalWrapped) continue;
    const wrapped = function (...args) {
      const result = Reflect.apply(original, this, args);
      queueMicrotask(notify);
      return result;
    };
    Object.defineProperty(wrapped, '__rvlocalWrapped', { value: true });
    try { history[method] = wrapped; } catch {}
  }

  window.addEventListener('popstate', notify);
  window.addEventListener('hashchange', notify);
})();
