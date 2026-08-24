# Архитектурный план: кнопка «Продлить огоньки» в Пункте управления (Control Center)

**Проект:** Уголёк (Ugolek) — iOS-приложение для автоматического продления стриков в TikTok.
**Цель:** добавить нативную кнопку 🔥 в шторку iOS (Control Center), которая запускает прогон рассылки сообщений друзьям.
**Дата составления:** 2026-08-23.
**Статус:** план проверен, готов к реализации.

---

## 1. Проверенные факты (основа плана)

### 1.1. ControlWidget может жить в main app target — Widget Extension НЕ нужен

`ControlWidget` (API iOS 18+, из `AppIntents`/`WidgetKit`) можно объявить прямо в основном target приложения. Не требуется создавать отдельный Widget Extension target (`.appex`). Это **критически важно** для нашего проекта:

- Приложение распространяется как **unsigned IPA** через Sideloadly/AltStore.
- Если бы виджет жил в Widget Extension (`.appex`), Sideloadly должен был бы ре-сигнить **два** bundle (host app + extension). Не все версии Sideloadly делают это корректно — extension может молча не загрузиться.
- С виджетом в main app target Sideloadly подписывает **один** bundle — нет проблем.

**Решение: виджет остаётся в main app target. Widget Extension НЕ создаётся.**

### 1.2. CI runner имеет Xcode 16.4 с iOS 18.5 SDK

GitHub Actions runner `macos-15` имеет установленные Xcode версии (по состоянию на 2026-08):
- 26.3, 26.2, 26.1.1, 26.0.1 — Xcode 26.x с iOS 26 SDK
- **16.4 (default)**, 16.3, 16.2, 16.1, 16.0 — Xcode 16.x с iOS 18.x SDK

`ControlWidget` (iOS 18+) скомпилируется на любом из них. Проблема в текущем CI — флаг `SKIP_CONTROL_WIDGET`, который **исключает** виджет из компиляции. Этот флаг был добавлен, когда на runner'е был Xcode без iOS 18 SDK; сейчас это уже не так.

**Решение: убрать `SKIP_CONTROL_WIDGET` из CI и из `#if` в коде виджета.**

### 1.3. Синтаксис StaticControlConfiguration требует `kind:` параметр

Текущий код вызывает `StaticControlConfiguration(...)` без `kind:` — это **не скомпилируется** на iOS 18 SDK. Правильный синтаксис (подтверждён через Apple Developer Forums и документацию):

```swift
StaticControlConfiguration(kind: Self.kind) {
    ControlWidgetButton(action: MaintainStreaksIntent()) {
        Label("Продлить", systemImage: "flame.fill")
    }
}
```

`kind` — строковый идентификатор виджета (например `"com.ugolek.streak-button"`), используется системой для отслеживания состояния кнопки.

### 1.4. Bundle ID несоответствие — нужно исправить

XcodeGen с `bundleIdPrefix: com.ugolek` и без явного `PRODUCT_BUNDLE_IDENTIFIER` авто-генерирует bundle ID как `com.ugolek.Ugolek` (правило: `bundleIdPrefix.<TargetName>`).

Но код проекта ожидает `com.ugolek.app`:
- `KeychainStore.swift`: service = `"com.ugolek.app"`
- `CatchUpTask.swift`: identifier = `"com.ugolek.app.catchup"`
- `altstore-source.json`: `"bundleIdentifier": "com.ugolek.app"`

Это несоответствие могло работать, потому что Keychain service и BGTask identifier — это строки, а не bundle ID (iOS не связывает их автоматически). Но для Control Center виджету нужен корректный bundle ID — система использует его для регистрации виджета.

**Решение: добавить `PRODUCT_BUNDLE_IDENTIFIER: com.ugolek.app` в `project.yml` settings.base.**

### 1.5. MaintainStreaksIntent — правильный хук

Текущий `MaintainStreaksIntent` (в `Ugolek/Core/AppIntents/MaintainStreaksIntent.swift`):

```swift
struct MaintainStreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Продлить огоньки"
    static var description = IntentDescription("...")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        RunCoordinator.shared.start()
        return .result()
    }
}
```

`openAppWhenRun = true` — правильно. Виджет в Control Center тапает кнопку → система вызывает `MaintainStreaksIntent.perform()` → открывается приложение → `RunCoordinator.shared.start()` запускает прогон в host-процессе (где есть `UIWindowScene` для `InboxRunner`).

Extension процесс (если бы виджет был в extension) не имеет доступа к `UIApplication.connectedScenes` и не может создать `UIWindow` — но мы виджет в main app target, поэтому `perform()` выполняется в процессе приложения.

---

## 2. Что нужно изменить — точный код для каждого файла

### 2.1. `Ugolek/Core/AppIntents/UgolekControlWidget.swift`

**Текущий код (сломанный):**
```swift
import AppIntents
#if !SKIP_CONTROL_WIDGET
import WidgetKit

@available(iOS 18.0, *)
struct UgolekControlWidget: ControlWidget {
    static let kind = "com.ugolek.streak-button"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            ControlWidgetButton(action: MaintainStreaksIntent()) {
                Label("Продлить", systemImage: "flame.fill")
            }
        )
        .displayName("Продлить огоньки")
        .description("Запустить рассылку сообщений друзьям в TikTok")
    }
}
#endif
```

**Проблемы:**
1. `#if !SKIP_CONTROL_WIDGET` — пропускает весь код виджета на CI (флаг установлен в xcodebuild команды).
2. `StaticControlConfiguration(...)` без `kind:` — не скомпилируется на iOS 18 SDK.

**Новый код:**
```swift
import AppIntents
import WidgetKit

@available(iOS 18.0, *)
struct UgolekControlWidget: ControlWidget {
    static let kind = "com.ugolek.streak-button"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MaintainStreaksIntent()) {
                Label("Продлить", systemImage: "flame.fill")
            }
        }
        .displayName("Продлить огоньки")
        .description("Запустить рассылку сообщений друзьям в TikTok")
    }
}
```

**Изменения:**
- Убран `#if !SKIP_CONTROL_WIDGET` / `#endif`
- `import WidgetKit` перенесён наверх (без условия)
- Добавлен `kind: Self.kind` в `StaticControlConfiguration`
- `ControlWidgetButton` теперь внутри trailing closure `StaticControlConfiguration(kind:) { ... }`

### 2.2. `project.yml`

**Текущие settings.base:**
```yaml
settings:
  base:
    SWIFT_VERSION: "5.9"
    TARGETED_DEVICE_FAMILY: "1"
    ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

**Новые settings.base:**
```yaml
settings:
  base:
    SWIFT_VERSION: "5.9"
    TARGETED_DEVICE_FAMILY: "1"
    ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    PRODUCT_BUNDLE_IDENTIFIER: com.ugolek.app
```

**Изменение:** добавлена одна строка `PRODUCT_BUNDLE_IDENTIFIER: com.ugolek.app`.

Больше в `project.yml` ничего не меняется — виджет остаётся в main app target, sources уже включают `Ugolek/` рекурсивно (файл `Ugolek/Core/AppIntents/UgolekControlWidget.swift` уже в дереве источников).

### 2.3. `.github/workflows/build.yml`

**Текущее состояние (закоммиченный HEAD):**
- Ручной `xcode-select` через `ls -d /Applications/Xcode*.app | sort -V | tail -1`
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS="SKIP_CONTROL_WIDGET"` в compile-check и ipa job

**Нужно:**

1. В обоих macos job'ах (`compile-check` и `ipa`) заменить ручной `xcode-select` на:
```yaml
      - name: Select latest Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: 'latest-stable'
```

2. В обоих macos job'ах убрать `SWIFT_ACTIVE_COMPILATION_CONDITIONS="SKIP_CONTROL_WIDGET"` из xcodebuild команд.

3. Добавить шаг диагностики после выбора Xcode:
```yaml
      - name: Show Xcode and SDK info
        run: |
          xcodebuild -version
          xcodebuild -showsdks | grep -i ios
```

**Полный файл `build.yml`** (готовый к использованию):

```yaml
name: build

on:
  push:
  workflow_dispatch:

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  compile-check:
    name: Compile check (simulator, debug)
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select latest Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: 'latest-stable'

      - name: Show Xcode and SDK info
        run: |
          xcodebuild -version
          xcodebuild -showsdks | grep -i ios

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build for iOS Simulator
        id: build
        run: |
          set -o pipefail
          xcodebuild -project Ugolek.xcodeproj \
            -scheme Ugolek \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug \
            -derivedDataPath dd \
            CODE_SIGNING_ALLOWED=NO \
            build -quiet 2>&1 | tee buildlog.txt

      - name: Annotate compile errors
        if: failure()
        run: |
          grep -E "error:" buildlog.txt | head -40 | sed 's/^/::error::/' || true

      - name: Zip simulator .app (for Appetize.io)
        run: |
          cd dd/Build/Products/Debug-iphonesimulator
          zip -qry "${GITHUB_WORKSPACE}/Ugolek-simulator.zip" Ugolek.app

      - name: Upload simulator zip
        uses: actions/upload-artifact@v4
        with:
          name: Ugolek-simulator
          path: Ugolek-simulator.zip
          retention-days: 30

  ipa:
    name: Unsigned IPA (for AltStore)
    runs-on: macos-15
    needs: compile-check
    steps:
      - uses: actions/checkout@v4

      - name: Select latest Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: 'latest-stable'

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Archive (device, release, unsigned)
        run: >
          xcodebuild -project Ugolek.xcodeproj
          -scheme Ugolek
          -destination 'generic/platform=iOS'
          -configuration Release
          -archivePath build/Ugolek.xcarchive
          CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
          archive -quiet

      - name: Pack unsigned IPA
        run: |
          mkdir Payload
          cp -R "build/Ugolek.xcarchive/Products/Applications/Ugolek.app" Payload/
          zip -qry Ugolek-unsigned.ipa Payload
          ls -lh Ugolek-unsigned.ipa

      - name: Upload IPA
        uses: actions/upload-artifact@v4
        with:
          name: Ugolek-unsigned-ipa
          path: Ugolek-unsigned.ipa
          retention-days: 30

  rolling-release:
    name: Attach IPA to rolling release
    runs-on: ubuntu-latest
    needs: ipa
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: write
    steps:
      - name: Download IPA artifact
        uses: actions/download-artifact@v4
        with:
          name: Ugolek-unsigned-ipa

      - name: Publish to rolling release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release view rolling --repo "$GITHUB_REPOSITORY" || \
            gh release create rolling --repo "$GITHUB_REPOSITORY" \
              --title "Свежая сборка (rolling)" \
              --notes "Последняя сборка из ветки main. IPA — для установки через Sideloadly/AltStore."
          gh release upload rolling Ugolek-unsigned.ipa --clobber --repo "$GITHUB_REPOSITORY"
```

---

## 3. Порядок выполнения (для другой сессии)

### Шаг 1: Исправить код виджета
- Файл: `Ugolek/Core/AppIntents/UgolekControlWidget.swift`
- Убрать `#if !SKIP_CONTROL_WIDGET` / `#endif`
- Добавить `kind: Self.kind` в `StaticControlConfiguration`
- Использовать точный код из раздела 2.1 выше

### Шаг 2: Исправить bundle ID
- Файл: `project.yml`
- Добавить `PRODUCT_BUNDLE_IDENTIFIER: com.ugolek.app` в `settings.base`
- Использовать точный код из раздела 2.2 выше

### Шаг 3: Исправить CI
- Файл: `.github/workflows/build.yml`
- Заменить на полный файл из раздела 2.3 выше
- Ключевые изменения: `setup-xcode@v1` вместо ручного `xcode-select`, убрать `SKIP_CONTROL_WIDGET`

### Шаг 4: Коммит и push
```bash
git add Ugolek/Core/AppIntents/UgolekControlWidget.swift project.yml .github/workflows/build.yml
git commit -m "fix: enable ControlWidget with correct kind: syntax, fix bundle ID, update CI Xcode"
git push
```

### Шаг 5: Ждать CI (~3-4 мин)
```bash
# проверить статус
curl -s --http1.1 "https://api.github.com/repos/Noli4ekc/ugolek/actions/runs?per_page=1" | \
  python -c "import json,sys; d=json.load(sys.stdin); r=d['workflow_runs'][0]; print(r['head_sha'][:7], r['status'], r.get('conclusion'))"
```

### Шаг 6: Если CI зелёный
```bash
# скачать свежий IPA
curl -sL --http1.1 -o /d/sideload-tools/Ugolek-unsigned.ipa \
  "https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa"
ls -la /d/sideload-tools/Ugolek-unsigned.ipa
```

### Шаг 7: Если CI красный
```bash
# получить аннотации ошибок (видны без логина в GitHub)
CR=$(curl -s --http1.1 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Noli4ekc/ugolek/commits/<SHA>/check-runs" | \
  python -c "
import json, sys
d = json.load(sys.stdin)
for c in d.get('check_runs', []):
    if c['name'].startswith('Compile') and c['conclusion'] == 'failure':
        print(c['id'])
")
curl -s --http1.1 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Noli4ekc/ugolek/check-runs/$CR/annotations" | \
  python -c "
import json, sys
d = json.load(sys.stdin)
for a in d:
    if a.get('annotation_level') == 'failure' and 'exit code' not in str(a.get('message','')):
        print(a.get('path'), a.get('start_line'), a.get('message','')[:200])
"
```

Возможные ошибки и решения:
- **"cannot find type 'ControlWidget' in scope"** — Xcode не имеет iOS 18 SDK. Проверить `xcodebuild -showsdks`. Если SDK нет — вернуть `#if canImport(WidgetKit)` (но не `SKIP_CONTROL_WIDGET`).
- **"missing argument for parameter 'kind'"** — синтаксис `StaticControlConfiguration` требует `kind:`. Проверить, что код точно как в разделе 2.1.
- **Bundle ID конфликт** — если `PRODUCT_BUNDLE_IDENTIFIER` уже установлен где-то ещё, XcodeGen может ругаться. Проверить `project.yml` на дубликаты.

---

## 4. Риски и компенсации

### Риск 1: `StaticControlConfiguration(kind:)` синтаксис может отличаться на Xcode 26
**Вероятность:** низкая. API стабилен с iOS 18.
**Компенсация:** аннотации CI покажут точную ошибку. Если `kind:` не нужен на Xcode 26 — убрать параметр.

### Риск 2: Bundle ID изменение создаёт "новое" приложение
**Описание:** при смене `com.ugolek.Ugolek` → `com.ugolek.app` на уже установленном приложении iOS считает это новым приложением. Старое нужно удалить перед установкой нового.
**Вероятность:** средняя (пользователь уже установил IPA с авто-генерированным ID).
**Компенсация:** предупредить пользователя: "Удали старый Уголёк перед установкой нового IPA". Куки TikTok хранятся в Keychain — при удалении приложения они сотрутся, нужен повторный вход в TikTok.

### Риск 3: Sideloadly ре-сигнинг
**Описание:** поскольку виджет в main app target (не в `.appex`), Sideloadly подписывает один bundle. Нет проблем с ре-сигнингом extension.
**Вероятность:** низкая.
**Компенсация:** нет нужна — это преимущество подхода "виджет в main app target".

### Риск 4: `openAppWhenRun = true` открывает приложение
**Описание:** тап по кнопке в шторке открывает приложение (не работает "молча" в фоне). Это правильно: `InboxRunner` требует `UIWindowScene` из host-процесса.
**Вероятность:** это не риск, это правильное поведение.
**Компенсация:** нет нужна. Приложение откроется, прогон пройдёт, пользователь увидит прогресс-оверлей.

---

## 5. Инструкция для пользователя (после установки IPA с виджетом)

### Как добавить кнопку 🔥 в шторку

1. **Открой шторку** (смахни вниз справа сверху экрана)
2. **Зажми пустое место** в шторке → нажми **«+»** (или «Добавить управляющий элемент» внизу)
3. **Найди «Уголёк»** в списке приложений → выбери **«Продлить огоньки»**
4. Кнопка 🔥 появится в шторке

### Как использовать

- **Тап по кнопке 🔥** в шторке → открывается Уголёк → запускается прогон рассылки
- Прогон идёт как обычно: открывается скрытый WebView, находятся чаты, отправляются сообщения
- Результат видно в приложении (алерт «Готово») и в вкладке «История»

### Альтернатива: Shortcuts-тайл (работает уже сейчас, без виджета)

Если нативная кнопка ещё не установлена, можно использовать Shortcuts:

1. Открой шторку → зажми → «+»
2. Выбери **Shortcuts**
3. Выбери **«Продлить огоньки»** (из приложения Уголёк)
4. Тайл Команд появится в шторке — тап запускает прогон

Shortcuts-тайл выглядит как стандартная кнопка Команд (без кастомной иконки 🔥). Нативная кнопка виджета выглядит как кнопка приложения с иконкой пламени.

---

## 6. Архитектурная схема

```
Пользователь тапает 🔥 в Control Center
         │
         ▼
ControlWidgetButton (в main app target)
         │
         ▼
MaintainStreaksIntent.perform()
  (openAppWhenRun = true → открывает приложение)
         │
         ▼
RunCoordinator.shared.start()
  (@MainActor, в host-процессе приложения)
         │
         ▼
StreakEngine.run()
  (перебирает друзей, вызывает InboxRunner)
         │
         ▼
InboxRunner.shared.send()
  (создаёт скрытый WKWebView 1920×1080,
   makeKey() + becomeFirstResponder(),
   инжектит send.js, находит чат, вводит текст,
   нажимает отправку, подтверждает)
         │
         ▼
RunRecord → AppStore.record()
  (история, статистика, лог)
```

**Ключевое ограничение:** каждый узел в цепочке — `@MainActor` и требует `UIWindowScene` из host-процесса. Extension процесс не может выполнить эту цепочку. Поэтому виджет **обязательно** в main app target, а `openAppWhenRun = true` — обязательно.

---

## 7. Файлы проекта (справка для другой сессии)

| Файл | Назначение |
|------|-----------|
| `Ugolek/Core/AppIntents/UgolekControlWidget.swift` | Виджет кнопки (исправить) |
| `Ugolek/Core/AppIntents/MaintainStreaksIntent.swift` | AppIntent + AppShortcuts (не менять) |
| `Ugolek/UgolekApp.swift` | Точка входа `@main` (не менять) |
| `Ugolek/Core/Planner/RunCoordinator.swift` | Координатор прогона (не менять) |
| `Ugolek/Core/Planner/StreakEngine.swift` | Движок рассылки (не менять) |
| `Ugolek/Core/InboxEngine/InboxRunner.swift` | WebView автоматизация (не менять) |
| `project.yml` | XcodeGen конфиг (добавить PRODUCT_BUNDLE_IDENTIFIER) |
| `.github/workflows/build.yml` | CI (заменить на версию с setup-xcode) |
| `Resources/send.js` | JS автоматизация TikTok (не менять) |
| `HANDOFF.md` | Паспорт проекта (обновить после реализации) |

---

## 8. Среда и доступы

- **GitHub:** `Noli4ekc/ugolek` (публичный). API работает с ПК (иногда с `--http1.1`).
- **CI:** GitHub Actions, runner `macos-15`, Xcode 16.4 (default) или 26.x (latest-stable).
- **Sideloadly:** в `D:\sideload-tools\` на Windows-ПК пользователя.
- **iPhone:** iPhone 13 (Кирилл), iOS 26.1, подключение по USB.
- **CDP-отладка:** `pymobiledevice3 webinspector cdp --port 9222` + Node.js WebSocket (npm `ws` установлен в `D:\Ugolek`).
- **Task Master:** `D:\Ugolek\.taskmaster\tasks\tasks.json`.

---

*План составлен на основе исследования кода проекта, Apple Developer документации, XcodeGen source, и GitHub Actions runner-images readme. Все факты проверены.*
