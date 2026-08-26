# Адверсариальный ревью Уголька — фоновый стек (LocationKeeper / AutoRunner / HeadlessStreaksIntent)

Дата: 2026-08-25. Ревьюер: adversarial-агент (зона «фоновые режимы», уровни 1–3).
Цель — доказать, что свежий фоновый стек ломается. Ничего не чинилось, файлы в `Ugolek/` не трогались.
Метод: только чтение реального кода (файл:строка) + сверка с замыслом `docs/background-modes-plan.md` и `HANDOFF.md` («Фоновые режимы»).
Статусы: **CONFIRMED** (следует из кода напрямую), **SUSPECTED** (нужен рантайм/устройство).
Артефакт-тесты: `Tests/AdversarialBackgroundTests.swift`.

Итого: **13 находок** (2 CRITICAL, 4 HIGH, 6 MEDIUM, 1 LOW), **5 атак отбито** (BG-03, BG-11 и три податаки внутри BG-05/BG-07/BG-08).

Нумерация BG-01…BG-13 соответствует стартовым направлениям атаки 1–13; BG-14/BG-15 — собственные находки.

---

## CRITICAL

### BG-01 · Watchdog 900 с убивает ЛЕГАЛЬНЫЙ медленный прогон: drain обнуляет аренду, пока рассылка ещё идёт → процесс замораживают на середине, история не пишется, завтра — двойные отправки
**CONFIRMED (логика). Severity: CRITICAL**

Механика: `acquire()` ставит сторож ровно один раз на весь прогон (`Ugolek/Core/Background/LocationKeeper.swift:36-40` → `resetWatchdog()` :74-81). Внутри прогона **нечего** сторож не сбрасывает: `resetWatchdog` private, вызывается только из `acquire()`. Прогон же легально живёт дольше 15 минут:

- паузы между друзьями 2–6 с в обычном режиме (`Ugolek/Core/Planner/StreakEngine.swift:76-77`);
- один друг по худшему пути `InboxRunner.send`: до 3 попыток × 95 с + reloadPage(8+3 с) ≈ до ~5 мин (`Ugolek/Core/InboxEngine/InboxRunner.swift:102-112,121-131`) — арифметику худшего пути подтверждает и CORE-02;
- `ensureLoaded` до ~45 с только на старт (`InboxRunner.swift:48-57,62-71`).

30 друзей при плавающем TikTok — это 15–20+ минут гарантированно. На 900-й секунде:

1. Сторож просыпается: `while self.acquireCount > 0 { self.release() }` (`LocationKeeper.swift:79`) → счётчик 1→0.
2. `stopIfNeeded()` (:65-71): `stopUpdatingLocation()` + `allowsBackgroundLocationUpdates = false`.
3. iOS через секунды замораживает фоновый процесс. `StreakEngine.run` висит в `await InboxRunner.send` посреди списка друзей (`StreakEngine.swift:53`).

Пострадавшие сценарии — все, кто держится только на scoped-аренде (persistent=false):
- **Уровень 2:** `HeadlessStreaksIntent.perform()` → acquire (`HeadlessStreaksIntent.swift:19`) → долгий ночной прогон >15 мин → процесс заморожен → ни уведомления, ни записи в историю.
- **Уровень 1 (ручной 🔥 свёрнут):** `RunCoordinator.start()` → acquire (`RunCoordinator.swift:38`).

Двойной удар: `store.record(record)` выполняется только ПОСЛЕ цикла (`StreakEngine.swift:87`), поэтому замороженный прогон теряет ВСЮ историю, включая уже реально отправленные сообщения. `lastSentDay` не обновлён → завтрашний прогон пришлёт этим же друзьям повторно (дубль поверх живого стрика — прямо противоположность цели проекта).

Хвост: когда прогон всё же завершился бы, его `release()` упирается в `guard acquireCount > 0` (`LocationKeeper.swift:43`) и молча no-op — бухгалтерия аренды навсегда рассинхронизирована.

Это прямое противоречие обещанию уровня 1 (HANDOFF.md:88-89: «прогон дойдёт до конца») и Risk 5 плана («Watchdog гарантирует, что локация не останется висеть при зависшем прогоне» — сторож не отличает зависший прогон от медленного).

Тест: `test_BG01_slowRunBudget_exceedsWatchdogCap`.

### BG-13 · В project.yml нет ключа NSLocationWhenInUseUsageDescription → первый же тап тумблера «Гео всегда» роняет приложение; геолокация неавторизуемая ВООБЩЕ
**CONFIRMED (конфигурация) / SUSPECTED (крэш на устройстве — поведение документировано Apple). Severity: CRITICAL**

В сгенерированном Info.plist есть только два ключа: `NSLocationAlwaysAndWhenInUseUsageDescription` и `NSLocationAlwaysUsageDescription` (`project.yml:39-40`; других NSLocation* в репозитории нет — проверено grep; Info.plist генерирует XcodeGen, checked-in plist отсутствует). Ключ **NSLocationWhenInUseUsageDescription отсутствует**.

При этом тумблер вызывает `manager.requestAlwaysAuthorization()` (`Ugolek/Screens/SettingsView.swift:123` → `Ugolek/Core/Background/LocationKeeper.swift:31-33`). Требование платформы (iOS 11+): для запроса Always нужны ОБА ключа — WhenInUse и AlwaysAndWhenInUse; система внутри сначала запрашивает when-in-use. Без WhenInUse-ключа запрос авторизации завершается системным исключением и termination приложения.

Последствия:
1. Пользователь включает тумблер «Гео всегда» → приложение падает. Уровень 3 мёртв на первом шаге (проверка №3 из HANDOFF.md:111 невыполнима).
2. Уровни 1–2 тоже под ударом: без любого из usage-ключей разрешение локации нельзя выдать даже вручную в Настройках iOS — приложение не появится в списке «Геолокация» корректно, `allowsBackgroundLocationUpdates` не даст эффекта без авторизации.
3. Ни CI (компил-check), ни симуляторный прогон это не ловят — крэш только на реальном запросе.

Замысел vs код: план §3.8 требовал добавить оба NSLocation*-ключа — реализатор добавил Always-пару и пропустил WhenInUse.

Тест: `test_BG13_projectConfig_missingWhenInUseUsageKey`.

---

## HIGH

### BG-02 · Гонка тумблера: неотыслеживаемый dry-test Task перезаряжает startPersistent()+arm() ПОВЕРХ выключенного состояния (и наоборот, провал старого теста затирает свежее включение)
**CONFIRMED. Severity: HIGH**

`handleGeoToggle(true)` запускает **неотменяемый, непомеченный** `Task { ... }` с сетевым dry-run до минуты (`Ugolek/Screens/SettingsView.swift:124-136`; сам тест тянет `ensureLoaded` ≈45 с + JS, `SettingsView.swift:143-148`). Индикатора «идёт тест» в UI нет.

Сценарий A (успех поверх OFF):
1. Юзер включает тумблер → task1 пошёл в сеть.
2. Юзер ничего не видит, выключает тумблер → `onChange(false)` → `disarm()` + `stopPersistent()` (`SettingsView.swift:137-140`). Флаг `geoAlwaysAuto = false`, всё чисто.
3. task1 успешно возвращается → ветка ok выполняет `startPersistent()` + `AutoRunner.shared.arm()` + постит «Фон готов: N друзей ждут 🔥» (`SettingsView.swift:126-129`) — **не проверяя текущее значение флага**.
4. Итог: `LocationKeeper.persistent == true` при `settings.geoAlwaysAuto == false`. Постоянная фоновая геолокация (синяя стрелка, живой процесс 24/7, батарея) без ведома юзера, пока его не убьёт ребут/перезапуск приложения или отзыв разрешения (`geoPermissionRevoked`). Единственный внутренний предохранитель — `fireAndReschedule` перепроверяет флаг перед выстрелом (`Ugolek/Core/Background/AutoRunner.swift:60`) — но он гасит только прогон, не аренду.

Сценарий B (провал старого теста поверх нового ON):
1. ON → task1; OFF; снова ON → task2, флаг true.
2. Медленный task1 завершается провалом → пишет `store.settings.geoAlwaysAuto = false` (`SettingsView.swift:131`) — затирая решение юзера, включившего режим секундой раньше; onChange(false) гасит то, что успел вооружить task2.
3. Затем успешный task2 делает `startPersistent()+arm()` → снова состояние «аренда включена, флаг выключен» (как в A).

Корень: у тестовой задачи нет поколения/отмены и нет перепроверки `store.settings.geoAlwaysAuto` в момент успеха.

Тест: `test_BG02_staleDryTestTask_overridesToggleOff_interleavingSketch`.

### BG-04 · runDryTest зовёт StreakEngine.run напрямую, минуя RunCoordinator: окно гонки «тест тумблера ↔ ночной авто-прогон ↔ ручная кнопка» = два движка на одном InboxRunner
**CONFIRMED (структура). Severity: HIGH** (пересекается с CORE-01; здесь — окна именно фонового стека)

`runDryTest()` дергает `StreakEngine.run(dryRun: true)` в обход координатора (`SettingsView.swift:146`) — `runActive` остаётся false. Обратное окно открыто тоже: кнопка «Продлить сейчас» задизейблена только по `runActive` (`Ugolek/Screens/HomeView.swift:62`), который сухой тест НЕ поднимает.

Реалистичные пересечения:
- Ночной headless/auto прогон идёт (runActive=true), юзер утром заходит в Настройки и щёлкает тумблер — dry-test не проверяет `runActive` вообще и стартует параллельно.
- Dry-test ползёт (до минуты сети), юзер жмёт 🔥 — кнопка активна, `start()` проходит guard.

Два `StreakEngine.run` на синглтоне `InboxRunner.shared`:
- `onLog` перезаписывается, первый финиширующий прогон своим `defer` обнуляет лог второго (`StreakEngine.swift:22-23`);
- единственный слот `resultContinuation` (+`runToken`) — ответы моста достаются не тому ожиданию (`InboxRunner.swift:37,115-133`);
- dryRun-JS активно листает чаты, пока боевой send ждёт пузырь → «Чат не открылся» → шторм перезагрузок `send` (:102-112), вплоть до `clearSiteData`.

Отличие от CORE-01: там вечное зависание на loadContinuation от Диагностики/dry-run; здесь показано, что фоновый стек добавляет ТРЕТИЙ вход (ночные прогоны), с которым гонка возникает без каких-либо действий пользователя.

Тест: `test_BG04_dryTestBypassesRunActive_buttonStaysEnabled_mirror`.

### BG-06 · Drain сторожа убивает ЧУЖИЕ аренды: общий счётчик, вложенные acquire не продлевают защиту (resetWatchdog перезапускает, а не стекует)
**CONFIRMED. Severity: HIGH**

Уровень 2 даёт ДВЕ вложенные аренды на один прогон: интент `acquire()` (`HeadlessStreaksIntent.swift:19-20`) + `startHeadless()` внутри ещё один (`RunCoordinator.swift:61-63`). Интуитивно «двойная страховка» — на деле:

1. Второй `acquire()` зовёт `resetWatchdog()`, который СНАЧАЛА отменяет прежний сторож (`LocationKeeper.swift:75`) — окно защиты не суммируется, это «последний acquire + 900 с».
2. На 900-й секунде drain циклом съедает ОБЩИЙ счётчик до нуля (`LocationKeeper.swift:79`) — уничтожены аренды ВСЕХ владельцев сразу.
3. `stopIfNeeded()` при persistent=false глушит локацию, пока оба кадра (intent defer и startHeadless defer) ещё живут; их будущие `release()` молча no-op'ятся через `guard acquireCount > 0` (:43) — счётчик и `isHolding` навсегда врут относительно реальных держателей.

Сценарий: автоматизация Команд в 10:00, TikTok тормозит, прогон 20 мин → в 10:15 локация погашена из-под живого прогона → процесс заморожен (развитие BG-01 на уровне 2). Отдельно: после drain при живом persistent (уровень 3) scoped-счётчик равен нулю — любой последующий `stopPersistent()` (например, из цепочки BG-14) глушит локацию мгновенно, хотя формально «прогоны ещё держат».

Тест: `test_BG06_nestedAcquires_watchdogRestartsNotStacks_drainKillsAllLeases_mirror`.

### BG-10 · notifyResult рапортует ложь: sentCount==0 → «все огоньки уже горят» даже при failed>0
**CONFIRMED. Severity: HIGH**

`HeadlessStreaksIntent.notifyResult` (`Ugolek/Core/AppIntents/HeadlessStreaksIntent.swift:29-33`): ветка else выбирается по одному условию `sentCount > 0`, текст же утверждает «Нечего продлевать — все огоньки уже горят 🔥». Контрпримеры из реального движка:
- сессия протухла: `StreakEngine` вернул `failedRun("Нужен вход в TikTok")` с одним `.failed` (`StreakEngine.swift:91-97`) → юзер неделями получает «все огоньки горят», хотя ни одно сообщение не ушло и логин умер;
- 10 друзей `.skipped` (чаты не нашлись) при sent=0/failed=0 → тот же «всё горит».

Автоматизация уровня 2 выглядит работающей, стрики тем временем гаснут. Это хуже, чем заявлено в направлении атаки: ломается не только skipped-случай, но и любой полный провал.

Тест: `test_BG10_notifyResultPredicate_zeroSentWithFailures_reportsFalseAllGood`.

---

## MEDIUM

### BG-05 · Жизненный цикл LocationKeeper: любой колбэк авторизации ≠ authorizedAlways мгновенно хоронит уровень 3 (ответ юзера «При использовании приложения» = смерть режима); acquire без разрешения включают фон вслепую
**CONFIRMED (логика) / SUSPECTED (UX на устройстве). Severity: MEDIUM**

`locationManagerDidChangeAuthorization` (`LocationKeeper.swift:86-96`) гасит persistent при ЛЮБОМ статусе != `.authorizedAlways`. Сценарий: юзер включает тумблер, success-ветка уже могла выполнить `startPersistent()` (успех dry-test НЕ требует никакого разрешения — `runDryTest` (`SettingsView.swift:143-148`) не смотрит permissionStatus; оранжевая подсказка :52-55 чисто косметическая), затем в системном диалоге юзер честно выбирает «При использовании приложения» → статус `.authorizedWhenInUse` → persistent=false + post(.geoPermissionRevoked) → наблюдатель (`RunCoordinator.swift:20-28`) выключает флаг. Режим молча умер; апгрейд до Always (штатный двухшаговый flow requestAlwaysAuthorization) становится невозможен — режим уже выключен. Замысел (Risk 2 плана) предполагал подсказку «нажми ещё раз», а не похороны режима.

Суб-находка: `startIfNeeded()` (`LocationKeeper.swift:59-63`) ставит `allowsBackgroundLocationUpdates = true` и стартует апдейты независимо от статуса (notDetermined/denied) — безвредно для рантайма, но вводит в заблуждение и даёт системные ворнинги.

Отбитая података (инициирована направлением 5): делегат-колбэк при INIT с notDetermined НЕ вредит — в этот момент persistent=false, ветка не выполняется.

Тест: `test_BG05_whenInUseStatus_killsPersistentMode_predicate`.

### BG-07 · AutoRunner: Task.sleep на ~24 ч переживает suspension с опозданием в часы; после ребута открытие приложения ПОЗЖЕ целевого времени переносит прогон на ЗАВТРА (сегодня тихо потерян)
**CONFIRMED (частично), частично ОТБИТО. Severity: MEDIUM**

Подтверждено:
- Таймер — голый `Task.sleep` до цели ±джиттер (`AutoRunner.swift:48-54`). Пока процесс спит, тикание стоит; по пробуждению sleep истекает задним числом → `fireAndReschedule` стреляет немедленно: «прогон в выбранное время» на деле = «в момент первого пробуждения процесса» (открыл телефон в 18:00 — прогон в 18:00).
- Ребут: процесс мёртв; оживление только через `UgolekApp.init()` (`UgolekApp.swift:12-15`) при ручном открытии. Если юзер открыл приложение ХОТЬ НА МИНУТУ позже целевого времени (плюс 60-секундный буфер `AutoRunner.swift:43-44`), `target <= now+60` переносит цель на ЗАВТРА — сегодняшний автопрогон тихо пропущен. Compensation из плана (Risk 4: «открыл — режим оживает») в общем случае не выполняется для сегодняшнего дня; страховка — лишь возможно-сработавший CatchUp-уведомление (`CatchUpTask.swift:37`).

ОТБИТАЯ података (направление 7, «двойной прогон при быстрой смене времени дважды»): невозможно. `fireAndReschedule` и `scheduleNext` синхронны на MainActor, между guards и `RunCoordinator.start()` нет ни одного await (`AutoRunner.swift:58-66`); reschedule из DatePicker физически не может вклиниться между guard и стартом, повторный вызов scheduleNext лишь пересчитывает джиттер (last-writer-wins). Плюс `start()` имеет свой guard `runActive` (`RunCoordinator.swift:32`).

Тест: `test_BG07_rebootOpenAfterTarget_pushesRunToTomorrow_mirror`.

### BG-08 · Ночной авто-прогон идёт через UI-вариант start(): isIdleTimerDisabled держит экран юзера среди ночи, а «Готово»-алерт выскакивает при следующем открытии — вопреки собственному футеру настроек
**CONFIRMED (логика) / SUSPECTED (сила эффекта). Severity: MEDIUM**

`fireAndReschedule` вызывает именно `RunCoordinator.start()` (`AutoRunner.swift:64`), а не `startHeadless()`:
1. `UIApplication.shared.isIdleTimerDisabled = true` (`RunCoordinator.swift:37`), снимается только в completion-Task (:46). Автопрогон в 03:00 + юзер взял телефон → экран не заблокируется, пока не закончится невидимая ему рассылка.
2. `showSummary = !record.results.isEmpty` (`RunCoordinator.swift:50`) → при следующем открытии `.alert("Готово", isPresented: $coordinator.showSummary)` (`HomeView.swift:99-110`) сообщает про прогон, которого юзер не запускал. Футер секции обещает ровно обратное: «сам продлевает … не открываясь и не спрашивая» (`SettingsView.swift:60`); план (§3.2) сам же прописал `start()` — расхождение замысел↔поведение не замечено.
3. Попутно мутируются progressText/Done/Total (:41-44): открывший приложение юзер получает fullScreenCover оверлей «Продлеваю огоньки… Не переключайся из приложения» (`HomeView.swift:92-98,211`) посреди чужого ночного прогона.

ОТБИТАЯ података (направление 8, «утечёт ли флаг, если процесс умрёт между строками»): нет — смерть процесса сбрасывает весь стейт; внутрипроцессная утечка потребовала бы вечного зависания StreakEngine.run, но все continuation имеют таймауты (40 с `InboxRunner.swift:52-57`, 95 с :121-131).

Тест: `test_BG08_autoRunUsesUiStart_summaryAlertPredicate_mirror`.

### BG-09 · HeadlessStreaksIntent молчит во всех guard'ах: автоматизация юзера неделями выглядит работающей, ничего не делая
**CONFIRMED. Severity: MEDIUM**

`perform()` при отсутствии логина / пустом friendsDueToday / занятом runActive делает `return .result()` БЕЗ какого-либо уведомления (`HeadlessStreaksIntent.swift:14-18`). Инструкция в настройках прямо советует отключить «Спрашивать до запуска» (`SettingsView.swift:78`) — то есть система не спросит юзера ни о чём. Типовой дрейф: sessionID в Keychain пуст после logout/переустановки → каждый ночной запуск тихо no-op. Диалог/уведомление вместо тишины напрашивалось; замысел (план §1 уровень 2: «итог — уведомлением») нарушен для всех guard-выходов.

Тест: `test_BG09_silentGuards_noNotification_mirror`.

### BG-12 · Воскрешение режима после ребута зависит от читаемости settings.json: битый файл → geoAlwaysAuto молча=false навсегда
**CONFIRMED. Severity: MEDIUM** (угол CORE-03, специфичный для фонового стека)

`UgolekApp.init()` первым делом материализует `AppStore.shared` и читает флаг (`UgolekApp.swift:12`); `loadAll` глушит любую ошибку декода через `try?` (`Store/AppStore.swift:119-120`) → дефолты, `geoAlwaysAuto=false`. Единственный механизм оживления уровня 3 после ребута (план Risk 4) в этом случае никогда не сработает, а следующий persist перезапишет файл дефолтами — потеря навсегда и без следа. Бонус-замечание: синхронный файловый I/O в App.init — мелочь, но на холодном старте.

Тест: `test_BG12_corruptSettingsJson_geoModeLostAfterReboot`.

### BG-14 · Цепочка geoPermissionRevoked полностью беззвучна для юзера: режим умер — никто не узнает
**CONFIRMED. Severity: MEDIUM**

iOS забрал/понизил разрешение → `locationManagerDidChangeAuthorization` постит `.geoPermissionRevoked` (`LocationKeeper.swift:90-94`) → наблюдатель тихо делает flag=false + disarm + stopPersistent (`RunCoordinator.swift:24-26`). postNotice/UNNotification в этой цепочке НЕТ (postNotice существует только в SettingsView:150-161). Юзер узнаёт лишь случайно: флажок в настройках снят, оранжевая подсказка скрыта вместе со всей секцией (`if store.settings.geoAlwaysAuto`, `SettingsView.swift:48`). Итог — юзер уверен, что автопилот включён, огоньки гаснут. Проверка №4 из HANDOFF.md:113 («тумблер сам отщёлкнулся») предполагает, что юзер именно смотрит на тумблер в этот момент.

Тест: покрыт исходником-инспекцией в доке; runtime-скетч `test_BG14_revokedChain_isSilent_sourceScan` (сканирует текст RunCoordinator.swift на отсутствие уведомлений).

### BG-15 · ReminderService и AutoRunner кидают ДВА независимых джиттера ±15: напоминание «Пора продлить!» приходит после того, как авто-прогон уже всё разослал
**CONFIRMED. Severity: LOW**

`ReminderService.scheduleDaily` и `AutoRunner.scheduleNext` независимо бросают кубик ±15 мин (`Core/Planner/ReminderService.swift:40-47` и `Background/AutoRunner.swift:35-42`) → разброс между уведомлением и авто-прогоном до 30 минут в обе стороны. `refreshAfterRun` чистит снузы, но НЕ трогает ежедневное напоминание (`ReminderService.swift:91-98`) → после успешного ночного автопрогона юзер получает «Пора продлить огоньки — тапни!»; тап ставит `pendingAutoRun` (:126), который благополучно отсамоуничтожается в guard'е (`RunCoordinator.swift:78`). Противоречит собственному футеру «Напоминание остаётся запасным вариантом» (`SettingsView.swift:84`).

Тест: `test_BG15_independentJitters_reminderCanFireAfterAutoRun_window`.

---

## ОТБИТЫЕ АТАКИ (полностью)

### BG-03 · Повторный onChange(false) от программной записи флага — безвредно
**ОТБИТ.** Провал dry-test пишет `store.settings.geoAlwaysAuto = false` (`SettingsView.swift:131`) → SwiftUI действительно перестреливает `onChange` → `handleGeoToggle(false)` → `disarm()` (cancel nil-таймера, `AutoRunner.swift:19-21`) + `stopPersistent()` (guard `!isHolding`, `LocationKeeper.swift:66`) — идемпотентные no-op'ы. postNotice НЕ дублируется (один вызов в ветке провала). Реальная побочка одна — и она описана отдельно как BG-02 сценарий B (устаревшая задача перетирает свежее решение юзера), а не как рекурсия/двойное уведомление.

### BG-11 · Невыполненный токен NotificationCenter — утечки/двойного вызова нет
**ОТБИТ.** `addObserver(forName:)` без сохранения токена (`RunCoordinator.swift:20-28`) — да, антипаттерн, но `RunCoordinator.shared` — синглтон, живущий век: блок живёт ровно столько же, вызывается ровно один раз на пост, утечки роста нет. Обработчик идемпотентен (повторная запись false в уже-false флаг триггерит безвредный handleGeoToggle(false), см. BG-03). Единственный шум — лишний persist settings при каждом холостом срабатывании.

### Података направления 5: делегат-колбэк при INIT (notDetermined) — см. BG-05. Података 7 (двойной прогон) — см. BG-07. Података 8 (утечка isIdleTimerDisabled при смерти процесса) — см. BG-08.

---

## Сводка

| ID | Severity | Статус | Суть | Якорь |
|----|----------|--------|------|-------|
| BG-01 | CRITICAL | CONFIRMED | Watchdog 900 с глушит легальный медленный прогон | LocationKeeper.swift:74-81 |
| BG-13 | CRITICAL | CONFIRMED/SUSPECTED | Нет NSLocationWhenInUseUsageDescription → крэш на requestAlways | project.yml:39-40 |
| BG-02 | HIGH | CONFIRMED | Устаревший dry-test Task перезаряжает persistent/arm поверх OFF | SettingsView.swift:124-136 |
| BG-04 | HIGH | CONFIRMED | runDryTest минуя runActive: два движка на одном InboxRunner | SettingsView.swift:146 |
| BG-06 | HIGH | CONFIRMED | Drain сторожа ест чужие аренды; watchdog не стекуется | LocationKeeper.swift:75,79 |
| BG-10 | HIGH | CONFIRMED | «Все огоньки горят» при failed>0/skipped>0 | HeadlessStreaksIntent.swift:29-33 |
| BG-05 | MEDIUM | CONFIRMED | WhenInUse-ответ хоронит уровень 3; acquire без разрешения | LocationKeeper.swift:86-96 |
| BG-07 | MEDIUM | CONFIRMED (част.) | 24h Task.sleep: поздние выстрелы; ребут+позднее открытие = пропуск дня | AutoRunner.swift:43-54 |
| BG-08 | MEDIUM | CONFIRMED | Ночной прогон через UI start(): idle-timer ночью + внезапный алерт | AutoRunner.swift:64 |
| BG-09 | MEDIUM | CONFIRMED | Молчаливые guard'ы headless-интента | HeadlessStreaksIntent.swift:14-18 |
| BG-12 | MEDIUM | CONFIRMED | Ребут-воскрешение зависит от читаемости settings.json | UgolekApp.swift:12 |
| BG-14 | MEDIUM | CONFIRMED | Отзыв разрешения гасит режим беззвучно | RunCoordinator.swift:24-26 |
| BG-15 | LOW | CONFIRMED | Два независимых джиттера: напоминание после автопрогона | ReminderService.swift:91-98 |
| BG-03 | — | ОТБИТ | Повторный onChange(false) идемпотентен | SettingsView.swift:131 |
| BG-11 | — | ОТБИТ | Токен NC у синглтона — не утечка | RunCoordinator.swift:20-28 |

**13 находок: 2 CRITICAL, 4 HIGH, 6 MEDIUM (включая BG-14/BG-15), 1 LOW. 5 атак отбито** (BG-03, BG-11, init-callback-notDetermined, double-run-on-reschedule, idle-timer-leak-on-death).
