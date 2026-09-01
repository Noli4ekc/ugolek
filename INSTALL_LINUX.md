# Установка Уголька с Linux (Fedora)

## Быстрый старт (2 команды)

```bash
# 1. Скачай скрипт
wget -O ~/ugolek-install.sh https://raw.githubusercontent.com/Noli4ekc/ugolek/main/ugolek-install.sh

# 2. Запусти
bash ~/ugolek-install.sh
```

Скрипт сам сделает всё остальное: установит зависимости, соберёт инструменты для подписи, проведёт через получение Apple-сертификата, подпишет IPA и поставит на iPhone.

> ⚠️ В процессе скрипт попросит пароль суперпользователя (для `sudo`) и пароль от сертификата (придумай сам, запомни его).

---

## Что делает скрипт

| Этап | Автоматически | Твоё участие |
|------|--------------|--------------|
| Установка зависимостей (git, gcc, openssl, python3-devel, wget, usbmuxd, libimobiledevice-utils) | ✅ | Только пароль sudo |
| Сборка zsign (подпись IPA) | ✅ | — |
| Установка pymobiledevice3 в venv | ✅ | — |
| Запуск usbmuxd | ✅ | — |
| Генерация ключа и CSR | ✅ | Ввести email Apple ID |
| Получение Apple-сертификата | ❌ | Браузер: зайти на developer.apple.com, загрузить CSR, скачать .cer |
| Сборка .p12 | ✅ | Придумать пароль |
| Регистрация UDID iPhone | ❌ | Браузер: добавить UDID в Devices |
| Provisioning profile | ❌ | Браузер: создать profile, скачать |
| Lockdown pair | ✅ | Разблокировать iPhone, нажать «Доверять» |
| Скачивание IPA | ✅ | — |
| Подпись IPA | ✅ | Ввести пароль от сертификата |
| Установка на iPhone | ✅ | — |

---

## Требования

- Fedora 44 (x86_64)
- iPhone с iOS 17+, подключённый по USB
- Apple ID (бесплатный подходит)
- Доступ в браузере к https://developer.apple.com

---

## Подробное описание шагов с ручным вмешательством

### Получение Apple-сертификата

Когда скрипт дойдёт до этого шага, он сгенерирует CSR и попросит тебя:

1. Открой https://developer.apple.com/account/ и войди в Apple ID
2. **Certificates** → **+** → **iOS App Development** → Continue
3. Загрузи CSR (путь покажет скрипт) → Continue → Download
4. Скачанный .cer положи в `~/ugolek-sign/` (или в `~/Downloads/` — скрипт найдёт)

### Регистрация UDID iPhone

Скрипт выведет UDID твоего iPhone. Запомни его или скопируй.

1. developer.apple.com → **Devices** → **+** → введи UDID и имя
2. **Identifiers** → **+** → **App IDs** → **App**:
   - Description: Ugolek
   - Bundle ID: Explicit → `com.ugolek.app`
3. **Profiles** → **+** → **iOS App Development**:
   - App ID: Ugolek (com.ugolek.app)
   - Certificates: выбери созданный
   - Devices: выбери свой iPhone
4. Download → сохрани как `~/ugolek-sign/profile.mobileprovision`

### Lockdown pair

Когда скрипт попросит — разблокируй iPhone и нажми «Доверять» при появлении диалога.

---

## Обновление при новом релизе

Просто запусти скрипт заново:

```bash
bash ~/ugolek-install.sh
```

Он поймёт что зависимости уже стоят и продолжит с того места, где остановился.

---

## Устранение проблем

| Симптом | Решение |
|---------|---------|
| `externally-managed-environment` | Скрипт использует venv, это не должно произойти |
| `idevice_id: command not found` | Перезапусти скрипт; если повторится — `sudo dnf install libimobiledevice-utils` |
| `Unable to retrieve device list!` | `sudo systemctl restart usbmuxd`, разблокируй iPhone |
| `Device is not paired` | Разблокируй iPhone, нажми «Доверять» |
| `ApplicationVerificationFailed` | Истёк сертификат (7 дней) — переподпиши; проверь что provisioning profile включает твой UDID |
| `zsign: command not found` | `sudo cp /tmp/zsign/bin/zsign /usr/local/bin/`, потом `hash -r` |
| Скрипт упал на сертификате | Удали `~/ugolek-sign/` и перезапусти скрипт |

---

## Ограничения бесплатного Apple ID

- **7 дней** — сертификат протухает, пере-подписывай еженедельно
- **3 приложения** — лимит одновременно установленных
- Платный Apple Developer ($99/год) убирает оба ограничения

---

## Как удалить

```bash
rm -rf ~/ugolek-sign ~/ugolek-venv ~/Ugolek
```
