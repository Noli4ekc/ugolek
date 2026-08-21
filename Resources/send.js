// Уголёк — автоматизация инбокса TikTok (собственная реализация с нуля).
(function () {
  'use strict';

  function post(msg) {
    try {
      window.webkit.messageHandlers.ugolekBridge.postMessage(msg);
    } catch (e) {
      // мост недоступен (например, при ручном запуске в браузере) — молча игнорируем
    }
  }

  function log(text) {
    post({ type: 'log', text: String(text) });
  }

  window.Ugolek = { log: log };
  log('Скрипт загружен и ждёт команд');
})();
