#!/bin/bash
# ugolek-install.sh — установка Уголька на iPhone с Fedora Linux
# Запусти: bash ~/ugolek-install.sh
# Повторный запуск — скрипт поймёт что уже сделано и продолжит

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }
step() { echo -e "\n${YELLOW}━━━ $1 ━━━${NC}"; }

# ═══ Выбор способа установки ═══
# Флаг --docker-ready: перезапуск после добавления в группу docker (меню не показывать)
if [ "$1" = "--docker-ready" ]; then
    INSTALL_MODE="free"
    echo -e "${GREEN}Продолжаем бесплатную установку (группа docker применена).${NC}"
else
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Установка Уголька на iPhone с Linux               ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Доступно два способа:                                      ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  ${GREEN}1) Бесплатно${CYAN} — AltServer + бесплатный Apple ID             ║${NC}"
    echo -e "${CYAN}║     Подпись на 7 дней, автопродление с ПК                    ║${NC}"
    echo -e "${CYAN}║     Требует: Docker (anisette-server)                        ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}2) Платно${CYAN}   — Apple Developer Program ($99/год)          ║${NC}"
    echo -e "${CYAN}║     Подпись на 1 год, без ограничений                        ║${NC}"
    echo -e "${CYAN}║     Трудоёмко: ручная работа с сертификатами                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Какой способ использовать?"
    echo -e "  ${GREEN}1${NC}) Бесплатно (AltServer, 7 дней)"
    echo -e "  ${YELLOW}2${NC}) Платно (Apple Developer, 1 год)"
    echo ""
    read -rp "Выбор [1/2]: " MODE

    if [ "$MODE" = "2" ]; then
        INSTALL_MODE="paid"
        echo ""
        echo -e "${YELLOW}Выбран платный способ (Apple Developer Program).${NC}"
    else
        INSTALL_MODE="free"
        echo ""
        echo -e "${GREEN}Выбран бесплатный способ (AltServer + бесплатный Apple ID).${NC}"
    fi
fi

IPA_DIR="$HOME/Ugolek"
mkdir -p "$IPA_DIR" && cd "$IPA_DIR"

# ═══ Общие функции ═══
get_udid() {
    if command -v idevice_id >/dev/null 2>&1; then
        UDID=$(idevice_id -l 2>/dev/null | head -1)
    elif [ -f "$HOME/ugolek-venv/bin/pymobiledevice3" ]; then
        UDID=$("$HOME/ugolek-venv/bin/pymobiledevice3" lockdown wifi-connection-information 2>/dev/null | grep -oP 'UDID:\s*\K.*' | head -1)
    fi
    echo "$UDID"
}

check_iphone() {
    step "Проверка iPhone"
    # Попробовать через usbmuxd если доступен
    if command -v idevice_id >/dev/null 2>&1; then
        UDID=$(idevice_id -l 2>/dev/null | head -1)
    fi
    if [ -z "$UDID" ]; then
        warn "iPhone не найден. Подключи по USB и разблокируй."
        read -rp "Нажми Enter когда готов..."
        UDID=$(idevice_id -l 2>/dev/null | head -1)
    fi
    if [ -z "$UDID" ]; then
        err "iPhone всё ещё не виден. Проверь кабель и «Доверять»."
        exit 1
    fi
    ok "iPhone найден: $UDID"
}

download_ipa() {
    step "Скачивание IPA"
    rm -f Ugolek-unsigned.ipa Ugolek-signed.ipa
    echo "Скачиваю последний релиз..."
    wget -q --show-progress https://github.com/Noli4ekc/ugolek/releases/download/rolling/Ugolek-unsigned.ipa
    ok "IPA скачан: $IPA_DIR/Ugolek-unsigned.ipa"
}

# ══════════════════════════════════════════════════════════════
# БЕСПЛАТНЫЙ ПУТЬ — AltServer-Linux + anisette-v3-server
# ══════════════════════════════════════════════════════════════
install_free() {
    step "Бесплатная установка через AltServer"

    # --- Docker для anisette-server ---
    if ! command -v docker >/dev/null 2>&1; then
        warn "Docker не найден. Устанавливаю..."
        sudo dnf install -y docker
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        ok "Docker установлен и пользователь добавлен в группу docker."
        echo ""
        echo -e "${YELLOW}Важно:${NC} нужен перезапуск сессии для применения прав."
        echo "Выйди из системы и зайди заново, потом запусти скрипт снова:"
        echo "  bash ~/ugolek-install.sh"
        exit 0
    fi

    # Проверяем что docker работает и есть права
    if ! docker info >/dev/null 2>&1; then
        # Проверяем состоит ли пользователь в группе docker
        if ! groups | grep -q docker; then
            warn "Для работы anisette-сервера нужна группа docker."
            echo "Скрипт добавит тебя в группу. Введи пароль суперпользовода:"
            echo ""
            read -rsp "Пароль: " SUDO_PASS; echo ""
            echo "$SUDO_PASS" | sudo -S usermod -aG docker "$USER" 2>/dev/null || {
                err "Неверный пароль или нет прав sudo."
                exit 1
            }
            ok "Группа docker добавлена."
            # Применяем группу без перезахода
            exec sg docker -c "bash $0 --docker-ready"
            exit 0
        fi
        # Группа есть но daemon не запущен
        warn "Docker daemon не запущен. Запускаю..."
        sudo systemctl start docker
        sleep 2
        # Перепроверяем
        if ! docker info >/dev/null 2>&1; then
            err "Docker всё ещё недоступен. Выполни вручную:"
            echo "  sudo systemctl start docker"
            echo "  sudo chmod 666 /var/run/docker.sock"
            exit 1
        fi
    fi

    # --- anisette-v3-server ---
    step "Anisette-сервер (эмуляция Mac для Apple)"
    if docker ps | grep -q anisette; then
        ok "anisette-сервер уже работает"
    else
        echo "Запускаю anisette-v3-server..."
        docker run -d --restart always --name anisette \
          -p 6969:6969 \
          -v anisette_data:/home/Alcoholic/.config/anisette-v3/lib/ \
          dadoum/anisette-v3-server 2>/dev/null || {
            warn "Не удалось запустить anisette. Попробую alt-anisette-server..."
            docker run -d --restart always --name anisette \
              -p 6969:6969 \
              nyamisty/alt_anisette_server
        }
        sleep 3
        ok "anisette-сервер запущен на http://127.0.0.1:6969"
    fi

    # --- AltServer-Linux ---
    step "AltServer-Linux"
    ALT_BIN="$HOME/ugolek-tools/AltServer"
    if [ -f "$ALT_BIN" ]; then
        ok "AltServer уже установлен"
    else
        echo "Скачиваю AltServer-Linux..."
        mkdir -p "$HOME/ugolek-tools"
        # Скачиваем последний релиз
        ALT_URL=$(curl -sL https://api.github.com/repos/NyaMisty/AltServer-Linux/releases/latest | grep browser_download_url | grep x86_64 | head -1 | cut -d'"' -f4)
        if [ -z "$ALT_URL" ]; then
            # Фолбэк на известный релиз
            ALT_URL="https://github.com/NyaMisty/AltServer-Linux/releases/download/0.0.1 AltServer-x86_64"
        fi
        wget -q --show-progress -O "$ALT_BIN" "$ALT_URL"
        chmod +x "$ALT_BIN"
        ok "AltServer установлен: $ALT_BIN"
    fi

    # --- Зависимости для AltServer ---
    step "Зависимости"
    MISSING=""
    for pkg in usbmuxd libimobiledevice-utils libimobiledevice; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then MISSING="$MISSING $pkg"; fi
    done
    if [ -n "$MISSING" ]; then
        warn "Установить:$MISSING"
        sudo dnf install -y $MISSING
    fi
    if ! systemctl is-active --quiet usbmuxd; then
        sudo systemctl enable --now usbmuxd
    fi
    ok "Зависимости на месте"

    # --- Скачивание IPA ---
    download_ipa

    # --- Проверка iPhone ---
    check_iphone

    # --- Авторизация Apple ID ---
    step "Авторизация Apple ID"
    echo "Введи данные от бесплатного Apple ID."
    echo -e "${YELLOW}Внимание:${NC} пароль передаётся напрямую в Apple (как в AltStore)."
    read -rp "Email Apple ID: " APPLE_EMAIL
    read -rsp "Пароль: " APPLE_PASS; echo ""

    # --- Подписываем и устанавливаем ---
    step "Подпись и установка (бесплатно, 7 дней)"
    echo "Подписываю и устанавливаю на iPhone..."
    echo "Когда появится запрос 2FA — введи код."

    export ALTSERVER_ANISETTE_SERVER="http://127.0.0.1:6969"
    export ALTSERVER_NO_SUBSCRIBE=1

    # AltServer подпишет и установит напрямую на устройство
    "$ALT_BIN" -u "$UDID" -a "$APPLE_EMAIL" -p "$APPLE_PASS" "$IPA_DIR/Ugolek-unsigned.ipa"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo -e "${GREEN}  Готово! 🔥${NC}"
    echo "═══════════════════════════════════════════════════════"
    echo "Подпись живёт 7 дней. Чтобы продлить:"
    echo "  1. Держи этот ПК включённым с запущенным anisette"
    echo "  2. Перезапусти скрипт: bash ~/ugolek-install.sh"
    echo ""
    echo "На iPhone: Настройки → Основные → VPN → доверь Apple ID."
}

# ══════════════════════════════════════════════════════════════
# ПЛАТНЫЙ ПУТЬ — zsign + pymobiledevice3 (Apple Developer $99/год)
# ══════════════════════════════════════════════════════════════
install_paid() {
    SIGN_DIR="$HOME/ugolek-sign"
    VENV_DIR="$HOME/ugolek-venv"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Платный способ: Apple Developer Program ($99/год)          ║${NC}"
    echo -e "${YELLOW}║  Сертификат живёт 1 год, без ограничений на приложения       ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

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
    step "Шаг 5: Apple-сертификат (разовая настройка, живёт 1 год)"
    if [ -f "$SIGN_DIR/developer.p12" ] && [ -f "$SIGN_DIR/profile.mobileprovision" ]; then
        ok "Сертификат и профиль уже существуют"
        read -rp "Пересоздать? [y/N]: " REBUILD
        [[ "$REBUILD" =~ ^[Yy]$ ]] || STEP5_DONE=true
    fi

    if [ "${STEP5_DONE:-false}" != "true" ]; then
        mkdir -p "$SIGN_DIR"
        echo ""; echo "════════════════════════════════════════════════════"
        echo " Сейчас создаём Apple-сертификат. Разовая процедура."
        echo " Сертификат живёт 1 год (платная подписка)."
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
    download_ipa

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
}

# ═══ Запуск ═══
if [ "$INSTALL_MODE" = "paid" ]; then
    install_paid
else
    install_free
fi
