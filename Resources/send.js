// Уголёк — автоматизация инбокса TikTok (собственная реализация с нуля).
(function () {
  'use strict';

  const CFG = {
    settleMs: 3000,
    focusMs: 300,
    insertMs: 500,
    sendScanMs: 500,
    clickWaitMs: 1500,
    scrollStepMs: 1200,
    scrollMaxSteps: 60,
    sendConfirmMs: 1000,
    verifyPolls: 3,
    verifyPollMs: 1200,
    pollMs: 400,
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

  // жучки на падение панели: React-крэши летят в window.onerror / unhandledrejection / console.error
  const jsErrors = [];
  function trapErrors() {
    window.addEventListener('error', function (e) {
      jsErrors.push('err: ' + String(e.message || e.type).slice(0, 160));
    });
    window.addEventListener('unhandledrejection', function (e) {
      const reason = e.reason;
      jsErrors.push('rej: ' + String((reason && (reason.stack || reason.message)) || reason).slice(0, 200));
    });
    const orig = console.error;
    console.error = function () {
      try {
        const parts = Array.from(arguments).map(function (a) {
          if (typeof a === 'string') return a;
          if (a && a.stack) return String(a.stack).split('\n')[0];
          if (a && a.message) return String(a.message);
          try { return JSON.stringify(a); } catch (e) { return String(a); }
        });
        jsErrors.push('console: ' + parts.join(' | ').slice(0, 250));
      } catch (e) {}
      orig.apply(console, arguments);
    };
  }
  trapErrors();

  function errorsSummary() {
    if (!jsErrors.length) return '';
    return ' jsErrors=[' + jsErrors.slice(-6).join(' ;; ').slice(0, 700) + ']';
  }

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

  function handleFromItem(item) {
    // в веб-списке TikTok ссылки a[href*='/@'] отсутствуют (handle виден только в открытом чате)
    // поэтому handle почти всегда null — поиск идёт по никнейму
    const link = item.querySelector("a[href*='/@']");
    if (!link) return null;
    const match = link.getAttribute('href').match(/@([^/?#]+)/);
    return match ? match[1].toLowerCase() : null;
  }

  // частичное совпадение: никнейм "нн" (кириллица) может быть отображением @nnnnll67nl (латиница)
  // нормализуем раскладку: кириллические буквы → латинские эквиваленты
  const LAYOUT_MAP = { 'а':'a','в':'b','е':'e','к':'k','м':'m','н':'n','о':'o','р':'p','с':'c','т':'t','у':'y','х':'x' };
  function normalizeLayout(s) {
    let out = '';
    for (const ch of s.toLowerCase()) out += LAYOUT_MAP[ch] || ch;
    return out;
  }

  function fuzzyMatch(wanted, candidate) {
    if (!candidate) return false;
    const c = normalizeLayout(candidate);
    const w = normalizeLayout(wanted);
    return c === w
      || (w.length >= 2 && c.length >= 2 && (w.startsWith(c) || c.startsWith(w)));
  }

  function waitFor(test, timeoutMs, pollMs) {
    const interval = pollMs || CFG.pollMs || 400;
    return new Promise((resolve) => {
      const started = Date.now();
      const timer = setInterval(() => {
        let ok = false;
        try { ok = !!test(); } catch (e) { ok = false; }
        if (ok) { clearInterval(timer); resolve(true); }
        else if (Date.now() - started > timeoutMs) { clearInterval(timer); resolve(false); }
      }, interval);
    });
  }

  async function waitForChatList() {
    const appeared = await waitFor(
      () => document.querySelectorAll("[data-e2e='dm-new-conversation-item']").length > 0,
      15000
    );
    return appeared ? chatList() : null;
  }

  function scrollTargetFor() {
    // TikTok DM: настоящий скролл-контейнер — безымянный div ВНУТРИ drawer
    // (не предок списка! у списка overflow=visible, scrollHeight=clientHeight)
    // Ищем: overflowY=auto/scroll И scrollHeight > clientHeight
    const drawer = document.querySelector('[class*="DivDrawerCont"]')
      || document.querySelector('[class*="MessageDra"]');
    if (drawer) {
      const all = drawer.querySelectorAll('*');
      for (const el of all) {
        const style = getComputedStyle(el);
        if (/(auto|scroll)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 10) {
          return el;
        }
      }
    }
    // фолбэк: старый путь — от списка вверх
    const direct = document.querySelector("[data-e2e='dm-new-conversation-list']");
    let node = direct;
    for (let i = 0; node && i < 12 && node !== document.body; i++) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight + 10) return node;
      node = node.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  function nudgeScroll(target, delta) {
    // плавный скролл малыми шагами — виртуализированный список TikTok
    // не успевает рендерить элементы при больших прыжках
    const step = Math.min(delta, target.clientHeight * 0.7);
    target.scrollTop += step;
    target.dispatchEvent(new Event('scroll', { bubbles: true }));
    // дополнительно: wheel-событие, как от реальной мыши
    target.dispatchEvent(new WheelEvent('wheel', {
      deltaY: step, bubbles: true, cancelable: true
    }));
  }

  function nicknameOfItem(item) {
    const el = item.querySelector("[data-e2e='dm-new-conversation-nickname']");
    return el ? (el.innerText || '').trim() : '';
  }

  async function findAndOpenChat(username, isGroup) {
    const wanted = String(username).toLowerCase();
    let list = await waitForChatList();
    if (!list) throw new Error('Список чатов не появился за 15 секунд');

    const target = scrollTargetFor();
    if (target.scrollTop > 0) {
      nudgeScroll(target, -target.scrollTop);
      await sleep(800);
    }

    for (let step = 0; step <= CFG.scrollMaxSteps; step++) {
      for (const item of list.items) {
        const nickname = nicknameOfItem(item).toLowerCase();
        let matches;
        if (isGroup) {
          matches = itemTitle(item).toLowerCase() === wanted || nickname === wanted
            || fuzzyMatch(wanted, itemTitle(item)) || fuzzyMatch(wanted, nickname);
        } else {
          const handle = handleFromItem(item);
          const title = itemTitle(item).toLowerCase();
          matches = handle === wanted || nickname === wanted || title === wanted
            || fuzzyMatch(wanted, nickname) || fuzzyMatch(wanted, title)
            || (handle && fuzzyMatch(wanted, handle));
        }
        if (matches) {
          try {
            item.scrollIntoView({ block: 'center' });
          } catch (e) {}
          await sleep(500);
          const preState = paneState();
          log('До клика — ' + preState);
          if (renderErrVisible() && !(await recoverRenderError())) {
            log('Оверлей ошибки без кнопки повтора — пробую другой чат для перемонтирования панели');
            if (!(await distractClick(item))) {
              throw new Error('Чат не открылся [DM сломана до клика: ' + preState + ']');
            }
            log('Панель восстановлена кликом по другому чату');
          }
          if (!paneAlive()) {
            log('Панель пуста — жму nav-messages, чтобы перемонтировать страницу сообщений');
            const nav = document.querySelector("[data-e2e='nav-messages']");
            if (nav) humanClick(nav);
            await waitFor(paneAlive, 6000);
          }
          const opened = await openChat(item);
          if (!opened) {
            throw new Error('Чат не открылся [до=' + preState + ' после=' + chatOpenDiagnostics(item) + ']');
          }
          return;
        }
      }

      const before = target.scrollTop;
      nudgeScroll(target, target.clientHeight ? target.clientHeight * 0.7 : 400);
      await sleep(CFG.scrollStepMs);

      // всегда пере-запрашиваем список: TikTok виртуализирует, элементы меняются
      const refreshed = chatList();
      if (refreshed) list = refreshed;
      log('Скролл шаг ' + step + ': items=' + (list ? list.items.length : 0) + ' scrollTop=' + target.scrollTop);

      // TikTok может ограничивать scrollTop — если упёрлись, пробуем
      // scrollIntoView на последний видимый элемент, чтобы «дотолкнуть»
      if (target.scrollTop === before || target.scrollTop >= target.scrollHeight - target.clientHeight - 5) {
        const allItems = document.querySelectorAll("[data-e2e='dm-new-conversation-item']");
        const lastItem = allItems[allItems.length - 1];
        if (lastItem) {
          try { lastItem.scrollIntoView({ block: 'end' }); } catch (e) {}
          await sleep(800);
          const refreshed2 = chatList();
          if (refreshed2) list = refreshed2;
        }
        if (target.scrollTop === before) {
          target.dispatchEvent(new WheelEvent('wheel', { deltaY: 600, bubbles: true, cancelable: true }));
          await sleep(600);
          if (target.scrollTop === before && step > 2) {
            throw new Error('Пользователь не найден в списке чатов (скролл упёрся, всего ' + allItems.length + ' чатов)');
          }
        }
      }
    }
    throw new Error('Пользователь не найден в списке чатов');
  }

  // ==== Верификация получателя (план handle-verification, часть A) ====

  function rankOf(item, h, l, isGroup) {
    const nickname = nicknameOfItem(item).toLowerCase();
    const title = itemTitle(item).toLowerCase();
    if (isGroup) {
      if (nickname === h || title === h) return 1;
      if (fuzzyMatch(h, nickname) || fuzzyMatch(h, title)) return 3;
      return 99;
    }
    const handleAttr = handleFromItem(item); // почти всегда null — ок
    if (handleAttr === h || nickname === h || title === h) return 1;
    if (l && (nickname === l || title === l)) return 2;
    if (fuzzyMatch(h, nickname) || fuzzyMatch(h, title)) return 3;
    if (l && (fuzzyMatch(l, nickname) || fuzzyMatch(l, title))) return 4;
    return 99;
  }

  // Один проход скролла, обе иглы сразу: юзернейм (ранги 1/3) и имя (ранги 2/4).
  // Второго прохода нет — худший случай укладывается в таймаут отправки (PLAN-08).
  async function collectCandidates(h, l, isGroup) {
    let list = await waitForChatList();
    if (!list) throw new Error('Список чатов не появился за 15 секунд');

    const target = scrollTargetFor();
    if (target.scrollTop > 0) {
      nudgeScroll(target, -target.scrollTop);
      await sleep(800);
    }

    const found = [];
    const seen = new Set();

    for (let step = 0; step <= CFG.scrollMaxSteps; step++) {
      for (const item of list.items) {
        const rank = rankOf(item, h, l, isGroup);
        if (rank > 4) continue;
        const key = item.getAttribute('data-conv-id')
          || (nicknameOfItem(item) + '|' + itemTitle(item));
        if (seen.has(key)) continue;
        seen.add(key);
        found.push({ item, rank });       // ранг 1 лучше 2 лучше 3 лучше 4
      }

      const before = target.scrollTop;
      // шаг — ТОЛЬКО рабочая формула из основного поиска (PLAN-01), не CFG.scrollStep
      nudgeScroll(target, target.clientHeight ? target.clientHeight * 0.7 : 400);
      await sleep(CFG.scrollStepMs);

      const refreshed = chatList();
      if (refreshed) list = refreshed;

      // упёрлись в низ списка — кандидатов больше не будет
      if (target.scrollTop === before || target.scrollTop >= target.scrollHeight - target.clientHeight - 5) {
        const allItems = document.querySelectorAll("[data-e2e='dm-new-conversation-item']");
        const lastItem = allItems[allItems.length - 1];
        if (lastItem) {
          try { lastItem.scrollIntoView({ block: 'end' }); } catch (e) {}
          await sleep(800);
          const refreshed2 = chatList();
          if (refreshed2) list = refreshed2;
        }
        if (target.scrollTop === before) break;
      }
    }

    found.sort((a, b) => a.rank - b.rank);
    log('Кандидаты: ' + (found.map((c) => 'rank' + c.rank).join(',') || 'нет'));
    return found;
  }

  // Юзернейм виден только в открытой панели. Три стратегии чтения (PLAN-07).
  function handleFromOpenChat() {
    const scope = document.querySelector("[data-e2e='dm-new-chatbox']")
      || document.querySelector("[data-e2e='inbox-content']")
      || document.body;
    // 1) прямая ссылка на профиль внутри панели
    const link = scope.querySelector("a[href*='/@']");
    if (link) {
      const m = link.getAttribute('href').match(/@([^/?#]+)/);
      if (m) return m[1].toLowerCase();
    }
    // 2) текстовый узел ровно вида "@login" (шапка чата часто показывает юз текстом)
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const t = (node.textContent || '').trim();
      const m = t.match(/^@([A-Za-z0-9._]{2,30})$/);
      if (m) return m[1].toLowerCase();
    }
    return null; // не смогли — кандидат будет пропущен, вслепую не пишем
  }

  // Открыть чат нужного друга с проверкой юзернейма по открытой панели.
  // Бросает «…не найден…» — такие ошибки НЕ повторяются второй попыткой.
  async function findAndOpenVerifiedChat(username, label, isGroup) {
    const wanted = String(username).toLowerCase();
    const candidates = await collectCandidates(wanted, String(label || '').toLowerCase(), isGroup);
    if (!candidates.length) throw new Error('Друг не найден в списке чатов');

    let unverifiable = 0;
    for (const cand of candidates) {
      const fresh = resolveFresh(cand.item);           // защита от React-перерисовки (PLAN-06)
      if (!fresh) continue;
      const opened = await openChat(fresh);
      if (!opened) continue;

      if (isGroup) return { ok: true };

      const actual = handleFromOpenChat();
      if (!actual) {
        unverifiable++;
        log('Не смог прочитать юзернейм открытого чата — кандидат пропущен');
        continue;                                      // вслепую не пишем
      }
      if (actual !== wanted) {
        log('Юзернейм не совпал: ожидался ' + wanted + ', открылся ' + actual + ' — пробую следующего');
        continue;                                      // панель переключится при открытии следующего
      }
      log('Юзернейм совпал: ' + actual);
      return { ok: true };
    }
    throw new Error('Друг не найден: ни один кандидат не прошёл верификацию'
      + (unverifiable ? ' (непроверяемых: ' + unverifiable + ')' : '')
      + ' — если это массово, выключи «Проверять получателя» в настройках');
  }

  function keyboardClick(el) {
    const options = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    el.dispatchEvent(new KeyboardEvent('keydown', options));
    el.dispatchEvent(new KeyboardEvent('keyup', options));
  }

  function clampX(value) { return Math.max(1, Math.min(window.innerWidth - 1, value)); }
  function clampY(value) { return Math.max(1, Math.min(window.innerHeight - 1, value)); }

  function pressAndHold(el) {
    const rect = el.getBoundingClientRect();
    const options = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: clampX(rect.left + rect.width * 0.35),
      clientY: clampY(rect.top + rect.height / 2),
      button: 0,
      detail: 1
    };
    el.dispatchEvent(new MouseEvent('mousedown', options));
    setTimeout(() => {
      el.dispatchEvent(new MouseEvent('mouseup', options));
      el.dispatchEvent(new MouseEvent('click', options));
    }, 120);
  }

  function hoverPane() {
    const x = clampX(window.innerWidth * 0.6);
    const y = clampY(window.innerHeight * 0.5);
    const el = document.elementFromPoint(x, y);
    if (!el) return;
    el.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: x, clientY: y }));
    el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, clientX: x, clientY: y }));
    el.dispatchEvent(new MouseEvent('mouseenter', { clientX: x, clientY: y }));
  }

  const editorReady = () => visibleEditor() !== null;

  // чат открыт ТОЛЬКО если поле ввода есть и выбрана именно целевая строка
  // (иначе после «отвлекающего» клика можно написать не в тот чат)
  function chatOpenReady(item) {
    if (!editorReady()) return false;
    const node = resolveFresh(item);
    return !!node && node.getAttribute('aria-selected') === 'true';
  }

  async function distractClick(item) {
    const targetConv = item.getAttribute('data-conv-id');
    const items = document.querySelectorAll("[data-e2e='dm-new-conversation-item']");
    for (const other of items) {
      if (targetConv && other.getAttribute('data-conv-id') === targetConv) continue;
      if (other.offsetParent === null) continue;
      try { other.scrollIntoView({ block: 'center' }); } catch (e) {}
      humanClick(other);
      if (await waitFor(editorReady, 6000)) return true;
    }
    return false;
  }

  async function settleRect(item, maxMs) {
    const started = Date.now();
    let last = null;
    while (Date.now() - started < maxMs) {
      const rect = item.getBoundingClientRect();
      const key = [rect.left, rect.top, rect.width, rect.height].join(',');
      if (last !== null && key === last) return;
      last = key;
      await sleep(250);
    }
  }

  function resolveFresh(item) {
    const convId = item.getAttribute('data-conv-id');
    if (convId) {
      const nodes = document.querySelectorAll("[data-e2e='dm-new-conversation-item'][data-conv-id=\"" + convId + "\"]");
      for (const node of nodes) {
        if (node.isConnected) return node;
      }
    }
    const nickname = nicknameOfItem(item);
    if (nickname) {
      const all = document.querySelectorAll("[data-e2e='dm-new-conversation-item']");
      for (const node of all) {
        if (nicknameOfItem(node) === nickname) return node;
      }
    }
    return item.isConnected ? item : null;
  }

  function paneState() {
    const visible = (selector) => {
      const el = document.querySelector(selector);
      return !!el && el.offsetParent !== null;
    };
    const parts = [];
    if (visible("[data-e2e='dm-new-input-editor']")) parts.push('editor');
    if (visible("[data-e2e='dm-new-chatbox']")) parts.push('chatbox');
    if (visible("[data-e2e='dm-new-message-list']")) parts.push('msglist');
    if (visible("[data-e2e='inbox-bar']")) parts.push('inboxBar');
    if (visible("[data-e2e='inbox-content']")) parts.push('inboxContent');
    const errEl = document.querySelector("[data-e2e='dm-render-error']");
    let err = 'нет';
    if (errEl) {
      const buttons = Array.from(errEl.querySelectorAll('button, [role="button"]'))
        .map((b) => ((b.innerText || '') + (b.getAttribute('aria-label') || '')).trim().slice(0, 24))
        .filter(Boolean).slice(0, 4).join('|');
      err = (errEl.offsetParent !== null ? 'видим' : 'скрыт')
        + ':' + (errEl.innerText || '').replace(/\s+/g, ' ').slice(0, 40)
        + (buttons ? ' кнопки=[' + buttons + ']' : '');
    }
    return 'панель=[' + (parts.join(',') || 'ничего') + '] renderErr=' + err;
  }

  function paneAlive() {
    const chatbox = document.querySelector("[data-e2e='dm-new-chatbox']");
    const inbox = document.querySelector("[data-e2e='inbox-bar'], [data-e2e='inbox-content']");
    return (!!chatbox && chatbox.offsetParent !== null) || (!!inbox && inbox.offsetParent !== null);
  }

  function renderErrVisible() {
    const el = document.querySelector("[data-e2e='dm-render-error']");
    return !!el && el.offsetParent !== null;
  }

  async function recoverRenderError() {
    const errEl = document.querySelector("[data-e2e='dm-render-error']");
    if (!errEl) return false;
    const scope = errEl.parentElement || errEl;
    const buttons = Array.from(scope.querySelectorAll('button, [role="button"]'));
    const retry = buttons.find((b) => {
      const label = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).toLowerCase();
      return /try again|retry|reload|refresh|повтор|обнов|перезагруз/.test(label);
    });
    if (!retry || retry.offsetParent === null) return false;
    log('Жму кнопку повтора в оверлее ошибки');
    safeClick(retry);
    await waitFor(() => !renderErrVisible(), 6000);
    return !renderErrVisible();
  }

  async function openChat(item) {
    try { item.scrollIntoView({ block: 'center' }); } catch (e) {}
    await settleRect(item, 2000);

    const clickRound = async () => {
      const node = resolveFresh(item);
      if (!node) return false;
      try { node.scrollIntoView({ block: 'center' }); } catch (e) {}
      hoverPane();
      humanClick(node);
      return true;
    };

    // список чатов перерисовывается (виртуализация, новые сообщения) — каждый раз бьём по свежей ноде
    for (let round = 0; round < 3; round++) {
      if (!(await clickRound())) break;
      if (await waitFor(() => chatOpenReady(item), round === 0 ? 5000 : 2500)) return chatOpened();
      if (renderErrVisible() && !(await recoverRenderError())) return false;
    }

    const focusNode = resolveFresh(item);
    if (focusNode) {
      try { focusNode.focus(); } catch (e) {}
      keyboardClick(focusNode);
      if (await waitFor(() => chatOpenReady(item), 2500)) return chatOpened();
      if (renderErrVisible() && !(await recoverRenderError())) return false;
    }

    const holdNode = resolveFresh(item);
    if (holdNode) {
      const nickname = holdNode.querySelector("[data-e2e='dm-new-conversation-nickname']");
      pressAndHold(nickname || holdNode);
      if (await waitFor(() => chatOpenReady(item), 3000)) return chatOpened();
    }

    const last = resolveFresh(item);
    if (last) {
      try { last.click(); } catch (e) {}
      if (await waitFor(() => chatOpenReady(item), 2500)) return chatOpened();
    }

    return false;
  }

  function chatOpened() {
    cachedSendButton = findSendButton();
    log('Чат открыт — ' + paneState() + (cachedSendButton ? ' кнопкаОтправки=найдена' : ' кнопкаОтправки=НЕТ'));
    return true;
  }

  let cachedSendButton = null;

  function findSendButton() {
    for (const selector of ["[data-e2e*='send']", "[data-e2e*='Send']", "button[type='submit']"]) {
      for (const button of document.querySelectorAll(selector)) {
        if (button.offsetParent !== null) return button;
      }
    }
    const chatbox = document.querySelector("[data-e2e='dm-new-chatbox']");
    if (chatbox) {
      for (const button of chatbox.querySelectorAll('button, [role="button"]')) {
        const label = ((button.innerText || '') + ' ' + (button.getAttribute('aria-label') || '')).toLowerCase();
        if (button.offsetParent !== null && /send|отправ/.test(label) && !/media|медиа|файл/.test(label)) return button;
      }
    }
    return null;
  }

  function chatOpenDiagnostics(item) {
    const rect = item.getBoundingClientRect();
    const at = document.elementFromPoint(clampX(rect.left + rect.width / 2), clampY(rect.top + rect.height / 2));
    const overlay = at
      ? at.tagName + '.' + String(at.className).slice(0, 40) + ' e2e=' + at.getAttribute('data-e2e')
      : 'null';
    const convId = item.getAttribute('data-conv-id');
    let freshSel = 'нетConvId';
    if (convId) {
      const nodes = document.querySelectorAll("[data-e2e='dm-new-conversation-item'][data-conv-id=\"" + convId + "\"]");
      freshSel = nodes.length
        ? Array.from(nodes).map((n) => n.getAttribute('aria-selected')).join(',')
        : 'нетНоды';
    }
    const html = item.outerHTML ? item.outerHTML.replace(/\s+/g, ' ').slice(0, 250) : '';
    return 'центр=' + overlay + ' connected=' + item.isConnected + ' freshSel=' + freshSel
      + ' ' + paneState() + ' item=' + html;
  }

  function humanClick(el) {
    const rect = el.getBoundingClientRect();
    const options = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2)),
      clientY: Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2)),
      button: 0,
      detail: 1
    };
    const pointerOptions = Object.assign({}, options, { pointerId: 1, pointerType: 'mouse', isPrimary: true });
    try { el.dispatchEvent(new PointerEvent('pointerdown', pointerOptions)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mousedown', options));
    try { el.dispatchEvent(new PointerEvent('pointerup', pointerOptions)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mouseup', options));
    el.dispatchEvent(new MouseEvent('click', options));
  }

  function visibleEditor() {
    const primary = document.querySelector("[data-e2e='dm-new-input-editor'] [contenteditable='true']");
    if (primary) return primary;
    const area = document.querySelector("[data-e2e='message-input-area'] textarea");
    if (area) return area;
    const editors = Array.from(document.querySelectorAll(CFG.editorSelector));
    return editors.find((el) => el.offsetParent !== null) || editors[0] || null;
  }

  function editorText(el) {
    if (!el) return '';
    if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') return el.value || '';
    return el.innerText || el.textContent || '';
  }

  function editorHasText(editor, text) {
    return editorText(editor).includes(text);
  }

  function pasteViaReact(editor, text) {
    for (const key of Object.keys(editor)) {
      if (!key.startsWith('__reactFiber$') && !key.startsWith('__reactInternalInstance$')) continue;
      let fiber = editor[key];
      for (let depth = 0; fiber && depth < 30; depth++) {
        const props = fiber.memoizedProps;
        if (props && typeof props.onPaste === 'function') {
          const fakeEvent = {
            preventDefault: () => {},
            stopPropagation: () => {},
            clipboardData: { getData: () => text },
            target: editor,
          };
          try {
            props.onPaste(fakeEvent);
            return true;
          } catch (e) {
            return false;
          }
        }
        fiber = fiber.return;
      }
    }
    return false;
  }

  function pasteEventInsert(editor, text) {
    try {
      const dt = new DataTransfer();
      dt.setData('text/plain', text);
      editor.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dt }));
      return true;
    } catch (e) {
      return false;
    }
  }

  async function typeMessage(text) {
    const editor = visibleEditor();
    if (!editor) throw new Error('Не найдено поле ввода сообщения');

    // focus() не зовём: скрытое окно не становится key (hasFocus=false), и фокус-цикл мог ронять панель
    try {
      const range = document.createRange();
      range.selectNodeContents(editor);
      range.collapse(false);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    } catch (e) {}

    if (editor.tagName === 'TEXTAREA' || editor.tagName === 'INPUT') {
      const setter = Object.getOwnPropertyDescriptor(
        editor.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype,
        'value'
      ).set;
      setter.call(editor, text);
      editor.dispatchEvent(new Event('input', { bubbles: true }));
    } else {
      // paste с DataTransfer — родной атомарный путь Draft.js; фолбэки: beforeinput, execCommand, React-onPaste
      if (pasteEventInsert(editor, text)) await sleep(80);
      if (!editorHasText(editor, text)) {
        try {
          editor.dispatchEvent(new InputEvent('beforeinput', {
            inputType: 'insertText', data: text, bubbles: true, cancelable: true
          }));
        } catch (e) {}
        await sleep(80);
      }
    }

    if (!editorHasText(editor, text)) {
      document.execCommand('insertText', false, text);
      await sleep(80);
    }

    if (!editorHasText(editor, text)) {
      pasteViaReact(editor, text);
      await sleep(80);
    }

    if (!editorHasText(editor, text)) {
      throw new Error('Текст не вставился в поле ввода');
    }
    log('Текст введён');
    log('После ввода — ' + paneState() + ' hasFocus=' + document.hasFocus() + errorsSummary());
  }

  function safeClick(el) {
    if (typeof el.click === 'function') {
      el.click();
      return;
    }
    humanClick(el);
  }

  async function clickSend() {
    if (cachedSendButton) {
      const button = cachedSendButton;
      cachedSendButton = null;
      if (button.isConnected && button.offsetParent !== null) {
        safeClick(button);
        log('Отправка заранее найденной кнопкой');
        return;
      }
    }

    // кнопка отправки появляется только когда в поле есть текст — ищем сразу, без паузы
    const instant = findSendButton();
    if (instant) {
      safeClick(instant);
      log('Отправка кнопкой (мгновенный поиск)');
      return;
    }

    await sleep(CFG.sendScanMs);

    for (const selector of ["[data-e2e*='send']", "[data-e2e*='Send']", "button[type='submit']"]) {
      for (const button of document.querySelectorAll(selector)) {
        if (button.offsetParent !== null) {
          safeClick(button);
          log('Отправка кнопкой: ' + selector);
          return;
        }
      }
    }

    const chatbox = document.querySelector("[data-e2e='dm-new-chatbox']");
    if (chatbox) {
      for (const button of chatbox.querySelectorAll('button, [role="button"]')) {
        const label = ((button.innerText || '') + ' ' + (button.getAttribute('aria-label') || '')).toLowerCase();
        if (button.offsetParent !== null && /send|отправ/.test(label) && !/media|медиа|файл/.test(label)) {
          safeClick(button);
          log('Отправка кнопкой в чатбоксе');
          return;
        }
      }
    }

    let editor = null;
    for (let attempt = 0; attempt < 10 && !editor; attempt++) {
      editor = visibleEditor();
      if (!editor) await sleep(CFG.pollMs || 400);
    }
    if (!editor) {
      const dmKeys = Object.keys(collectE2E())
        .filter((key) => key.indexOf('dm-') === 0)
        .slice(0, 14)
        .join(',');
      const buttons = Array.from(document.querySelectorAll('button, [role="button"]'))
        .filter((b) => b.offsetParent !== null)
        .map((b) => (((b.innerText || '') + (b.getAttribute('aria-label') || '')).trim().slice(0, 16)) || (b.getAttribute('data-e2e') || '').slice(0, 20))
        .filter(Boolean).slice(0, 12).join('|');
      const state = 'editorContainer=' + (document.querySelector("[data-e2e='dm-new-input-editor']") ? 'есть' : 'нет')
        + ' editables=' + document.querySelectorAll("[contenteditable='true']").length
        + ' vis=' + document.visibilityState
        + ' dm=[' + dmKeys + ']'
        + ' кнопки=[' + buttons + ']'
        + errorsSummary();
      throw new Error('Поле ввода пропало перед отправкой (' + state + ')');
    }
    const keyOptions = {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true,
      cancelable: true
    };
    for (const type of ['keydown', 'keypress', 'keyup']) {
      editor.dispatchEvent(new KeyboardEvent(type, keyOptions));
      document.dispatchEvent(new KeyboardEvent(type, keyOptions));
    }
    log('Отправка клавишей Enter');
  }

  const classOf = (el) => (typeof el.className === 'string' ? el.className : '');

  function collectE2E(root) {
    const e2e = {};
    (root || document).querySelectorAll('[data-e2e]').forEach((el) => {
      const value = el.getAttribute('data-e2e');
      e2e[value] = (e2e[value] || 0) + 1;
    });
    const sorted = {};
    Object.keys(e2e).sort().forEach((key) => { sorted[key] = e2e[key]; });
    return sorted;
  }

  function discovery() {
    const e2eSorted = collectE2E();

    const rootChildren = [];
    const root = document.querySelector('#app') || document.querySelector('#main') || document.body;
    Array.from(root.children).slice(0, 15).forEach((el) => {
      const cls = classOf(el).split(' ').filter(Boolean).slice(0, 3).join('.');
      const tag = el.tagName.toLowerCase();
      const marker = el.getAttribute('data-e2e');
      rootChildren.push(tag + (cls ? '.' + cls : '') + (marker ? '[' + marker + ']' : ''));
    });

    const scrollables = [];
    const walk = (node, depth) => {
      if (depth > 9 || scrollables.length >= 6) return;
      for (const child of Array.from(node.children)) {
        if (child.scrollHeight > child.clientHeight + 100 && child.clientHeight > 200) {
          scrollables.push({
            cls: classOf(child).slice(0, 80),
            scrollHeight: child.scrollHeight,
            clientHeight: child.clientHeight,
            profileLinks: child.querySelectorAll("a[href*='/@']").length,
            e2eInside: child.querySelectorAll('[data-e2e]').length
          });
        }
        walk(child, depth + 1);
      }
    };
    walk(document.body, 0);

    const chats = [];
    Array.from(document.querySelectorAll("[data-e2e='dm-new-conversation-item']"))
      .slice(0, 12)
      .forEach((item) => {
        chats.push({
          handle: handleFromItem(item),
          nickname: nicknameOfItem(item),
          title: itemTitle(item),
          text: (item.innerText || '').replace(/\s+/g, ' ').slice(0, 90)
        });
      });

    return {
      url: location.href,
      ready: document.readyState,
      e2e: e2eSorted,
      chats,
      flame: flameScan(),
      profileLinks: document.querySelectorAll("a[href*='/@']").length,
      editables: document.querySelectorAll("[contenteditable='true']").length,
      iframes: document.querySelectorAll('iframe').length,
      scrollables,
      rootChildren,
      bodySnippet: (document.body.innerText || '').replace(/\s+/g, ' ').slice(0, 300)
    };
  }

  function chatPane() {
    return document.querySelector("[data-e2e='dm-new-message-list']") || document.body;
  }

  async function verifySent(text) {
    for (let poll = 0; poll < CFG.verifyPolls; poll++) {
      await sleep(CFG.verifyPollMs);
      const bubbles = document.querySelectorAll("[data-e2e='dm-new-message-text']");
      for (const bubble of bubbles) {
        if ((bubble.innerText || '').includes(text)) return true;
      }
    }
    return false;
  }

  function flameScan() {
    const found = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode()) && found.length < 8) {
      const text = node.textContent || '';
      if (/🔥/.test(text) || /\bflame\b/i.test(text)) {
        found.push({ kind: 'text', sample: text.trim().slice(0, 40) });
      }
    }
    document
      .querySelectorAll('[class*="streak" i], [class*="flame" i], [data-e2e*="streak" i], [data-e2e*="flame" i]')
      .forEach((el) => {
        if (found.length < 12) {
          found.push({
            kind: 'attr',
            sample: (el.getAttribute('data-e2e') || classOf(el) || '').toString().slice(0, 40)
          });
        }
      });
    return found;
  }

  function openFirstChat() {
    const items = document.querySelectorAll("[data-e2e='dm-new-conversation-item']");
    if (items[0]) {
      openChat(items[0]).then(() => {});
    }
    return items.length;
  }

  function chatSnapshot() {
    const buttons = [];
    document.querySelectorAll('button, [role="button"]').forEach((b) => {
      if (b.offsetParent === null) return;
      const text = (b.innerText || b.getAttribute('aria-label') || '').trim().slice(0, 24);
      buttons.push({
        text,
        e2e: b.getAttribute('data-e2e'),
        cls: classOf(b).split(' ').filter(Boolean).slice(0, 2).join('.')
      });
    });

    const editables = [];
    document.querySelectorAll("[contenteditable='true']").forEach((el) => {
      const owner = el.closest('[data-e2e]');
      editables.push({
        cls: classOf(el).split(' ').filter(Boolean).slice(0, 2).join('.'),
        ownerE2E: owner ? owner.getAttribute('data-e2e') : null
      });
    });

    const chatbox = document.querySelector("[data-e2e='dm-new-chatbox']");
    let chatboxButtons = null;
    if (chatbox) {
      chatboxButtons = Array.from(chatbox.querySelectorAll('button, [role="button"]')).map((b) => {
        const label = (b.innerText || b.getAttribute('aria-label') || '').trim().slice(0, 24);
        return label || b.getAttribute('data-e2e') || classOf(b).slice(0, 30);
      });
    }

    return {
      url: location.href,
      e2e: collectE2E(),
      buttons: buttons.slice(0, 20),
      editables,
      chatboxButtons,
      flame: flameScan()
    };
  }

  async function run(payload) {
    if (payload.fast) {
      CFG.settleMs = 1500;
      CFG.focusMs = 150;
      CFG.insertMs = 250;
      CFG.sendScanMs = 250;
      CFG.clickWaitMs = 800;
      CFG.scrollStepMs = 900;
      CFG.sendConfirmMs = 400;
      CFG.verifyPolls = 2;
      CFG.verifyPollMs = 700;
      CFG.pollMs = 200;
    }
        const username = payload.username || '';
        const label = payload.label || '';
        const useVerify = payload.verify !== false;   // аварийный выключатель из настроек
        const openTarget = async () => useVerify
          ? await findAndOpenVerifiedChat(username, label, !!payload.isGroup)
          : await findAndOpenChat(username, !!payload.isGroup);
        try {
          log('Прогон: hasFocus=' + document.hasFocus());
          log('Ищу чат: ' + username
            + (useVerify ? ' [верификация вкл]' : '')
            + (label ? ' (имя: ' + label + ')' : ''));
      await openTarget();

      if (payload.dryRun) {
        log('Пробный режим: чат открыт, отправка пропущена');
        post({ type: 'result', username, ok: true, detail: 'пробный режим' });
        return;
      }

      let delivered = false;
      let lastError = null;
      for (let attempt = 1; attempt <= 2 && !delivered; attempt++) {
        try {
          if (attempt > 1) {
            log('Повторная попытка: открываю чат заново');
            await openTarget();
          }
          await typeMessage(payload.message || '');
          await clickSend();
          await sleep(CFG.sendConfirmMs);
          const verified = await verifySent(payload.message || '');
          if (verified) {
            log('Отправка подтверждена');
            post({ type: 'result', username, ok: true, detail: 'подтверждено' });
          } else {
            log('Отправлено, но подтверждение не увидено');
            post({ type: 'result', username, ok: true, detail: 'отправлено без подтверждения' });
          }
          delivered = true;
        } catch (err) {
          lastError = err;
          log('Попытка ' + attempt + ' не удалась: ' + String((err && err.message) || err));
          // «не найден» — поиском не лечится, вторая попытка бессмысленна
          if (/не найден/i.test(String((err && err.message) || err))) break;
        }
      }
      if (!delivered) throw lastError;
    } catch (err) {
      post({
        type: 'result',
        username,
        ok: false,
        error: String((err && err.message) || err),
      });
    }
  }

  window.Ugolek = { log, discovery, run, openFirstChat, chatSnapshot };
  log('Скрипт загружен и ждёт команд (m4.25)');
  log('UA=' + (navigator.userAgent || '').slice(0, 90) + ' url=' + location.href + ' vis=' + document.visibilityState + ' hasFocus=' + document.hasFocus());
})();
