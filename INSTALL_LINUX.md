# Установка Уголька с Linux (Fedora)

## Разовая настройка (~15 минут)

### 1. Установить инструменты

```bash
sudo dnf install libimobiledevice ideviceinstaller openssl-devel git gcc-c++ python3-pip
sudo systemctl enable --now usbmuxd
pip install --user pymobiledevice3
```

### 2. Собрать zsign (подпись IPA)

```bash
git clone https://github.com/zhlynn/zsign.git /tmp/zsign
cd /tmp/zsign/build/linux
make clean && make
sudo cp zsign /usr/local/bin/
```

### 3. Настроить сертификат Apple Developer

```bash
mkdir -p ~/ugolek-sign

# Сгенерировать ключ и CSR
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ~/ugolek-sign/developer.key \
  -out ~/ugolek-sign/developer.csr \
  -subj "/CN=Ugolek Developer"
```

4. Открой https://developer.apple.com/account/
5. Certificates → создай сертификат → загрузи CSR → скачай .cer
6. Собери .p12:

```bash
openssl pkcs12 -export -out ~/ugolek-sign/developer.p12 \
  -inkey ~/ugolek-sign/developer.key \
  -in ~/ugolek-sign/developer.cer
```

7. Узнай UDID iPhone: `idevice_id -l` или `pymobiledevice3 usbmux list`
8. Зарегистрируй UDID в Devices → создай Provisioning Profile → скачай в ~/ugolek-sign/

## Установка IPA

```bash
# Скачать последнюю сборку
wget https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa

# Подписать
zsign -k ~/ugolek-sign/developer.p12 -p ПАРОЛЬ \
  -m ~/ugolek-sign/profile.mobileprovision \
  -o Ugolek-signed.ipa Ugolek-unsigned.ipa

# Установить
pymobiledevice3 apps install Ugolek-signed.ipa
```

## Ограничения

- **7 дней** — бесплатный сертификат живёт неделю. Переобрабатывай еженедельно.
- **3 приложения** — максимум для бесплатного Apple ID.
- Платный Developer Account ($99/год) убирает оба ограничения.

## Автоматизация (опционально)

Создай скрипт `~/bin/install-ugolek.sh`:

```bash
#!/bin/bash
set -e
cd ~/Ugolek
wget -q https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa -O /tmp/Ugolek-unsigned.ipa
zsign -k ~/ugolek-sign/developer.p12 -p "$UGOLEK_PASS" -m ~/ugolek-sign/profile.mobileprovision -o /tmp/Ugolek-signed.ipa /tmp/Ugolek-unsigned.ipa
pymobiledevice3 apps install /tmp/Ugolek-signed.ipa
echo "Готово!"
```

Сертификат и профиль в `~/ugolek-sign/`. Пароль — переменная окружения `UGOLEK_PASS`.
