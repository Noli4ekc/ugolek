# Архитектурный план: надёжная доставка + пропуск уже продлённых (объединённый)

**Проект:** Уголёк (Ugolek) — iOS-приложение для автоматического продления стриков в TikTok.
**Цель:** устранить недоставку (ник ≠ юзернейм) и промахи не в того (одинаковые ники), автоматически пропускать друзей, с которыми ты уже переписывался сегодня, и автоопределять никнейм из публичного профиля TikTok.
**Дата составления:** 2026-08-26. **Ревизия 2** — переработан после адверсариального ревью (`docs/adversarial-review-handleplan.md`): закрыты PLAN-01…PLAN-14.
**Статус:** план готов к реализации, выполнения не запущено.

---

## 0. Контекст и отправная точка

Текущее состояние (коммит `4037fe9`, CI зелёный):

- `StreakEngine.run()` для каждого друга вызывает `InboxRunner.shared.send(to: friend.handle, message:..., isGroup:..., dryRun:..., fast:...)`.
- `InboxRunner.send()` передаёт в JS payload `{username, message, isGroup, dryRun, fast}` — **только юзернейм**.
- `Resources/send.js:185` `findAndOpenChat(username, isGroup)` скроллит список чатов TikTok и сравнивает юзернейм с **никнеймом/заголовком** элемента списка (юзернейма в списке нет физически — комментарий в `send.js:95-97`). Спасает только `fuzzyMatch` (`send.js:113`). **Хватает первого совпавшего.**
- В JS **два** call site поиска: `send.js:885` (основной) и `send.js:899` (повторная попытка после неудачи) — заменять нужно ОБА (находка PLAN-04).
- Модель `Friend` хранит `handle` и `label`; у большинства друзей `label` пуст.
- Реальный скролл списка: `nudgeScroll(target, Math.round(target.clientHeight * 0.7))` (`send.js:239`) — в `CFG` ключа `scrollStep` НЕТ (есть `scrollMaxSteps: 60`, `scrollStepMs: 1200`) — на этом сломался черновик плана (PLAN-01).
- Существующий inline-резолвер узла по `data-conv-id`: `send.js:342-358` (запрос `[data-e2e='dm-new-conversation-item'][data-conv-id="…"]`) — переиспользуем для защиты от React-перерисовок (PLAN-06).
- Контейнер сообщений открытого чата: `[data-e2e='dm-new-message-list']` (`send.js:368,783`).
- `SessionStore.desktopUserAgent` существует (`SessionStore.swift:17-18`).

### Три проблемы

1. **Недоставка**: никнейм не похож на юзернейм → совпадений нет → пропуск.
2. **Промах**: одинаковые ники + мягкий фаззи → первый попавшийся выигрывает, сообщение может уйти не тому.
3. **Лишняя отправка**: ты сам переписывался с другом сегодня — прогон шлёт дублирующее сообщение.

### Ключевые ограничения

- Юзернейм не виден в списке чатов; виден только в открытой панели.
- Веб-TikTok не показывает огонёк — прямой проверки «горит ли» нет. Обходной сигнал: сегодня были реплики **обеих сторон** → продлён вручную.
- Список чатов — React с виртуализацией: узлы пересоздаются, сохранённые ссылки протухают; разделители дат («Сегодня») могут отсутствовать в отрендеренном окне.

---

## 1. Что будет сделано — пять частей

### Часть A: Двухигольный поиск одним проходом + верификация по юзернейму

Один полный проход скролла оценивает каждый элемент сразу по ОБОИМ иглам (юзернейм и label) — второго прохода нет (закрывает PLAN-08: худший случай = один полный скролл ~73 с < таймаут 200 с).

```
ОДИН ПРОХОД скролла (шаг = clientHeight×0.7, как в рабочем коде):
   для каждого элемента вычисляем ранг:
      1 = точное совпадение ника/заголовка с handle
      2 = точное совпадение с label
      3 = фаззи по handle
      4 = фаззи по label
   кандидаты сортируются по рангу, внутри ранга — по позиции в списке

для каждого кандидата по порядку:
   re-resolve узла по data-conv-id (защита от React-перерисовки)
   открыть чат
   ──► Часть D: проверить, не продлён ли уже
   прочитать @юзернейм из открытой панели
      ✓ совпал → вводим сообщение, отправляем
      ✗ не совпал / не прочитался → закрыть панель, следующий кандидат
   кандидаты кончились → «друг не найден», пропуск БЕЗ отправки
```

**Аварийный выключатель** (закрывает PLAN-07): настройка `recipientVerification` (по умолчанию ВКЛ) передаётся в payload как `verify`. Если пользователь её снял — JS идёт по СТАРОМУ пути `findAndOpenChat` (функция сохраняется, не удаляется). Регрессия доставки при сдвиге вёрстки превращается из тотальной в опциональную.

**Честная оговорка:** если верификация включена, а селектор панели не подошёл — друг пропускается с пометкой «не удалось проверить». Это осознанный trade-off: безопаснее пропустить, чем написать чужому.

### Часть B: Автообновление ника при неудаче

Если часть A закончилась «друг не найден»: запрос `tiktok.com/@{handle}` → свежий никнейм → обновление `friend.label` → ОДИН повтор через ту же верифицированную отправку (retry идёт через общий `InboxRunner.send` → оба call site JS покрыты — закрывает PLAN-04). Профили бывают трёх состояний: `found` / `blocked` (бот-фильтр, 200 без данных) / `missing` — в историю пишется честная причина, а не «юзернейм сменился» на всё.

### Часть C: Автоопределение имени при добавлении друга

Debounce 800 мс при вводе юза → `ProfileFetcher` → автозаполнение `label` с защитой ручных правок (автофилл перезаписывает только пустое поле или своё же прежнее значение).

### Часть D: Пропуск уже продлённых (автодетект во время прогона)

После открытия правильного чата, ДО ввода сообщения:

```
определяем границы «сегодня» по РАЗДЕЛИТЕЛЮ ДАТ в треде
   (узел с текстом ровно «Сегодня» / «Вчера» / день недели / дата)
   разделитель «Сегодня» найден выше окна → все сообщения ниже — сегодняшние
   ближайший разделитель — «Вчера»/дата       → сегодняшних нет → ПИШЕМ
   разделителя не видно (виртуализация)        → 'unknown' → ПИШЕМ (дефолт)

внутри сегодняшнего диапазона собираем флаги направлений:
   было моё сообщение?  было его сообщение?

   оба        → СКИП «🔥 уже продлён сегодня» (стрик закрыт обоими)
   только его → ПИШЕМ (мой ответ спасает стрик)
   только моё → СКИП (повтор бесполезен: его вклад от второго сообщения не появится)
   непонятно  → ПИШЕМ (безопасный дефолт)
```

Закрывает сценарий из обсуждения: цепочка «моё → его ответ» = оба писали сегодня → скип (по черновику с одной последней репликой это был ложный resend). Парсинг времени отдельных сообщений убран полностью — источник истины один: разделитель дат (убивает PLAN-03/PLAN-05: текст сообщения больше никогда не матчится тайм-регэкспами).

### Часть E: Кнопка/свайп «🔥 Продлили» + обратное действие

Свайп по карточке ставит `lastSentDay = сегодня` (прогон пропускает до конца дня). Когда друг уже помечен — на том же месте появляется действие «↺ Вернуть в очередь» (снимает отметку) — закрывает PLAN-14. Использует новый публичный метод `AppStore` (закрывает PLAN-02 для UI).

Дополняет D: автодетект покрывает «переписка в TikTok», кнопка — всё остальное (другой мессенджер, звонок, просто передумал).

---

## 2. Проверенные факты (основа плана)

### 2.1. Юзернейм виден в открытом чате, но не в списке
`send.js:95-101` — `handleFromItem()` почти всегда `null`. Верификация возможна только после открытия.

### 2.2. Профиль содержит никнейм, но парсить надо встроенный JSON, а не весь HTML
`__UNIVERSAL_DATA_FOR_REHYDRATION__` / `SIGI_STATE` содержат `user.nickname` рядом с `user.uniqueId`. Сверка `uniqueId == handle` отсекает рекомендации (PLAN-11). Страница бот-фильтра этих скриптов не содержит → честный `.blocked`.

### 2.3. Friend.label уже есть
`Friend.swift:6,14` — поле и displayName существуют.

### 2.4. Payload собирается в InboxRunner.swift:86-92
Добавка `label`/`verify` — две строки.

### 2.5. fuzzyMatch с нормализацией раскладки
`send.js:104-118` — переиспользуется для рангов 3-4.

### 2.6. Резолвер по data-conv-id существует
`send.js:342-358` — inline-запрос `[data-e2e='dm-new-conversation-item'][data-conv-id="…"]`. Выносим в функцию `resolveItemByConvId()` и используем перед каждым открытием.

### 2.7. Контейнер сообщений известен
`[data-e2e='dm-new-message-list']` — `send.js:368,783`.

### 2.8. lastSentDay/friendsDueToday работают
`AppStore.swift:55-62,69` — части D и E используют ту же механику через новые публичные методы (PLAN-02).

### 2.9. Скролл в рабочем коде
`send.js:239` — шаг = `clientHeight × 0.7`. Единственный проверенный способ прокрутки списка; план использует только его.

---

## 3. Что нужно создать/изменить

### 3.1. `Resources/send.js` (ИЗМЕНИТЬ)

**1) Однопроходный сбор кандидатов с двумя иглами и рангами:**

```javascript
// Один проход: каждый элемент оценивается по обеим иглам сразу.
// Возвращает упорядоченный список { convId, rank } — rank 1 лучше 4.
async function collectCandidates(wantedHandle, wantedLabel, isGroup) {
  const h = String(wantedHandle || '').toLowerCase();
  const l = String(wantedLabel || '').toLowerCase();
  let list = await waitForChatList();
  if (!list) throw new Error('Список чатов не появился за 15 секунд');

  const target = scrollTargetFor();
  if (target.scrollTop > 0) {
    nudgeScroll(target, -target.scrollTop);           // вверх к началу, как раньше
    await sleep(800);
  }

  const found = [];                                    // { convId, rank }
  const seenIds = new Set();

  for (let step = 0; step <= CFG.scrollMaxSteps; step++) {
    for (const item of list.items) {
      const nickname = nicknameOfItem(item).toLowerCase();
      const title = itemTitle(item).toLowerCase();
      const convId = item.getAttribute('data-conv-id') || null;

      let rank = 99;
      if (!isGroup) {
        const handleAttr = handleFromItem(item);      // почти всегда null — ок
        if (handleAttr === h) rank = 1;
        else if (nickname === h || title === h) rank = 1;
        else if (l && (nickname === l || title === l)) rank = 2;
        else if (fuzzyMatch(h, nickname) || fuzzyMatch(h, title)) rank = 3;
        else if (l && (fuzzyMatch(l, nickname) || fuzzyMatch(l, title))) rank = 4;
      } else {
        if (nickname === h || title === h) rank = 1;
        else if (fuzzyMatch(h, nickname) || fuzzyMatch(h, title)) rank = 3;
      }

      if (rank <= 4) {
        const key = convId || (nickname + '|' + title);
        if (!seenIds.has(key)) { seenIds.add(key); found.push({ convId, rank, item }); }
      }
    }
    // Шаг скролла — ТОЛЬКО рабочая формула из send.js:239 (PLAN-01):
    nudgeScroll(target, Math.round(target.clientHeight * 0.7));
    await sleep(CFG.scrollStepMs);
    list = await waitForChatList();
    if (!list) break;
  }

  found.sort((a, b) => a.rank - b.rank);
  return found;
}
```

**2) Резолвинг свежего узла (PLAN-06):**

```javascript
// Переиспользуем существующий inline-подход send.js:342-358 как отдельную функцию.
function resolveItemByConvId(convId, fallbackItem) {
  if (convId) {
    const nodes = document.querySelectorAll(
      "[data-e2e='dm-new-conversation-item'][data-conv-id=\"" + convId + "\"]");
    if (nodes.length > 0) return nodes[0];
  }
  return fallbackItem; // convId нет — рискуем устаревшей ссылкой (осознанный фолбэк)
}
```

**3) Чтение юзернейма из открытой панели — с @-текстовым фолбэком (PLAN-07):**

```javascript
function handleFromOpenChat() {
  // 1) прямая ссылка в панели
  const panel = document.querySelector("[class*='MessageThreadContainer']")
    || document.querySelector("[class*='dm-chat']")
    || document.body;                                  // крайний случай: ищем в документе
  const link = panel.querySelector("a[href*='/@']");
  if (link) {
    const m = link.getAttribute('href').match(/@([^/?#]+)/);
    if (m) return m[1].toLowerCase();
  }
  // 2) фолбэк: текстовый узел вида "@login" в шапке панели
  const walker = document.createTreeWalker(panel, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const t = walker.currentNode.textContent.trim();
    const m = t.match(/^@([A-Za-z0-9._]{2,30})$/);
    if (m) return m[1].toLowerCase();
  }
  return null; // не смогли — кандидат будет пропущен (никогда не отправляем вслепую)
}
```

**4) Границы «сегодня» по разделителю дат — без парсинга текста сообщений (PLAN-03/05):**

```javascript
// Возвращает { mine, theirs } для сообщений под разделителем «Сегодня»,
// null — если границу определить не удалось (виртуализация/нет разделителя).
function threadTodayFlags() {
  const list = document.querySelector("[data-e2e='dm-new-message-list']");
  if (!list) return null;
  const nodes = Array.from(list.children);

  let startIdx = -1;
  for (let i = nodes.length - 1; i >= 0; i--) {
    const txt = (nodes[i].textContent || '').trim().toLowerCase();
    if (!txt) continue;
    if (txt === 'сегодня') { startIdx = i; break; }                       // граница найдена
    if (txt === 'вчера'
        || /^(пн|вт|ср|чт|пт|сб|вс)\b/i.test(txt)
        || /^\d{1,2}\s+(янв|фев|мар|апр|ма[йя]|июн|июл|авг|сен|окт|ноя|дек)\b/i.test(txt)) {
      return { mine: false, theirs: false };                              // всё старше — точно не сегодня
    }
  }
  if (startIdx === -1) return null;                                       // разделителя не видно

  let mine = false, theirs = false;
  for (let i = startIdx + 1; i < nodes.length; i++) {
    const cls = (nodes[i].className || '') + ' ' + (nodes[i].getAttribute('data-e2e') || '');
    if (!/right|out/i.test(cls)) { theirs = true; continue; }
    if (/right|out/i.test(cls))  { mine = true; }
  }
  return { mine, theirs };
}
```

Разделитель матчится только ПОЛНЫМ совпадением слова — `/дн/` внутри «Сегодня» больше ничего не ломает (PLAN-03/05). Текст сообщений вообще не участвует в определении времени.

**5) Верифицирующий цикл (замена ОБЕИХ точек вызова — PLAN-04):**

```javascript
async function findAndOpenVerifiedChat(wantedHandle, wantedLabel, isGroup) {
  const candidates = await collectCandidates(wantedHandle, wantedLabel, isGroup);
  if (candidates.length === 0) throw new Error('Друг не найден в списке чатов');

  for (const cand of candidates) {
    const item = resolveItemByConvId(cand.convId, cand.item);   // PLAN-06
    try { item.scrollIntoView({ block: 'center' }); } catch (e) {}
    await sleep(500);
    // ... существующие recoverRenderError / paneAlive ...
    const opened = await openChat(item);
    if (!opened) continue;
    if (isGroup) return { ok: true, alreadyMaintained: false };

    const actual = handleFromOpenChat();
    if (actual === null) {
      verifyFailures++;                                   // счётчик для диагностики
      log('Не смог прочитать юзернейм открытого чата — кандидат пропущен');
      await closeChat();
      continue;
    }
    if (actual !== wantedHandle.toLowerCase()) {
      log('Юзернейм не совпал: ожидался ' + wantedHandle + ', открылся ' + actual);
      await closeChat();
      continue;
    }

    const flags = threadTodayFlags();                     // PLAN-03/05: разделитель дат
    if (flags && flags.mine && flags.theirs) {
      log('🔥 Сегодня уже писали оба — стрик продлён, пропускаю');
      await closeChat();
      return { ok: true, alreadyMaintained: true };
    }
    if (flags && flags.mine && !flags.theirs) {
      log('🔥 Последнее сегодня — моё, его реплики нет: повтор бесполезен, пропускаю');
      await closeChat();
      return { ok: true, alreadyMaintained: true };
    }
    // awaiting-reply / unknown → пишем
    return { ok: true, alreadyMaintained: false };
  }
  throw new Error('Друг не найден: ни один кандидат не прошёл верификацию');
}
```

**6) ОБЕ точки вызова заменяются** (PLAN-04): `send.js:885` и `send.js:899` →

```javascript
const found = await findAndOpenVerifiedChat(username, payload.label || '', !!payload.isGroup);
if (found.alreadyMaintained) {
  post({ type: 'result', username, ok: true, alreadyMaintained: true,
         detail: '🔥 уже продлён сегодня' });
  return;
}
```

Если `payload.verify === false` (тумблер выключен) — обе точки вызывают СТАРУЮ `findAndOpenChat` (функция сохраняется намеренно).

**7) `closeChat()` — только реальные хелперы (PLAN-09):**

```javascript
async function closeChat() {
  const back = document.querySelector("[data-e2e='dm-back']")
            || document.querySelector("[class*='BackButton']");
  if (back) { humanClick(back); await sleep(400); }
  if (paneAlive()) {                                     // существующая функция
    const nav = document.querySelector("[data-e2e='nav-messages']");
    if (nav) { humanClick(nav); await sleep(600); }
  }
  // Никаких кликов по первому попавшемуся чату — чужие беседы не открываем.
}
```

### 3.2. `Ugolek/Core/InboxEngine/InboxRunner.swift` (ИЗМЕНИТЬ)

```swift
struct BridgeMessage: Codable {
    let type: String
    var username: String? = nil
    var ok: Bool? = nil
    var error: String? = nil
    var detail: String? = nil
    var text: String? = nil
    var alreadyMaintained: Bool? = nil   // ← структурированный контракт (PLAN-13)
}

func send(
    to handle: String,
    label: String = "",
    verify: Bool = true,                 // ← аварийный выключатель (PLAN-07)
    message: String,
    isGroup: Bool,
    dryRun: Bool,
    fast: Bool = false
) async -> BridgeMessage {
    let payload: [String: Any] = [
        "username": handle,
        "label": label,
        "verify": verify,
        "message": message,
        "isGroup": isGroup,
        "dryRun": dryRun,
        "fast": fast,
    ]
    // ... дальше без изменений
}
```

Таймаут остаётся 200 с: однопроходный сбор укладывает худший случай (~73 с скролла + открытия) в лимит (PLAN-08 закрыт архитектурно).

### 3.3. `Ugolek/Core/Planner/StreakEngine.swift` (ИЗМЕНИТЬ)

```swift
let reply = await InboxRunner.shared.send(
    to: friend.handle,
    label: friend.label,
    verify: store.settings.recipientVerification,
    message: outgoingMessage,
    isGroup: friend.isGroup,
    dryRun: dryRun,
    fast: store.settings.fastMode
)

// Часть D: структурированный флаг вместо строкового матчинга (PLAN-13)
if reply.alreadyMaintained == true {
    if !dryRun { AppStore.shared.markStreakMaintainedToday(friend.id) }
    results.append(FriendResult(
        friendId: friend.id, handle: friend.handle,
        status: .skipped, detail: "🔥 уже продлён сегодня"
    ))
    continue
}
```

Часть B (автообновление): retry вызывает тот же `InboxRunner.send(...)` — попадает в те же верифицированные точки JS (PLAN-04 закрыт автоматически). Перед повтором — `ProfileFetcher.fetch`, обновление `label` через `AppStore.shared.update(...)`, результат помечается в истории как `.blocked/.missing/.found`.

### 3.4. `Ugolek/Store/AppStore.swift` (ИЗМЕНИТЬ — PLAN-02)

```swift
/// Части D/E: отметить «стрик продлён сегодня» без отправки.
func markStreakMaintainedToday(_ id: UUID) {
    guard let i = friends.firstIndex(where: { $0.id == id }) else { return }
    friends[i].lastSentDay = Day.today()
    persist(.friends)
}

/// Часть E: снять ручную отметку (вернуть в очередь).
func resetSentDay(_ id: UUID) {
    guard let i = friends.firstIndex(where: { $0.id == id }),
          friends[i].lastSentDay != nil else { return }
    friends[i].lastSentDay = nil
    persist(.friends)
}
```

Все сниппеты плана используют эти публичные методы — никаких обращений к `private(set)`/private persist.

### 3.5. `Ugolek/Core/SessionStore/ProfileFetcher.swift` (НОВЫЙ — PLAN-11)

```swift
import Foundation

@MainActor
enum ProfileFetcher {
    enum Outcome {
        case found(nickname: String)   // профиль прочитан, ник извлечён
        case blocked                   // 200, но встроенных данных нет (бот-фильтр?)
        case missing                   // профиль не существует (404)
    }

    static func fetch(handle: String) async -> Outcome {
        guard let url = URL(string: "https://www.tiktok.com/@\(handle)") else { return .missing }
        var request = URLRequest(url: url)
        request.setValue(SessionStore.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .missing }

        guard let html = String(data: data, encoding: .utf8),
              let json = embeddedJSON(from: html) else { return .blocked }

        // Ищем узел пользователя, у которого uniqueId == handle (отсекает рекомендации)
        if let nick = findNickname(in: json, uniqueId: handle.lowercased()) {
            return .found(nickname: nick)
        }
        return .blocked
    }

    private static func embeddedJSON(from html: String) -> Any? {
        guard let range = html.range(of: "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\"[^>]*>",
                                     options: .regularExpression) else { return nil }
        guard let end = html.range(of: "</script>", range: range.upperBound..<html.endIndex) else { return nil }
        let raw = String(html[range.upperBound..<end.lowerBound])
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8))
    }

    /// Рекурсивный обход: находим словарь, где uniqueId совпадает, и берём его nickname.
    private static func findNickname(in node: Any, uniqueId: String) -> String? {
        if let dict = node as? [String: Any] {
            if let uid = dict["uniqueId"] as? String, uid.lowercased() == uniqueId,
               let nick = dict["nickname"] as? String, !nick.isEmpty {
                return nick
            }
            for child in dict.values {
                if let hit = findNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        } else if let arr = node as? [Any] {
            for child in arr {
                if let hit = findNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        }
        return nil
    }
}
```

JSON-парсер сам декодирует `\uXXXX` (PLAN-11); привязка к `uniqueId == handle` отсекает чужие ники из рекомендаций; страница бот-фильтра даёт `.blocked` → в истории честно «не удалось проверить профиль», а не «юзернейм сменился».

### 3.6. `Ugolek/Screens/FriendsView.swift` (ИЗМЕНИТЬ — части C и E, PLAN-10/14)

```swift
@State private var nickTask: Task<Void, Never>?
@State private var nickState: NickState = .idle
@State private var autoFilledLabel: String?      // последнее авто-значение

enum NickState { case idle, checking, found, blocked, missing }

TextField("@юзернейм", text: $handle)
    .onChange(of: handle) { _, newValue in
        let clean = newValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        nickTask?.cancel()
        guard !clean.isEmpty else { nickState = .idle; return }
        nickState = .checking
        nickTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            switch await ProfileFetcher.fetch(handle: clean) {
            case .found(let nick):
                nickState = .found
                // автофиилл не затирает ручные правки (PLAN-10):
                if label.isEmpty || label == autoFilledLabel {
                    autoFilledLabel = nick
                    label = nick
                }
            case .blocked:  nickState = .blocked
            case .missing:  nickState = .missing
            }
        }
    }
```

Индикатор: `.checking` → прогресс, `.found` → «✓ имя», `.blocked` → «не удалось проверить — введи руками», `.missing` → «страничка не найдена».

**Часть E — свайпы с обратным действием:**

```swift
.swipeActions(edge: .trailing) {
    if friend.lastSentDay == Day.today() {
        Button("↺ Вернуть в очередь") {
            AppStore.shared.resetSentDay(friend.id)
        }.tint(.gray)
    } else {
        Button("🔥 Продлили") {
            AppStore.shared.markStreakMaintainedToday(friend.id)
        }.tint(.orange)
    }
}
```

### 3.7. Настройки: аварийный выключатель (PLAN-07)

`AppSettings` += `var recipientVerification: Bool = true`. В `SettingsView` секция «Доставка»:

```swift
Toggle("Проверять получателя перед отправкой", isOn: $store.settings.recipientVerification)
```

Footer: «Если TikTok изменил вёрстку и проверка сломалась — выключи: Уголёк вернётся к старому поиску по имени (возможны промахи между тёзками)». Инженерно: счётчик `verifyFailures` из JS попадает в лог прогона → виден в истории → пользователь узнаёт о деградации селектора до того, как отключит.

### 3.8. `project.yml` / `HANDOFF.md`

Без изменений конфигурации. HANDOFF обновляется после реализации.

---

## 4. Порядок выполнения

| Этап | Содержание | Коммит |
|---|---|---|
| 1 | Часть A: однопроходный `collectCandidates`, `resolveItemByConvId`, `handleFromOpenChat`, `findAndOpenVerifiedChat`, замена ОБОИХ call site, payload label+verify, тумблер в настройках, `BridgeMessage.alreadyMaintained` | `feat: verify recipient by handle in opened chat (dual-needle, single sweep)` |
| 2 | Часть D: `threadTodayFlags()` + интеграция скипа, `AppStore.markStreakMaintainedToday` | `feat: skip already-maintained streaks via today-separator check` |
| 3 | Часть B: `ProfileFetcher` + retry с обновлением label | `feat: refresh stale nickname from public profile on miss` |
| 4 | Часть C+E: FriendsView — автоопределение, свайпы с обратным действием | `feat: auto-detect nickname; manual maintained swipe with undo` |
| 5 | HANDOFF | `docs: handoff notes on verified delivery` |

Каждый этап: push → CI зелёный → следующий.

---

## 5. Риски и компенсации (после ревизии)

| # | Риск | Было в ревизии 1 | Стало |
|---|------|------------------|-------|
| 1 | Сдвиг вёрстки панели → null-верификация | 100% недоставка (PLAN-07) | Тумблер `recipientVerification` → старое поведение; `verifyFailures` виден в логе; @-текстовый фолбэк |
| 2 | React-перерисовка → протухшие узлы | Тёзки коллапсировали (PLAN-06) | Re-resolve по `data-conv-id` перед каждым открытием; без convId — фолбэк с осознанным риском |
| 3 | Разделитель дат вне виртуализированного окна | Ложный скип (PLAN-03/05) | Нет разделителя → `'unknown'` → пишем (дефолт «писать» сохранён) |
| 4 | Тайм-регэкспы на тексте сообщений | Ложные скип/resend (PLAN-05) | Убраны полностью: единственный источник — разделитель дат |
| 5 | Второй call site мимо верификации | Промах возвращался (PLAN-04) | Заменяются ОБЕ точки; retry идёт через общий send |
| 6 | Private-доступ из сниппетов | Не компилируется (PLAN-02) | Публичные `markStreakMaintainedToday`/`resetSentDay` |
| 7 | Первый `"nickname"` в HTML чужой | Ложные имена (PLAN-11) | JSON-парсинг + привязка `uniqueId == handle`; `.blocked` отдельно |
| 8 | Два прохода скролла > таймаут | Кросс-контаминация (PLAN-08) | Один проход с двумя иглами; худший случай ~73+открытия < 200 с |
| 9 | closeChat открывает чужие чаты | PLAN-09 | Только back-кнопка + nav-messages; чужие элементы не кликаются |
| 10 | Случайный свайп «Продлили» | Метку не снять (PLAN-14) | Обратное действие «↺ Вернуть в очередь»; действует до конца дня |

Остаточные принятые риски: направление сообщения определяется эвристикой классов (при сдвиге → `'unknown'` → пишем); dry-run открывает реальные чаты (read-receipts) — задокументировано.

---

## 6. Поток данных

```
Добавление друга (C):  @nnnnll67nl → debounce → ProfileFetcher
                       → .found("Нн") → label="Нн" ✓ (ручные правки защищены)
                       → .blocked → «введи имя руками»

Ручной скип (E):       свайп → markStreakMaintainedToday(id)
                       → lastSentDay=сегодня → вне очереди до завтра
                       (↺ Вернуть в очередь снимает)

Прогон (A + D + B):
  друг {handle:"nnnnll67nl", label:"Нн"}
  → send(to:, label:, verify:true, ...)
  → collectCandidates("nnnnll67nl","Нн",false)   // ОДИН проход, обе иглы
      item#7  rank1 (title=="nnnnll67nl"?? нет) …
      item#12 rank2 (nickname=="Нн")
      item#31 rank4 (фаззи по label)
  → ordered: [#12(r2)? нет — r1 нет → #12(r2), #31(r4)]
  → resolveItemByConvId(#12) → openChat
      handleFromOpenChat() → "someone_else" ≠ → closeChat()
  → resolveItemByConvId(#31) → openChat
      handleFromOpenChat() → "nnnnll67nl" ✓
      threadTodayFlags(): разделитель «Сегодня» найден
         [моё 12:41][его ответ 12:50] → mine ✓ theirs ✓
      → alreadyMaintained=true → closeChat()
  → post(ok:true, alreadyMaintained:true)
  → StreakEngine: lastSentDay=сегодня, skipped «🔥 уже продлён сегодня»
```

---

## 7. Файлы проекта

| Файл | Действие |
|------|----------|
| `Resources/send.js` | Изменить: collectCandidates (один проход, ранги), resolveItemByConvId, handleFromOpenChat (+@-фолбэк), threadTodayFlags, findAndOpenVerifiedChat, closeChat, замена ОБОИХ call site, ветка verify=false |
| `Ugolek/Core/InboxEngine/InboxRunner.swift` | Изменить: BridgeMessage.alreadyMaintained, send(label:verify:), payload |
| `Ugolek/Core/Planner/StreakEngine.swift` | Изменить: передача label/verify, обработка alreadyMaintained, Part B retry |
| `Ugolek/Core/SessionStore/ProfileFetcher.swift` | Создать |
| `Ugolek/Store/AppStore.swift` | Изменить: markStreakMaintainedToday/resetSentDay |
| `Ugolek/Models/AppSettings.swift` | Изменить: recipientVerification |
| `Ugolek/Screens/FriendsView.swift` | Изменить: автоопределение + свайпы |
| `Ugolek/Screens/SettingsView.swift` | Изменить: тумблер верификации |
| `HANDOFF.md` | Обновить после реализации |

---

## 8. Проверки на телефоне

1. Ник≠юз теперь доставляется (главный кейс).
2. Два «Нн» → каждому правильному; второй кандидат открывается после несовпадения первого.
3. Переписка «моё → его ответ» сегодня → скип «🔥 уже продлён сегодня».
4. Ты писал, он молчал → скип «повтор бесполезен».
5. Он написал, ты не отвечал → прогон пишет (спасает стрик).
6. Тумблер верификации OFF → старое поведение (первый совпавший).
7. Свайп «Продлили» → друг вне очереди; «↺ Вернуть» → вернулся.
8. Отзыв/ребут/бот-фильтр профиля → честные статусы в истории.
9. Группы — по названию, без верификации юза.

---

## 9. Влияние

| Параметр | Оценка |
|---|---|
| Время (обычный друг) | +2–3 с (проверка handle) |
| Время (тёзки) | +5–15 с на лишнего кандидата |
| Время (продлён вручную, автодетект) | +2–3 с, экономит полную отправку |
| Время (Part B retry) | +10–15 с на друга, разово |
| Доставляемость | ↑ (ник≠юз доходят) |
| Безопасность | ↑ (промахи исключены; дефолты консервативны) |
| Спам | ↓ (продлённые не получают дублей) |

---

## 10. Changelog ревизии 2 (трассировка находок ревью)

| Атака | Закрыто |
|---|---|
| PLAN-01 (CFG.scrollStep) | §3.1 п.1 — шаг clientHeight×0.7 |
| PLAN-02 (private доступ) | §3.4 — публичные методы AppStore |
| PLAN-03 (флаги без даты) | §3.1 п.4 — разделитель дат вместо регэкспов |
| PLAN-04 (второй call site) | §3.1 п.6 — замена обеих точек |
| PLAN-05 (тайм-регэкспы на тексте) | §3.1 п.4 — текст сообщений не анализируется |
| PLAN-06 (React-узлы) | §3.1 п.2 — resolveItemByConvId |
| PLAN-07 (регрессия доставки) | §3.1 п.6 + §3.7 — тумблер + @-фолбэк + счётчик |
| PLAN-08 (2 прохода > timeout) | §3.1 п.1 — один проход, две иглы |
| PLAN-09 (closeChat) | §3.1 п.7 — реальные хелперы |
| PLAN-10 (FriendsView свойства) | §3.6 — объявленные состояния + защита ручных правок |
| PLAN-11 (nickname regex) | §3.5 — JSON + uniqueId-матч + .blocked |
| PLAN-12 (dry-run открывает чаты) | Принят, задокументирован в §5 |
| PLAN-13 (строковый контракт) | §3.2/§3.3 — BridgeMessage.alreadyMaintained |
| PLAN-14 (метку не снять) | §3.6 — обратное действие |

*План составлен на основе изученного кода и адверсариального ревью ревизии 1. Ничего не реализовано.*
