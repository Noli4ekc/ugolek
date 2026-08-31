#!/bin/bash
# ugolek-install.sh — установка Уголька на iPhone с Fedora Linux
# Запусти: bash ~/ugolek-install.sh
# Повторный запуск — скрипт поймёт что уже сделано и продолжит

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }
step() { echo -e "\n${YELLOW}━━━ $1 ━━━${NC}"; }

SIGN_DIR="$HOME/ugolek-sign"
VENV_DIR="$HOME/ugolek-venv"
IPA_DIR="$HOME/Ugolek"

# ═══ Шаг 1: зависимости ═══
step "Шаг 1: системные зависимости"
MISSING=""
for pkg in git gcc-c++ pkgconf-pkg-config openssl-devel python3-devel python3-pip wget usbmuxd libimobiledevice-utils libimobiledevice ideviceinstaller; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then MISSING="$MISSING $pkg"; fi
done
if [ -n "$MISSING" ]; then
    warn "Установить:$MISSING"
    echo "Введи пароль:"
    sudo dnf install -y $MISSING
    ok "Зависимости установлены"
else
    ok "Все зависимости уже стоят"
fi

# ═══ Шаг 2: usbmuxd ═══
step "Шаг 2: usbmuxd"
if systemctl is-active --quiet usbmuxd; then ok "usbmuxd работает"
else sudo systemctl enable --now usbmuxd; ok "usbmuxd запущен"; fi

# ═══ Шаг 3: zsign ═══
step "Шаг 3: zsign"
if command -v zsign >/dev/null 2>&1; then ok "zsign уже стоит"
else
    if [ ! -f /tmp/zsign/bin/zsign ]; then
        echo "Собираю zsign..."
        rm -rf /tmp/zsign
        git clone -q https://github.com/zhlynn/zsign.git /tmp/zsign
        cd /tmp/zsign/build/linux && make clean >/dev/null 2>&1 && make
    fi
    sudo cp /tmp/zsign/bin/zsign /usr/local/bin/
    hash -r
    ok "zsign установлен в /usr/local/bin/"
fi

# ═══ Шаг 4: pymobiledevice3 ═══
step "Шаг 4: pymobiledevice3"
if [ -f "$VENV_DIR/bin/pymobiledevice3" ]; then ok "pymobiledevice3 уже установлен"
else
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install -q pymobiledevice3
    ok "pymobiledevice3 установлен в $VENV_DIR"
fi

# ═══ Шаг 5: Apple-сертификат ═══
step "Шаг 5: Apple-сертификат (разовая настройка, живёт 7 дней)"
if [ -f "$SIGN_DIR/developer.p12" ] && [ -f "$SIGN_DIR/profile.mobileprovision" ]; then
    ok "Сертификат и профиль уже существуют"
    read -rp "Пересоздать? [y/N]: " REBUILD
    [[ "$REBUILD" =~ ^[Yy]$ ]] || STEP5_DONE=true
fi

if [ "${STEP5_DONE:-false}" != "true" ]; then
    mkdir -p "$SIGN_DIR"
    echo ""; echo "════════════════════════════════════════════════════"
    echo " Сейчас создаём Apple-сертификат. Разовая процедура."
    echo " Сертификат живёт 7 дней."
    echo "════════════════════════════════════════════════════"; echo ""

    if [ ! -f "$SIGN_DIR/developer.key" ]; then
        read -rp "Email от Apple ID: " APPLE_EMAIL
        openssl req -new -newkey rsa:2048 -nodes \
          -keyout "$SIGN_DIR/developer.key" \
          -out "$SIGN_DIR/developer.csr" \
          -subj "/emailAddress=$APPLE_EMAIL, CN=Ugolek Developer, C=RU"
        ok "CSR создан"
    fi

    echo ""; echo "┌─────────────────────────────────────────────────────┐"
    echo "│  Открой: https://developer.apple.com/account       │"
    echo "│  Войди в Apple ID.                                 │"
    echo "│  1) Certificates → + → iOS App Development          │"
    echo "│  2) Загрузи: $SIGN_DIR/developer.csr               │"
    echo "│  3) Continue → Download                            │"
    echo "│  4) Скачанный .cer положи в: $SIGN_DIR/            │"
    echo "└─────────────────────────────────────────────────────┘"; echo ""
    read -rp "Нажми Enter когда скачаешь .cer..."

    CER=$(find "$SIGN_DIR" ~/Downloads -name "*.cer" -mmin -5 2>/dev/null | head -1)
    [ -z "$CER" ] && { err "Не вижу .cer. Скачай в $SIGN_DIR."; exit 1; }
    cp "$CER" "$SIGN_DIR/ios_development.cer"
    openssl x509 -in "$SIGN_DIR/ios_development.cer" -inform DER -out "$SIGN_DIR/developer.pem"

    [ ! -f "$SIGN_DIR/wwdr.pem" ] && curl -sL https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer -o "$SIGN_DIR/wwdr.cer" && openssl x509 -in "$SIGN_DIR/wwdr.cer" -inform DER -out "$SIGN_DIR/wwdr.pem"

    read -rsp "Пароль от сертификата (запомни!): " P12_PASS; echo ""
    openssl pkcs12 -export -legacy -out "$SIGN_DIR/developer.p12" \
      -inkey "$SIGN_DIR/developer.key" -in "$SIGN_DIR/developer.pem" \
      -certfile "$SIGN_DIR/wwdr.pem" -passout "pass:$P12_PASS"
    echo "$P12_PASS" > "$SIGN_DIR/.password"
    ok "Сертификат подписан"

    MOD_CERT=$(openssl x509 -noout -modulus -in "$SIGN_DIR/developer.pem" | openssl md5)
    MOD_KEY=$(openssl rsa -noout -modulus -in "$SIGN_DIR/developer.key" | openssl md5)
    [ "$MOD_CERT" != "$MOD_KEY" ] && { err "Ключ и сертификат не совпадают!"; exit 1; }
    ok "Ключ и сертификат совпадают"

    echo ""; echo "Подключи iPhone по USB и разблокируй."
    read -rp "Нажми Enter..."
    UDID=$(idevice_id -l 2>/dev/null | head -1)
    [ -z "$UDID" ] && { err "iPhone не найден. Разблокируй и нажми «Доверять»."; exit 1; }
    ok "iPhone: $UDID"

    echo ""; echo "┌─────────────────────────────────────────────────────┐"
    echo "│  developer.apple.com:                               │"
    echo "│  1) Devices → + → UDID: $UDID                       │"
    echo "│  2) Identifiers → + → App ID: com.ugolek.app         │"
    echo "│  3) Profiles → + → iOS App Development              │"
    echo "│  Download → сохрани в $SIGN_DIR/                    │"
    echo "└─────────────────────────────────────────────────────┘"; echo ""
    read -rp "Нажми Enter когда скачаешь профиль..."
    [ ! -f "$SIGN_DIR/profile.mobileprovision" ] && cp $(find ~/Downloads -name "*.mobileprovision" -mmin -5 | head -1) "$SIGN_DIR/profile.mobileprovision" 2>/dev/null
    ok "Профиль на месте"
    ok "Сертификат полностью настроен!"
fi

# ═══ Шаг 6: lockdown pair ═══
step "Шаг 6: пара с iPhone"
source "$VENV_DIR/bin/activate"
pymobiledevice3 lockdown pair 2>/dev/null || { echo "Разблокируй iPhone, нажми «Доверять»..."; pymobiledevice3 lockdown pair; }
ok "Пара установлена"

# ═══ Шаг 7: скачать, подписать, установить ═══
step "Шаг 7: скачать, подписать, установить IPA"
mkdir -p "$IPA_DIR" && cd "$IPA_DIR"
rm -f Ugolek-unsigned.ipa Ugolek-signed.ipa
echo "Скачиваю IPA..."
wget -q --show-progress https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa
ok "IPA скачан"

P12_PASS=$(cat "$SIGN_DIR/.password" 2>/dev/null)
[ -z "$P12_PASS" ] && { read -rsp "Пароль от сертификата: " P12_PASS; echo ""; }

echo "Подписываю..."
zsign -k "$SIGN_DIR/developer.p12" -p "$P12_PASS" \
  -m "$SIGN_DIR/profile.mobileprovision" \
  -o Ugolek-signed.ipa Ugolek-unsigned.ipa
ok "IPA подписан"

echo ""; echo "Устанавливаю на iPhone..."
pymobiledevice3 apps install Ugolek-signed.ipa

echo ""; echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Готово! 🔥${NC}"
echo "═══════════════════════════════════════════════════════"
echo "На iPhone: Настройки → Основные → VPN → доверь Apple ID."
echo "Обновиться потом — запусти этот скрипт заново:"
echo "  bash ~/ugolek-install.sh"