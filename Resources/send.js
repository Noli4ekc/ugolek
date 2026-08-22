// Уголёк — автоматизация инбокса TikTok (собственная реализация с нуля).
(function () {
  'use strict';

  const CFG = {
    settleMs: 3000,
    focusMs: 300,
    insertMs: 500,
    sendScanMs: 500,
    clickWaitMs: 1500,
    scrollStepMs: 2000,
    scrollMaxSteps: 40,
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
    const link = item.querySelector("a[href*='/@']");
    if (!link) return null;
    const match = link.getAttribute('href').match(/@([^/?#]+)/);
    return match ? match[1].toLowerCase() : null;
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
    const direct = document.querySelector("[data-e2e='dm-new-conversation-list']");
    let node = direct;
    for (let i = 0; node && i < 12 && node !== document.body; i++) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowY)) return node;
      node = node.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  function nudgeScroll(target, delta) {
    target.scrollTop += delta;
    target.dispatchEvent(new Event('scroll', { bubbles: true }));
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
          matches = itemTitle(item).toLowerCase() === wanted || nickname === wanted;
        } else {
          const handle = handleFromItem(item);
          const title = itemTitle(item).toLowerCase();
          matches = handle === wanted || nickname === wanted || title === wanted;
        }
        if (matches) {
          try {
            item.scrollIntoView({ block: 'center' });
          } catch (e) {}
          await sleep(500);
          const opened = await openChat(item);
          if (!opened) {
            throw new Error('Чат не открылся [' + chatOpenDiagnostics(item) + ']');
          }
          return;
        }
      }

      const before = target.scrollTop;
      nudgeScroll(target, target.clientHeight ? target.clientHeight * 2 : 600);
      await sleep(CFG.scrollStepMs);

      const refreshed = chatList();
      if (refreshed) list = refreshed;

      if (target.scrollTop === before) {
        target.dispatchEvent(new WheelEvent('wheel', { deltaY: 800, bubbles: true, cancelable: true }));
        const winBefore = window.scrollY;
        window.scrollBy(0, 800);
        await sleep(600);
        if (window.scrollY === winBefore && step > 1) {
          throw new Error('Пользователь не найден в списке чатов');
        }
      }
    }
    throw new Error('Пользователь не найден в списке чатов');
  }

  function clickViaReact(el) {
    const rect = el.getBoundingClientRect();
    const cx = Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2));
    const cy = Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2));
    for (const key of Object.keys(el)) {
      if (!key.startsWith('__reactFiber$') && !key.startsWith('__reactInternalInstance$')) continue;
      let fiber = el[key];
      for (let depth = 0; fiber && depth < 30; depth++) {
        const props = fiber.memoizedProps;
        if (props && typeof props.onClick === 'function') {
          const fake = {
            preventDefault: () => {},
            stopPropagation: () => {},
            currentTarget: el,
            target: el,
            type: 'click',
            clientX: cx,
            clientY: cy,
            button: 0,
            nativeEvent: {}
          };
          try { props.onClick(fake); return true; } catch (e) { return false; }
        }
        fiber = fiber.return;
      }
    }
    return false;
  }

  function keyboardClick(el) {
    const options = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    el.dispatchEvent(new KeyboardEvent('keydown', options));
    el.dispatchEvent(new KeyboardEvent('keyup', options));
  }

  async function openChat(item) {
    const targets = [item];
    const nickname = item.querySelector("[data-e2e='dm-new-conversation-nickname']");
    if (nickname) targets.push(nickname);
    if (item.firstElementChild && item.firstElementChild !== nickname) {
      targets.push(item.firstElementChild);
    }

    for (const target of targets) {
      humanClick(target);
      if (await waitFor(() => visibleEditor() !== null, 4000)) return true;
      clickViaReact(target);
      if (await waitFor(() => visibleEditor() !== null, 3000)) return true;
    }

    humanClick(item);
    humanClick(item);
    if (await waitFor(() => visibleEditor() !== null, 3000)) return true;

    keyboardClick(item);
    if (await waitFor(() => visibleEditor() !== null, 3000)) return true;

    item.click();
    if (await waitFor(() => visibleEditor() !== null, 3000)) return true;

    return false;
  }

  function chatOpenDiagnostics(item) {
    const rect = item.getBoundingClientRect();
    const cx = Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2));
    const cy = Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2));
    const at = document.elementFromPoint(cx, cy);
    const overlay = at
      ? at.tagName + '.' + String(at.className).slice(0, 50) + ' e2e=' + at.getAttribute('data-e2e')
      : 'null';
    const html = item.outerHTML ? item.outerHTML.replace(/\s+/g, ' ').slice(0, 400) : '';
    return 'центр=' + overlay + ' item=' + html;
  }

  function humanClick(el) {
    const rect = el.getBoundingClientRect();
    const options = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2)),
      clientY: Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2)),
      button: 0
    };
    try { el.dispatchEvent(new PointerEvent('pointerdown', options)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mousedown', options));
    try { el.dispatchEvent(new PointerEvent('pointerup', options)); } catch (e) {}
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

  async function typeMessage(text) {
    const editor = visibleEditor();
    if (!editor) throw new Error('Не найдено поле ввода сообщения');

    editor.focus();
    await sleep(CFG.focusMs);

    if (editor.tagName === 'TEXTAREA' || editor.tagName === 'INPUT') {
      const setter = Object.getOwnPropertyDescriptor(
        editor.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype,
        'value'
      ).set;
      setter.call(editor, text);
      editor.dispatchEvent(new Event('input', { bubbles: true }));
      await sleep(CFG.insertMs);
    }

    if (!editorHasText(editor, text)) {
      document.execCommand('insertText', false, text);
      await sleep(CFG.insertMs);
    }

    if (!editorHasText(editor, text)) {
      pasteViaReact(editor, text);
      await sleep(CFG.insertMs);
    }

    if (!editorHasText(editor, text)) {
      throw new Error('Текст не вставился в поле ввода');
    }
    log('Текст введён');
  }

  async function clickSend() {
    await sleep(CFG.sendScanMs);

    for (const selector of ["[data-e2e*='send']", "[data-e2e*='Send']", "button[type='submit']"]) {
      for (const button of document.querySelectorAll(selector)) {
        if (button.offsetParent !== null) {
          button.click();
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
          button.click();
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
      const state = 'editorContainer=' + (document.querySelector("[data-e2e='dm-new-input-editor']") ? 'есть' : 'нет')
        + ' editables=' + document.querySelectorAll("[contenteditable='true']").length
        + ' dm=[' + dmKeys + ']';
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
    try {
      log('Ищу чат: ' + username);
      await findAndOpenChat(username, !!payload.isGroup);

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
            await findAndOpenChat(username, !!payload.isGroup);
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
  log('Скрипт загружен и ждёт команд');
})();
