// Уголёк — автоматизация инбокса TikTok (собственная реализация с нуля).
(function () {
  'use strict';

  const CFG = {
    settleMs: 3000,
    clickWaitMs: 1500,
    scrollStepMs: 2000,
    scrollMaxSteps: 40,
    sendConfirmMs: 1000,
    verifyPolls: 3,
    verifyPollMs: 1200,
    itemSelectors: [
      "[data-e2e*='dm-new-conversation-item']",
      "[data-e2e*='chat-list-item']",
      "[data-e2e*='chat-item']",
    ],
    headerSelector: "[data-e2e='chat-header']",
    editorSelector: "[contenteditable='true']",
    sendSelectors: ["[data-e2e*='send']", "button[type='submit']"],
  };

  function post(msg) {
    try {
      window.webkit.messageHandlers.ugolekBridge.postMessage(msg);
    } catch (e) {
      // мост недоступен (ручной запуск в браузере) — игнорируем
    }
  }

  function log(text) {
    post({ type: 'log', text: String(text) });
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  function firstMatch(selectors) {
    for (const selector of selectors) {
      const found = document.querySelectorAll(selector);
      if (found.length) {
        return { selector, items: Array.from(found) };
      }
    }
    return null;
  }

  function chatList() {
    return firstMatch(CFG.itemSelectors);
  }

  function itemTitle(item) {
    const lines = (item.innerText || '').split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed) return trimmed;
    }
    return '';
  }

  function discovery() {
    const list = chatList();
    return {
      url: location.href,
      chatSelector: list ? list.selector : null,
      chatCount: list ? list.items.length : 0,
      sampleTitles: list ? list.items.slice(0, 8).map(itemTitle) : [],
      hasEditor: !!document.querySelector(CFG.editorSelector),
      headerText: (document.querySelector(CFG.headerSelector) || {}).innerText || null,
    };
  }

  window.Ugolek = { log, discovery };
  log('Скрипт загружен и ждёт команд');
})();
