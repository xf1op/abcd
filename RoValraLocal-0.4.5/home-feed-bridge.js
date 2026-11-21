'use strict';

(() => {
  const DEFAULTS = { cleanHomePage: true };
  let enabled = DEFAULTS.cleanHomePage;
  let observer = null;
  let scanQueued = false;

  function publish(value) {
    enabled = value?.cleanHomePage === true;
    window.postMessage({
      __rvLocalFeedBridge: 'settings',
      settings: { cleanHomePage: enabled }
    }, location.origin);
    if (enabled) {
      startObserver();
      queueScan();
    } else if (observer) {
      observer.disconnect();
      observer = null;
    }
  }

  function isHomePage() {
    const path = location.pathname.replace(/^\/[a-z]{2}(?:-[a-z]{2})?\//i, '/');
    return path === '/' || path === '/home';
  }

  function normalize(value) {
    return String(value || '').replace(/\s+/g, ' ').trim().replace(/[!:.]+$/, '').toLowerCase();
  }

  function isRemovedHeading(value) {
    const label = normalize(value);
    return /^(friends|friends are playing|friends activity|friends playing|standout games?|standout games? for you|recommended for you|recommendations?|discover|sponsored)(?:\s|$)/.test(label);
  }

  function isFeedHeading(value) {
    const label = normalize(value);
    return isRemovedHeading(label) || ['continue', 'continue playing', 'favorites', 'favourites'].includes(label);
  }

  function clearMedia(section) {
    const media = section.querySelectorAll('img,source,video,audio,iframe,track,embed,object');
    for (const element of media) {
      for (const attr of ['src', 'srcset', 'sizes', 'poster', 'data-src', 'data-srcset', 'data-lazy-src', 'data-original', 'data-original-src', 'data-background-image']) {
        if (element.hasAttribute(attr)) element.removeAttribute(attr);
      }
      if (element instanceof HTMLMediaElement) {
        try { element.pause(); element.load(); } catch {}
      }
    }
    for (const element of [section, ...section.querySelectorAll('[style]')]) {
      if (element.style?.backgroundImage) element.style.backgroundImage = 'none';
    }
  }

  function findSection(heading) {
    let node = heading;
    const cardSelector = 'a[href*="/games/"],[data-testid*="game-card" i],[data-testid*="game-tile" i],[class*="game-card" i],[class*="GameCard"]';
    const sectionSelector = 'section,[data-testid*="sort" i],[data-testid*="carousel" i],[data-testid*="section" i],[class*="sort-container" i],[class*="carousel" i],[class*="section-container" i]';

    for (let depth = 0; depth < 10; depth += 1) {
      node = node.parentElement;
      if (!node || node === document.body || node === document.documentElement || node.matches('main,#container-main')) break;

      const competing = [...node.querySelectorAll('h1,h2,h3,h4,[role="heading"],div,span')].some((candidate) => {
        if (candidate === heading || candidate.contains(heading) || heading.contains(candidate)) return false;
        const label = normalize(candidate.textContent);
        return label.length <= 70 && isFeedHeading(label);
      });
      if (competing) continue;

      const cards = node.querySelectorAll(cardSelector).length;
      if (node.matches(sectionSelector) && (cards >= 1 || node.children.length >= 3)) return node;
      if (cards >= 2 && node.children.length >= 2) return node;
    }
    return null;
  }

  function scan() {
    if (!enabled || !isHomePage() || !document.documentElement) return;
    const root = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    if (!root) return;

    const candidates = new Set(root.querySelectorAll('h1,h2,h3,h4,[role="heading"],[data-testid*="title" i],[class*="section-title" i],[class*="heading" i]'));
    for (const element of root.querySelectorAll('div,span')) {
      if (element.childElementCount > 3) continue;
      const label = String(element.textContent || '').trim();
      if (label && label.length <= 70 && isFeedHeading(label)) candidates.add(element);
    }

    const sections = new Map();
    for (const heading of candidates) {
      if (!heading.isConnected || !isRemovedHeading(heading.textContent)) continue;
      const section = findSection(heading);
      if (section?.isConnected) sections.set(section, true);
    }

    const removals = [...sections.keys()].filter((section) =>
      ![...sections.keys()].some((other) => other !== section && other.contains(section))
    );
    for (const section of removals) {
      if (!section.isConnected) continue;
      clearMedia(section);
      section.remove();
    }
  }

  function queueScan() {
    if (scanQueued || !enabled || !isHomePage()) return;
    scanQueued = true;
    queueMicrotask(() => {
      scanQueued = false;
      scan();
    });
  }

  function startObserver() {
    if (observer) return;
    observer = new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === 'characterData' && isRemovedHeading(record.target.nodeValue)) {
          queueScan();
          return;
        }
        for (const node of record.addedNodes || []) {
          if (node.nodeType === Node.ELEMENT_NODE && isFeedHeading(node.textContent?.slice(0, 80))) {
            queueScan();
            return;
          }
          if (node.nodeType === Node.TEXT_NODE && isRemovedHeading(node.nodeValue)) {
            queueScan();
            return;
          }
        }
      }
    });
    observer.observe(document, { childList: true, subtree: true, characterData: true });
  }

  chrome.storage.local.get(DEFAULTS).then(publish).catch(() => publish(DEFAULTS));
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !Object.hasOwn(changes, 'cleanHomePage')) return;
    chrome.storage.local.get(DEFAULTS).then(publish).catch(() => {});
  });

  window.addEventListener('popstate', () => {
    if (enabled) {
      startObserver();
      queueScan();
    }
  });
  window.addEventListener('hashchange', queueScan);
})();
