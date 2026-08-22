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

  function handleFromItem(item) {
    const link = item.querySelector("a[href*='/@']");
    if (!link) return null;
    const match = link.getAttribute('href').match(/@([^/?#]+)/);
    return match ? match[1].toLowerCase() : null;
  }

  function scrollContainerOf(item) {
    let node = item;
    while (node && node !== document.body) {
      if (node.scrollHeight > node.clientHeight + 8) return node;
      node = node.parentElement;
    }
    return null;
  }

  async function findAndOpenChat(username, isGroup) {
    const initial = chatList();
    if (initial) {
      const top = scrollContainerOf(initial.items[0]);
      if (top) {
        top.scrollTop = 0;
        await sleep(800);
      }
    }

    const wanted = String(username).toLowerCase();
    for (let step = 0; step <= CFG.scrollMaxSteps; step++) {
      const list = chatList();
      if (!list) throw new Error('Список чатов не найден на странице');

      for (const item of list.items) {
        let matches = false;
        if (isGroup) {
          matches = itemTitle(item).toLowerCase() === wanted;
        } else {
          const handle = handleFromItem(item);
          if (handle) matches = handle === wanted;
        }
        if (matches) {
          item.click();
          await sleep(CFG.clickWaitMs);
          return;
        }
      }

      const container = scrollContainerOf(list.items[0]);
      if (!container) throw new Error('Не найден контейнер прокрутки списка чатов');

      const before = container.scrollTop;
      container.scrollTop = before + container.clientHeight * 2;
      container.dispatchEvent(new Event('scroll', { bubbles: true }));
      await sleep(CFG.scrollStepMs);

      if (container.scrollTop === before && step > 0) {
        throw new Error('Пользователь не найден в списке чатов');
      }
    }
    throw new Error('Пользователь не найден в списке чатов');
  }

  function visibleEditor() {
    const editors = Array.from(document.querySelectorAll(CFG.editorSelector));
    return editors.find((el) => el.offsetParent !== null) || editors[0] || null;
  }

  function editorHasText(editor, text) {
    return (editor.innerText || editor.textContent || '').includes(text);
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
    await sleep(300);

    if (!editorHasText(editor, text)) {
      document.execCommand('insertText', false, text);
      await sleep(500);
    }

    if (!editorHasText(editor, text)) {
      pasteViaReact(editor, text);
      await sleep(500);
    }

    if (!editorHasText(editor, text)) {
      throw new Error('Текст не вставился в поле ввода');
    }
    log('Текст введён');
  }

  async function clickSend() {
    for (const selector of CFG.sendSelectors) {
      for (const button of document.querySelectorAll(selector)) {
        if (button.offsetParent !== null) {
          button.click();
          return;
        }
      }
    }

    const editor = visibleEditor();
    if (!editor) throw new Error('Не найдена кнопка отправки');
    const keyOptions = {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true,
      cancelable: true,
    };
    editor.dispatchEvent(new KeyboardEvent('keydown', keyOptions));
    editor.dispatchEvent(new KeyboardEvent('keyup', keyOptions));
    log('Отправка клавишей Enter');
  }

  function discovery() {
    const e2e = {};
    document.querySelectorAll('[data-e2e]').forEach((el) => {
      const value = el.getAttribute('data-e2e');
      e2e[value] = (e2e[value] || 0) + 1;
    });
    const e2eSorted = {};
    Object.keys(e2e)
      .sort()
      .forEach((key) => { e2eSorted[key] = e2e[key]; });

    const classOf = (el) => (typeof el.className === 'string' ? el.className : '');

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

    return {
      url: location.href,
      ready: document.readyState,
      e2e: e2eSorted,
      profileLinks: document.querySelectorAll("a[href*='/@']").length,
      editables: document.querySelectorAll("[contenteditable='true']").length,
      iframes: document.querySelectorAll('iframe').length,
      scrollables,
      rootChildren,
      bodySnippet: (document.body.innerText || '').replace(/\s+/g, ' ').slice(0, 300)
    };
  }

  function chatPane() {
    return (
      document.querySelector("[data-e2e='chat-message-list']") ||
      document.querySelector("[data-e2e='chat-message']")?.closest('div[class]') ||
      document.body
    );
  }

  async function verifySent(text) {
    const pane = chatPane();
    for (let poll = 0; poll < CFG.verifyPolls; poll++) {
      await sleep(CFG.verifyPollMs);
      const bubbles = pane.querySelectorAll("[data-e2e='chat-message'], [data-e2e*='message-item']");
      for (const bubble of bubbles) {
        if ((bubble.innerText || '').includes(text)) return true;
      }
      if (bubbles.length === 0 && (pane.innerText || '').includes(text)) return true;
    }
    return false;
  }

  async function run(payload) {
    const username = payload.username || '';
    try {
      log('Ищу чат: ' + username);
      await findAndOpenChat(username, !!payload.isGroup);

      if (payload.dryRun) {
        log('Пробный режим: чат открыт, отправка пропущена');
        post({ type: 'result', username, ok: true, detail: 'пробный режим' });
        return;
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
    } catch (err) {
      post({
        type: 'result',
        username,
        ok: false,
        error: String((err && err.message) || err),
      });
    }
  }

  window.Ugolek = { log, discovery, run };
  log('Скрипт загружен и ждёт команд');
})();
