# Установка Уголька с Linux (Fedora 44)

## Разовая настройка

### 1. Системные зависимости

```bash
sudo dnf install -y git gcc-c++ pkgconf-pkg-config openssl-devel \
  python3-devel python3-pip wget usbmuxd libimobiledevice-utils \
  libimobiledevice ideviceinstaller
```

| Пакет | Зачем |
|-------|-------|
| `pkgconf-pkg-config` | Makefile zsign требует `pkg-config --cflags openssl` |
| `python3-devel` | Без него `pip install pymobiledevice3` падает с `Python.h: No such file or directory` |
| `wget` | Для скачивания IPA (на minimal-установке отсутствует) |
| `usbmuxd` | База для связи с iPhone |
| `libimobiledevice-utils` | **Критично:** содержит `idevice_id` (пакет `libimobiledevice` — только библиотека, без CLI) |
| `libimobiledevice` | Библиотека для связи с iOS |

### 2. Запустить usbmuxd

```bash
sudo systemctl enable --now usbmuxd
```

> ⚠️ Без этого `idevice_id` и `pymobiledevice3` не увидят iPhone. После каждой перезагрузки usbmuxd не автозапускается — `enable` решает.

### 3. Собрать zsign (подпись IPA без Xcode)

```bash
git clone https://github.com/zhlynn/zsign.git /tmp/zsign
cd /tmp/zsign/build/linux
make clean && make
sudo cp /tmp/zsign/bin/zsign /usr/local/bin/
hash -r   # сбросить кэш команд, чтобы `zsign` нашёлся
```

> ✅ Бинарник собирается в `/tmp/zsign/bin/zsign`, НЕ в текущей директории.

### 4. Установить pymobiledevice3

Fedora 44 следует PEP 668 (externally-managed-environment) — `pip install` заблокирован. Используй venv:

```bash
python3 -m venv ~/ugolek-venv
source ~/ugolek-venv/bin/activate
pip install pymobiledevice3
```

> ⚠️ В этом venv работай до конца установки. Для последующих обновлений активируй его: `source ~/ugolek-venv/bin/activate`.

### 5. Узнать UDID iPhone

```bash
idevice_id -l
```

> Если `command not found` — установи `libimobiledevice-utils` (шаг 1). Если `ERROR: Unable to retrieve device list!` — проверь `sudo systemctl status usbmuxd`.

### 6. Apple-сертификат (один раз, живёт 7 дней для бесплатного аккаунта)

```bash
mkdir -p ~/ugolek-sign

openssl req -new -newkey rsa:2048 -nodes \
  -keyout ~/ugolek-sign/developer.key \
  -out ~/ugolek-sign/developer.csr \
  -subj "/emailAddress=mishania.ckop@gmail.com, CN=Ugolek Developer, C=RU"
```

Дальше в браузере:

1. https://developer.apple.com/account/ (войди в Apple ID)
2. **Certificates** → **+** → **iOS App Development** → Continue
3. Загрузи `~/ugolek-sign/developer.csr` → Continue → Download (`ios_development.cer`)
4. Сконвертируй:
   ```bash
   cp ~/Downloads/ios_development.cer ~/ugolek-sign/
   openssl x509 -in ~/ugolek-sign/ios_development.cer -inform DER \
     -out ~/ugolek-sign/developer.pem
   ```
5. Добавь промежуточный сертификат Apple (WWDR CA) — **без него подпись невалидна**:
   ```bash
   curl -sL https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer \
     -o ~/ugolek-sign/wwdr.cer
   openssl x509 -in ~/ugolek-sign/wwdr.cer -inform DER -out ~/ugolek-sign/wwdr.pem
   ```
6. Собери .p12 (с `-legacy` для совместимости с zsign):
   ```bash
   openssl pkcs12 -export -legacy \
     -out ~/ugolek-sign/developer.p12 \
     -inkey ~/ugolek-sign/developer.key \
     -in ~/ugolek-sign/developer.pem \
     -certfile ~/ugolek-sign/wwdr.pem
   ```
   Придумай пароль — он понадобится при подписи IPA.

7. Проверь что ключ и сертификат совпадают:
   ```bash
   openssl x509 -noout -modulus -in ~/ugolek-sign/developer.pem | openssl md5
   openssl rsa  -noout -modulus -in ~/ugolek-sign/developer.key | openssl md5
   ```
   > Два хеша должны быть **идентичны**. Иначе подпись не сработает и ты узнаешь об этом только на iPhone.

### 7. Provisioning profile

1. developer.apple.com → **Devices** → **+** → введи UDID (из шага 5)
2. **Identifiers** → **+** → **App IDs** → **App**:
   - Description: Ugolek
   - Bundle ID: Explicit → `com.ugolek.app`
3. **Profiles** → **+** → **iOS App Development**:
   - App ID: Ugolek (com.ugolek.app)
   - Certificates: выбери созданный
   - Devices: выбери свой iPhone
4. Download → сохрани как `~/ugolek-sign/profile.mobileprovision`

> ✅ **iOS App Development** — правильный тип для бесплатного Apple ID. Ad Hoc не поддерживается бесплатно.

### 8. Lockdown pair (критично!)

Перед первой установкой iPhone должен доверять компьютеру:

```bash
source ~/ugolek-venv/bin/activate
pymobiledevice3 lockdown pair
```

> Разблокируй iPhone и нажми «Доверять» при появлении диалога. Без этого установка всегда падает с `Device is not paired` или `LOCKDOWN_E_INVALID_HOST_ID`.

## Установка и обновление IPA

```bash
mkdir -p ~/Ugolek && cd ~/Ugolek
rm -f Ugolek-unsigned.ipa Ugolek-signed.ipa

# Скачать свежую сборку
wget https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa

# Подпиши (замени ПАРОЛЬ)
zsign -k ~/ugolek-sign/developer.p12 -p ПАРОЛЬ \
  -m ~/ugolek-sign/profile.mobileprovision \
  -o Ugolek-signed.ipa Ugolek-unsigned.ipa

# Установи на iPhone (подключён по USB)
source ~/ugolek-venv/bin/activate
pymobiledevice3 apps install Ugolek-signed.ipa
```

## После установки на iPhone

**На iPhone:** Настройки → Основные → VPN и управление устройством → доверь своему Apple ID.

## Ограничения бесплатного Apple ID

- **7 дней** — сертификат протухает, пере-подписывай еженедельно
- **3 приложения** — лимит одновременно установленных
- Платный Apple Developer ($99/год) убирает оба ограничения

## Устранение проблем

| Симптом | Решение |
|---------|---------|
| `externally-managed-environment` | Используй venv (шаг 4), не `pip install --user` |
| `idevice_id: command not found` | Установи `libimobiledevice-utils` (шаг 1) |
| `pkg-config: No such file` | Установи `pkgconf-pkg-config` (шаг 1) |
| `Python.h: No such file` | Установи `python3-devel` (шаг 1) |
| `Unable to retrieve device list!` | `sudo systemctl restart usbmuxd`, разблокируй iPhone, доверь компьютер |
| `Device is not paired` / `LOCKDOWN_E_INVALID_HOST_ID` | `pymobiledevice3 lockdown pair`, разблокируй iPhone, нажми «Доверять» |
| `ApplicationVerificationFailed` | Истёк сертификат (7 дней) — переподпиши; проверь WWDR CA и key-cert match |
| `unable to load PKCS#12` | Добавь `-legacy` в openssl pkcs12 (шаг 6) |
| Bundle ID mismatch | Проверь bundle ID IPA: `unzip -p Ugolek-unsigned.ipa 'Payload/*.app/Info.plist' \| plutil -p -` |
| `zsign: command not found` | `sudo cp /tmp/zsign/bin/zsign /usr/local/bin/`, потом `hash -r` |
| `/usr/local/bin` не в PATH | `echo $PATH` — если нет, добавь `export PATH="/usr/local/bin:$PATH"` |
