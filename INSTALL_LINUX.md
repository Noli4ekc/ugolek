# Установка Уголька с Linux (Fedora)

Доступно **два способа** установки IPA на Linux — бесплатный и платный. Выбирай под свои задачи.

---

## Сравнение способов

| | 🟢 Бесплатный (AltServer) | 🟡 Платный (Apple Developer) |
|---|---|---|
| **Стоимость** | $0 | $99/год |
| **Срок подписи** | 7 дней (продлевать еженедельно) | 1 год |
| **Сложность** | Просто — 2 команды | Сложно — ручная работа с сертификатами |
| **Лимит приложений** | 3 одновременно | Без ограничений |
| **Автопродление** | Да (если ПК включён) | Нет (сертификат живёт год) |
| **Требования** | Docker | Платный Apple Developer |
| **Надёжность** | Зависит от anisette-сервера | Полностью автономно |

---

## 🟢 Способ 1: Бесплатный (AltServer + бесплатный Apple ID)

> Использует тот же механизм, что AltStore на Windows/macOS. Подпись на 7 дней с автоматическим продлением.

### Быстрый старт (2 команды)

```bash
# 1. Скачай скрипт
wget -O ~/ugolek-install.sh https://raw.githubusercontent.com/Noli4ekc/ugolek/main/ugolek-install.sh

# 2. Запусти и выбери способ 1
bash ~/ugolek-install.sh
```

Скрипт сам:
1. Установит Docker (если нет) и запустит **anisette-v3-server** (эмулирует Mac для Apple)
2. Скачает **AltServer-Linux**
3. Скачает IPA, подпишет через твой бесплатный Apple ID и установит на iPhone

### Требования

- Fedora 44 (x86_64)
- iPhone с iOS 17+, подключённый по USB
- Бесплатный Apple ID
- Docker (скрипт установит если нет)

### Процесс при первом запуске

```
1. Выбери способ: 1 (бесплатно)
2. Подключи iPhone по USB
3. Введи email и пароль от Apple ID
4. Когда попросит 2FA — введи код с iPhone
5. Готово! Приложение на рабочем столе
```

### Продление подписи

Подпись живёт **7 дней**. Чтобы продлить:
- Перезапусти скрипт: `bash ~/ugolek-install.sh`
- Или поставь напоминание раз в неделю

> Важно: anisette-сервер должен быть запущен (скрипт сам проверяет и запускает).

---

## 🟡 Способ 2: Платный (Apple Developer Program, $99/год)

> Полноценная разработческая подпись на 1 год. Требует ручной работы с сертификатами.

### Быстрый старт

```bash
# 1. Скачай скрипт
wget -O ~/ugolek-install.sh https://raw.githubusercontent.com/Noli4ekc/ugolek/main/ugolek-install.sh

# 2. Запусти и выбери способ 2
bash ~/ugolek-install.sh
```

### Требования

- Fedora 44 (x86_64)
- iPhone с iOS 17+, подключённый по USB
- **Apple Developer Program ($99/год)** — бесплатный Apple ID не позволяет создавать сертификаты
- Доступ в браузере к https://developer.apple.com

### Что делает скрипт

| Этап | Автоматически | Твоё участие |
|------|--------------|--------------|
| Установка зависимостей | ✅ | Только пароль sudo |
| Сборка zsign (подпись IPA) | ✅ | — |
| Установка pymobiledevice3 | ✅ | — |
| Генерация ключа и CSR | ✅ | Ввести email Apple ID |
| Получение Apple-сертификата | ❌ | Браузер: developer.apple.com |
| Регистрация UDID iPhone | ❌ | Браузер: добавить в Devices |
| Provisioning profile | ❌ | Браузер: создать profile |
| Подпись и установка | ✅ | Ввести пароль от сертификата |

### Подробное описание ручных шагов

#### Получение Apple-сертификата

Когда скрипт дойдёт до этого шага, он сгенерирует CSR и попросит тебя:

1. Открой https://developer.apple.com/account/ и войди в Apple ID
2. **Certificates** → **+** → **iOS App Development** → Continue
3. Загрузи CSR (путь покажет скрипт) → Continue → Download
4. Скачанный .cer положи в `~/ugolek-sign/`

#### Регистрация UDID iPhone

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

---

## Обновление при новом релизе

Просто запусти скрипт заново:

```bash
bash ~/ugolek-install.sh
```

Он поймёт что зависимости уже стоят и продолжит с того места, где остановился.

---

## Устранение проблем

### Бесплатный способ (AltServer)

| Симптом | Решение |
|---------|---------|
| `anisette-сервер не запускается` | `docker ps -a`, `docker logs anisette` — проверь логи |
| Ошибка `-36607` | Неверные anisette-данные, перезапусти anisette: `docker restart anisette` |
| `AltServer не видит iPhone` | `sudo systemctl restart usbmuxd`, разблокируй iPhone |
| 2FA не приходит | Настройки iPhone → Пароль → Получить код вручную |
| Подпись истекла (7 дней) | Перезапусти скрипт |

### Платный способ (zsign)

| Симптом | Решение |
|---------|---------|
| `externally-managed-environment` | Скрипт использует venv, это не должно произойти |
| `idevice_id: command not found` | Перезапусти скрипт; если повторится — `sudo dnf install libimobiledevice-utils` |
| `Unable to retrieve device list!` | `sudo systemctl restart usbmuxd`, разблокируй iPhone |
| `Device is not paired` | Разблокируй iPhone, нажми «Доверять» |
| `ApplicationVerificationFailed` | Истёк сертификат — переподпиши; проверь что provisioning profile включает твой UDID |
| `zsign: command not found` | `sudo cp /tmp/zsign/bin/zsign /usr/local/bin/`, потом `hash -r` |

---

## Как удалить

```bash
# Бесплатный способ
docker stop anisette && docker rm anisette
rm -rf ~/ugolek-tools ~/Ugolek

# Платный способ
rm -rf ~/ugolek-sign ~/ugolek-venv ~/Ugolek
```
