# Адверсариальный ревью Уголька — ядро, данные, расписание, движок, виджет

Дата: 2026-08-25. Ревьюер: adversarial-агент (зона «ядро»). Цель — доказать, что приложение ломается.
Метод: только чтение реального кода (файл:строка). Ничего не чинилось, файлы в `Ugolek/` не трогались.
Статусы: **CONFIRMED** (следует из кода напрямую), **SUSPECTED** (нужен рантайм/устройство).
Артефакт-тесты: `Tests/AdversarialCoreTests.swift`.

Итого: **17 находок** (2 CRITICAL, 4 HIGH, 7 MEDIUM, 4 LOW), **8 атак отбито**.

---

## CRITICAL

### CORE-01 · Параллельный прогон движка: dry-run и Диагностика обходят guard `runActive`, роняют `loadContinuation` и вешают приложение навсегда
**CONFIRMED (логика) / SUSPECTED (триггер пользователем). Severity: CRITICAL**

Единственный замок движка — `RunCoordinator.runActive` (`Ugolek/Core/Planner/RunCoordinator.swift:10,32,58`). Но мимо него есть два входа, которые дергают `StreakEngine`/`InboxRunner` напрямую:

- `SettingsView.runDryTest()` → `StreakEngine.run(dryRun: true)` — `Ugolek/Screens/SettingsView.swift:146` (вызывается из тумблера «Гео всегда», :121-141);
- `HomeView.runDiagnostics()` → `InboxRunner.ensureLoaded()` — `Ugolek/Screens/HomeView.swift:140`.

`InboxRunner.loadContinuation` — одно поле (`Ugolek/Core/InboxEngine/InboxRunner.swift:36`). Верхний guard в `ensureLoaded` пропускает второго игрока, пока идёт первая загрузка (`loadedURL == nil`, :44). Дальше:

1. Вызов A ставит `loadContinuation = contA` и стартует load (:48-51).
2. Вызов B перезаписывает `loadContinuation = contB` (:48) и повторно вызывает `webView?.load` (:51).
3. `didFinish` резюмит только contB (`InboxRunner.swift:259-266`). **contA не возобновится никогда** — Task вызова A виснет в `await` навечно.
4. Если A был `RunCoordinator.start()`: строки `runActive = false; LocationKeeper.release()` (`RunCoordinator.swift:48-49`) не выполняются → `runActive` застревает `true`.
5. UI: `.fullScreenCover(isPresented: $coordinator.runActive)` (`Ugolek/Screens/HomeView.swift:92`) накрывает экран оверлеем «Продлеваю огоньки…» навсегда, кнопка задизейблена (`HomeView.swift:62`). Приложение кирпич до убивания процесса.

Даже без зависания два параллельных прогона перемешивают состояние: `onLog` перезаписывается каждым запуском и обнуляется его же `defer` (`Ugolek/Core/Planner/StreakEngine.swift:22-23`) — логи чужого прогона теряются; `resultContinuation` в `runJS` перезаписывается так же, как `loadContinuation` (`InboxRunner.swift:118-119`).

Пошаговый сценарий (гонка): 21:59 срабатывает авто-прогон «Гео всегда» (headless) → пользователь в этот момент открывает Настройки и щёлкает «Гео всегда» повторно / жмёт Диагностику на Главной → contA утрачен → вечный оверлей.

Тест: `Tests/AdversarialCoreTests.swift::test_CORE01_concurrentEnsureLoaded_leaksFirstContinuation` (async-скетч с окном гонки).

### CORE-02 · 95-секундный нативный таймаут короче худшего пути send.js → поздний «result» теряется, JS продолжает слать параллельно следующему другу
**CONFIRMED (арифметика) / SUSPECTED (реализация TikTok). Severity: CRITICAL**

Нативный watchdog `runJS` — 95 с (`InboxRunner.swift:121-131`); просрочка резюмится как `ok:false` «Превышено время ожидания». Худший путь одного `Ugolek.run` в `Resources/send.js`:

- ожидание списка чатов до 15 с (`send.js:134-137`);
- скролл поиска друга: до `scrollMaxSteps=60` шагов × `scrollStepMs=1200` ≈ **72 с только скролла** (`send.js:11-12`, цикл `send.js:196-240`);
+ открытие чата (~6 с), ввод/клик (~4 с), verify 3×1200 мс (`send.js:786-794`) ≈ **>95 с уже в первой попытке**, а `run()` делает **две попытки** (`send.js:892-919`) → до ~170 с.

Последствия:
1. Нативная сторона на 95-й секунде пометила друга `failed/skipped` и ушла к следующему, а JS-попытка №2 тем временем реально отправляет сообщение → друг получает сообщение, но в истории он «провален»; завтра ему уйдёт ещё одно (дубль поверх живого стрика).
2. Опоздавший `post({type:'result'})` приходит при пустом `resultContinuation` (`InboxRunner.swift:223-231`) и молча выбрасывается.
3. Следующий `runJS` стартует, пока старый JS ещё крутится: два `Ugolek.run` конкурируют за один contenteditable → тексты смешиваются, сообщение уходит не тому чату.

Лестница ретраев `InboxRunner.send` (reload 8 с + второй runJS + clearSiteData + третий runJS, `InboxRunner.swift:102-112`) растягивает одного друга до ~5 минут — что делает реальным CORE-08 (переход через полночь).

Тест: `test_CORE02_sendJsWorstCase_exceedsNativeTimeout` (арифметическое воспроизведение).

---

## HIGH

### CORE-03 · Один непарсящийся байт в JSON = молча дефолтные настройки, а первый persist затирает список друзей безвозвратно
**CONFIRMED. Severity: HIGH**

- `loadAll` дважды `try?` на каждый файл (`Ugolek/Store/AppStore.swift:117-122`): битый `settings.json` → кастомный текст сообщения, время, все тумблеры молча сбрасываются на дефолт, без единого предупреждения. Первый же `didSet` (`AppStore.swift:9`) перепишет файл дефолтом — потеря необратима.
- Битый `friends.json` → `friends = []`. Файл остаётся битым ровно до первого `persist(.friends)` — а его делает даже не экран «Друзья»: `record()` после КАЖДОГО прогона пишет `persist(.friends)` (`AppStore.swift:86-87`). Итог: после первого же запуска поверх битого файла записывается текущий пустой массив → список друзей уничтожен навсегда (бэкапов нет).
- Триггер, не требующий «битого байта»: `Friend.init(from:)` требует ключ `handle` как `try c.decode` (`Ugolek/Models/Friend.swift:27`). Одна запись без `handle` (ручной экспорт-правка, старая версия схемы, будущий рефакторинг CodingKeys) валит ДЕКОДИРОВАНИЕ ВСЕГО МАССИВА → тот же сценарии полного обнуления. Версионирования/миграций нет.

Тест: `test_CORE03_friendMissingHandle_poisonsWholeArrayDecode`, `test_CORE03_settingsCorruptJson_fallsBackToDefaultsSilently`.

### CORE-04 · Кнопка Пункта управления выполняет пустую копию интента из виджет-расширения; плюс возможное задвоение действия в Командах
**SUSPECTED (роутинг системы) при CONFIRMED структуре. Severity: HIGH**

`MaintainStreaksIntent.swift` компилируется в ОБА таргета (`project.yml:50-51`), причём тело `perform()` в расширении пустое — `RunCoordinator` обёрнут в `#if !WIDGET_EXTENSION` (`Ugolek/Core/AppIntents/MaintainStreaksIntent.swift:11-13`). `UgolekControlWidget` держит контрол именно в расширении и ссылается на этот тип (`Ugolek/Core/AppIntents/UgolekControlWidget.swift:11`).

Сценарий: тап 🔥 в Пункте управления → система исполняет копию интента из процесса виджета → `perform()` мгновенно возвращает `.result()`, ничего не запуская. `openAppWhenRun = true` (:7) может открыть приложение, но при старте приложения `pendingAutoRun == false`, а `consumePendingAutoRunIfNeeded()` лишь съедает флаг (`Ugolek/Screens/MainTabView.swift:20`, `RunCoordinator.swift:75-80`) → **приложение открылось, рассылка не пошла**. HANDOFF («мелькнула → дальше само») предполагает автозапуск, который в коде не существует для этого пути.

Второй эффект: расширение донатит в систему действие «Продлить огоньки» с тем же именем, что и приложение → риск двух одинаковых действий в библиотеке Команд, где выбранное может оказаться пустым (SUSPECTED, зависит от дедупликации iOS).

Тест: `test_CORE04_widgetCopyOfIntent_performIsEmpty` (структурная проверка исходника невозможна в рантайме — тест фиксирует контракт: тело под WIDGET_EXTENSION пусто).

### CORE-05 · Джиттер ±15 мин умеет переносить СЕГОДНЯШНЕЕ напоминание на завтра, если открыть приложение за ≤15 мин до времени
**CONFIRMED (логика). Severity: HIGH**

`scheduleDaily()` джиттерует ДО сравнения с «сейчас» (`Ugolek/Core/Planner/ReminderService.swift:40-55`): база = сегодня 22:00, jitter −15 → scheduled 21:45; открытие приложения в 21:46 (`MainTabView.swift:24` зовёт `scheduleDaily()` на каждый `.active`) → условие `scheduled <= .now` истинно → триггер уезжает на ЗАВТРА 21:45, хотя до сегодняшнего напоминания оставалось 14 минут. Окно [T−15; T) + отрицательный jitter = сегодняшний тап-уведомление не существует, авто-прогон по тапу тоже. У Кирилла с привычкой «открыть приложение перед временем» это стабильный пропуск дня.

Отмечено: у `AutoRunner.scheduleNext` тот же узел написан правильно — с запасом `+60 c` и сравнением ДО джиттер-вычитания неявно (`AutoRunner.swift:43-45`) — асимметрия подтверждает, что в ReminderService это именно баг.

Тест: `test_CORE05_jitterPast_reschedulesTodayToTomorrow` (воспроизведение формулы на Calendar).

---

## MEDIUM

### CORE-06 · `lastRandomMessage` запоминает кастомный текст вместо отправленной фразы — «без повторов подряд» не работает
**CONFIRMED. Severity: MEDIUM**

`StreakEngine.swift:62-64`: после успешной отправки случайной фразы в `lastRandomMessage` пишется `store.settings.messageText` (кастомный текст), а не фраза, которая реально ушла. `MessagePool.random(excluding:)` затем исключает строку, которой в пуле нет (`Ugolek/Models/MessagePool.swift:38-44`) → исключение ничего не исключает, `randomElement()` может выдать ту же фразу подряд. Обещание футера настроек («без повторов подряд», `SettingsView.swift:25`) ложно. Тест: `test_CORE06_lastRandomMessage_storesWrongString`.

### CORE-07 · Импорт друзей не дедуплицирует внутри самого файла → двойные записи → двойная отправка одному другу
**CONFIRMED. Severity: MEDIUM**

`importFriendsJSON` строит `existingHandles` ОДИН раз до цикла и не пополняет его при добавлении (`AppStore.swift:43-51`). JSON с двумя одинаковыми handle добавит обе записи. Дальше `friendsDueToday` вернёт обе (`AppStore.swift:55-62`), и `StreakEngine` отправит другу два сообщения за один прогон (два таргета с одним handle). UI рапортует «Добавлено друзей: 2». Тест: `test_CORE07_importDuplicatesWithinFile_addedTwice`.

### CORE-08 · Прогон, перешедший полночь, штампует `lastSentDay` новым днём → друг пропустит ЦЕЛЫЙ день (стрик умирает)
**CONFIRMED (логика) / SUSPECTED (частота). Severity: MEDIUM**

`record()` берёт `Day.today()` в момент ЗАПИСИ (`AppStore.swift:73,79`), а не в момент старта прогона. При переходе полуночи во время длинного прогона (реализуемо: лестница ретраев CORE-02 ~5 мин/друг × N друзей) всем `.sent` поставится вчерашне-сегодняшняя дата НОВОГО дня → на новом дне `friendsDueToday` их исключит (`lastSentDay != today` ложь) → сообщения в новый день не уйдут никому из «отправленных после полуночи» → огонёк гаснет, хотя пользователь всё сделал вовремя. Тест: `test_CORE08_runCrossingMidnight_marksWrongDay`.

### CORE-09 · Бесконечная часовая цепочка снузов при одном «вечнозависимом» друге; счётчик в тексте заморожен на момент планирования
**CONFIRMED. Severity: MEDIUM**

`refreshAfterRun` (`ReminderService.swift:91-98`): если остались должники И (sentCount>0 || failedCount>0) → `scheduleSnoozes()` заново на +60/+120/+180 мин от СЕЙЧАС. Друг, которого TikTok не находит (skipUnreachable=true → статус skipped, но в каждом прогоне есть и успешные), даёт sentCount>0 и dueLeft непустой вечно → снузы каждые 60 минут до бесконечности, каждый тап = новый прогон = новая нагрузка на аккаунт. Плюс текст снуза запекает `friendsDueToday.count` на момент планирования (`ReminderService.swift:71`) — «5 друзей ждут», когда их уже 1. Тест: `test_CORE09_snoozeLoop_neverEndsWithPermanentFailure`.

### CORE-10 · Headless-итог врёт: «все огоньки уже горят», когда все друзья ПРОВАЛИНЫ
**CONFIRMED. Severity: MEDIUM**

`HeadlessStreaksIntent.notifyResult` ветка `else` при `sentCount == 0` печатает «Нечего продлевать — все огоньки уже горят 🔥» (`HeadlessStreaksIntent.swift:29-33`) — включая случай `failedCount > 0` (сеть отвалилась, разлогин). Пользователь уверен, что всё продлено; стрик тихо гаснет. Тест: `test_CORE10_headlessAllFailed_reportsSuccess`.

### CORE-11 · Watchdog LocationKeeper принудительно гасит гео на 900-й секунде ЛЕГАЛЬНОГО долгого прогона → фон замирает
**CONFIRMED (логика) / SUSPECTED (проявление). Severity: MEDIUM**

Watchdog однократно взводится на `acquire()` и через 900 с сливает ВСЕ аренды (`LocationKeeper.swift:74-81`); во время прогона никто его не перезаводит. Комментарий считает, что 15 мин — «значит прогон завис», но легальный прогон по CORE-02 легко длиннее (5 мин/друг × 5 друзей = 25 мин). Для headless/свёрнутого прогона после 15-й минуты `allowsBackgroundLocationUpdates=false` → процесс замораживается посреди рассылки, часть друзей не получит ничего, запись в историю не попадёт (она только в конце, `StreakEngine.swift:81-87`). Тест: `test_CORE11_watchdog_releasesMidRunAfter15min`.

### CORE-12 · Куки сохраняются только при логине; рестор перезатирает ротированные куки → invalidate стирает сессию целиком
**SUSPECTED (ротация на стороне TikTok). Severity: MEDIUM**

`SessionStore.saveCookies` вызывается ровно из одного места — LoginView (`Ugolek/Screens/LoginView.swift:64`; grep по репозиторию). `restoreCookies` при каждом старте движка НАСАЖИВАЕТ старый снимок в сторе вебвью (`SessionStore.swift:56-74`), затирая свежие куки, полученные во время прошлых прогонов. Если TikTok ротировал `sessionid` — движок увидит top-login-button и вызовет `invalidate()` (`InboxRunner.swift:63-68`), который удаляет и sessionKey, и cookiesKey (`SessionStore.swift:76-80`) → принудительный релогин и потеря всего. Тест: `test_CORE12_restoreOverwritesRotatedCookies_thenInvalidates` (скетч).

---

## LOW

### CORE-13 · `lastSentDay` — локальная дата строкой: перелёт/перевод часов/ручная правка даты дают дубль или пропуск
**CONFIRMED дизайн-дыра / SUSPECTED частота. Severity: LOW**
`Day.today()` = компоненты локального календаря (`Ugolek/Models/Day.swift:3-11`). Перелёт на восток через полночь → «новый день» наступает дважды за сутки → дубль-отправка; на запад → день растягивается → пропуск. Перевод системной даты вручную (любимое тестовое действие) → массовый повторный спам всем друзьям. Тест: `test_CORE13_timezoneShift_doubleSendWindow`.

### CORE-14 · Keychain: результат SecItemAdd игнорируется — тишина при -34018
**SUSPECTED. Severity: LOW**
`KeychainStore.setString`: delete→add без проверки кодов (`KeychainStore.swift:13-16`). При отказе keychain (free-provisioning энтайтменты, -34018) логин/куки молча не сохранятся — «переживают переустановку» превращается в «не сохраняются вообще», диагностировать нечем. Тест: `test_CORE14_keychainAddError_swallowed` (скетч — нужен runtime).

### CORE-15 · История режется до 50 молча; экспортировать можно только лог отдельного прогона
**CONFIRMED. Severity: LOW**
`record()` молча удаляет хвост за кэпом (`AppStore.swift:12,70-71`); предупреждений нет; HistoryView экспортирует лишь `run.log` конкретного прогона (`HistoryView.swift:115-127`) — статистика за пределами 50 прогонов невосстановима. Тест: `test_CORE15_historyCap_silentTruncation`.

### CORE-16 · `consumePendingAutoRunIfNeeded` молча съедает тап: нет логина / нет должников / прогон уже идёт
**CONFIRMED. Severity: LOW**
Флаг сбрасывается ДО проверки условий (`RunCoordinator.swift:76-77`); любой guard (:78) глотает тап по уведомлению без единого отклика. Тап при идущем прогоне — просто ничего. Тест: `test_CORE16_pendingAutoRun_eatenSilently`.

---

## Отбитые атаки (8)

1. **MessagePool.random: бесконечный цикл при исчерпании пула** — ОТБИТ. Реализация без циклов: `filter` + `randomElement` + фолбэк `phrases[0]`; исключается максимум одна фраза, пусто не бывает (`MessagePool.swift:38-44`).
2. **BGTaskSchedulerPermittedIdentifiers ≠ CatchUpTask.identifier** — ОТБИТ. Точное совпадение `com.ugolek.app.catchup` (`project.yml:44-45` ↔ `CatchUpTask.swift:5`).
3. **BGTask запускает WebView под замком** — ОТБИТ. `CatchUpTask.handle` только считает overdue и постит локальное уведомление (`fireCatchUp`), движок не трогает (`CatchUpTask.swift:21-44`).
4. **AppSettings: новое/старое поле роняет decode** — ОТБИТ (частично). Кастомный `init(from:)` c `decodeIfPresent`+дефолтами переживает отсутствующие поля (`AppSettings.swift:19-30`); остриё остаётся только для смены ТИПА поля или битого JSON (CORE-03).
5. **Виджет читает Keychain чужого service/access group** — ОТБИТ. Виджетная копия интента не касается ни SessionStore, ни Keychain (тело пустое), HeadlessStreaksIntent в виджет не компилируется (`project.yml:49-51`).
6. **AutoRunner повторяет джиттер-баг ReminderService** — ОТБИТ. Там запас +60 с до переноса на завтра (`AutoRunner.swift:43-45`).
7. **Двойной acquire/release локации в headless-цепочке разбалансирует счётчик** — ОТБИТ. `acquire` в интенте + в startHeadless уравновешены двумя release (defer'ы) (`HeadlessStreaksIntent.swift:19-20` + `RunCoordinator.swift:61-64`; refcount `LocationKeeper.swift:36-46`).
8. **Кэп истории портит счётчики друзей** — ОТБИТ. `sentCount/failCount` друзей живут в friends.json независимо от обрезки runs (`AppStore.swift:69-88`).

---

## Сводная таблица

| ID | Severity | Статус | Суть | Файл:строка |
|----|----------|--------|------|-------------|
| CORE-01 | CRITICAL | CONFIRMED | Параллельный ensureLoaded теряет continuation → вечный оверлей | InboxRunner.swift:36,44-58; SettingsView.swift:146; HomeView.swift:140 |
| CORE-02 | CRITICAL | CONFIRMED* | send.js >95 c: поздний result теряется, параллельный JS | InboxRunner.swift:122; send.js:11-12,196,892-919 |
| CORE-03 | HIGH | CONFIRMED | Битый JSON → дефолты; первый persist стирает друзей | AppStore.swift:117-122,86-87; Friend.swift:27 |
| CORE-04 | HIGH | SUSPECTED | Кнопка CC исполняет пустую копию интента; задвоение в Командах | project.yml:50-56; MaintainStreaksIntent.swift:11-13 |
| CORE-05 | HIGH | CONFIRMED | Джиттер переносит сегодняшнее напоминание на завтра | ReminderService.swift:40-55; MainTabView.swift:24 |
| CORE-06 | MEDIUM | CONFIRMED | lastRandomMessage ≠ отправленная фраза | StreakEngine.swift:62-64 |
| CORE-07 | MEDIUM | CONFIRMED | Импорт не дедуплицирует внутри файла → двойная отправка | AppStore.swift:43-51 |
| CORE-08 | MEDIUM | CONFIRMED | Прогон через полночь штампует неверный lastSentDay | AppStore.swift:73,79 |
| CORE-09 | MEDIUM | CONFIRMED | Вечные часовые снузы; счётчик заморожен | ReminderService.swift:71,91-98 |
| CORE-10 | MEDIUM | CONFIRMED | «Все огоньки горят» при полном провале | HeadlessStreaksIntent.swift:29-33 |
| CORE-11 | MEDIUM | CONFIRMED* | Watchdog 900 с гасит гео посреди легального прогона | LocationKeeper.swift:74-81 |
| CORE-12 | MEDIUM | SUSPECTED | Рестор перезатирает ротированные куки → invalidate | SessionStore.swift:56-80; LoginView.swift:64 |
| CORE-13 | LOW | CONFIRMED* | Локальная дата: TZ/перевод часов → дубль/пропуск | Day.swift:3-11 |
| CORE-14 | LOW | SUSPECTED | SecItemAdd без проверки кода ошибки | KeychainStore.swift:13-16 |
| CORE-15 | LOW | CONFIRMED | Молчаливая обрезка истории до 50 | AppStore.swift:12,70-71 |
| CORE-16 | LOW | CONFIRMED | Тап уведомления съедается молча | RunCoordinator.swift:75-80 |

\* — CONFIRMED логика/арифметика; проявление зависит от рантайма.
