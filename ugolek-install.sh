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
    echo -e "${CYAN}║  ${GREEN}1) Бесплатно${CYAN} — ipasideloader + бесплатный Apple ID        ║${NC}"
    echo -e "${CYAN}║     Подпись на 7 дней, автопродление с ПК                    ║${NC}"
    echo -e "${CYAN}║     Требует: Docker                                          ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}2) Платно${CYAN}   — Apple Developer Program ($99/год)          ║${NC}"
    echo -e "${CYAN}║     Подпись на 1 год, без ограничений                        ║${NC}"
    echo -e "${CYAN}║     Трудоёмко: ручная работа с сертификатами                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Какой способ использовать?"
    echo -e "  ${GREEN}1${NC}) Бесплатно (ipasideloader, 7 дней)"
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
        echo -e "${GREEN}Выбран бесплатный способ (ipasideloader + бесплатный Apple ID).${NC}"
    fi
fi

IPA_DIR="$HOME/Ugolek"
mkdir -p "$IPA_DIR" && cd "$IPA_DIR"

# ═══ Общие функции ═══
check_iphone() {
    step "Проверка iPhone"
    UDID=$(idevice_id -l 2>/dev/null | head -1)
    if [ -z "$UDID" ]; then
        warn "iPhone не найден. Перезапускаю usbmuxd..."
        sudo systemctl restart usbmuxd 2>/dev/null
        sleep 3
        UDID=$(idevice_id -l 2>/dev/null | head -1)
    fi
    if [ -z "$UDID" ]; then
        warn "Разблокируй iPhone и нажми «Доверять»."
        echo "Ожидание подключения (Ctrl+C для отмены)..."
        for i in $(seq 1 30); do
            sleep 2
            UDID=$(idevice_id -l 2>/dev/null | head -1)
            if [ -n "$UDID" ]; then break; fi
            echo "  попытка $i: ещё не виден..."
        done
    fi
    if [ -z "$UDID" ]; then
        err "iPhone не обнаружен за ~60 секунд."
        echo ""
        echo "Проверь:"
        echo "  1) Кабель подключён (попробуй другой кабель/порт USB)"
        echo "  2) iPhone разблокирован"
        echo "  3) На экране iPhone нажми «Доверять этому компьютеру»"
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
# БЕСПЛАТНЫЙ ПУТЬ — ipasideloader + Docker
# ══════════════════════════════════════════════════════════════
install_free() {
    step "Бесплатная установка через ipasideloader"

    # --- Docker ---
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
        if ! groups | grep -q docker; then
            warn "Для работы Docker нужна группа docker."
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
        warn "Docker daemon не запущен. Запускаю..."
        sudo systemctl start docker
        sleep 2
    fi

    # --- ipasideloader ---
    step "ipasideloader (подпись IPA)"
    IPALOADER_DIR="$HOME/ipasideloader"
    if [ -d "$IPALOADER_DIR" ]; then
        ok "ipasideloader уже скачан"
    else
        echo "Скачиваю ipasideloader..."
        git clone -q https://github.com/heycodngskills/ipasideloader.git "$IPALOADER_DIR"
        ok "ipasideloader скачан в $IPALOADER_DIR"
    fi

    # --- Зависимости для установки ---
    step "Зависимости для установки"
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

    # pymobiledevice3 для установки подписанного IPA
    VENV_DIR="$HOME/ugolek-venv"
    if [ ! -f "$VENV_DIR/bin/pymobiledevice3" ]; then
        echo "Устанавливаю pymobiledevice3..."
        python3 -m venv "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        pip install -q pymobiledevice3
        ok "pymobiledevice3 установлен"
    else
        ok "pymobiledevice3 уже установлен"
    fi

    # --- Скачивание IPA ---
    download_ipa

    # --- Проверка iPhone ---
    check_iphone

    # --- Авторизация Apple ID ---
    step "Авторизация Apple ID"
    CREDS_FILE="$HOME/.ugolek-credentials"
    if [ -f "$CREDS_FILE" ]; then
        # Загружаем сохранённые креды
        APPLE_EMAIL=$(head -1 "$CREDS_FILE")
        APPLE_PASS=$(tail -1 "$CREDS_FILE")
        ok "Используем сохранённый Apple ID: $APPLE_EMAIL"
        echo "Нажми Enter чтобы использовать его, или введи новый email:"
        read -rp "> " NEW_EMAIL
        if [ -n "$NEW_EMAIL" ]; then
            APPLE_EMAIL="$NEW_EMAIL"
            read -rsp "Пароль: " APPLE_PASS; echo ""
            # Сохраняем новые креды
            printf '%s\n%s' "$APPLE_EMAIL" "$APPLE_PASS" > "$CREDS_FILE"
            chmod 600 "$CREDS_FILE"
            ok "Креды сохранены для следующего раза"
        fi
    else
        echo "Введи данные от бесплатного Apple ID."
        echo -e "${YELLOW}Внимание:${NC} пароль передаётся напрямую в Apple."
        read -rp "Email Apple ID: " APPLE_EMAIL
        read -rsp "Пароль: " APPLE_PASS; echo ""
        # Сохраняем для следующего раза
        printf '%s\n%s' "$APPLE_EMAIL" "$APPLE_PASS" > "$CREDS_FILE"
        chmod 600 "$CREDS_FILE"
        ok "Креды сохранены для следующего раза (файл: $CREDS_FILE)"
    fi

    # --- Подпись через ipasideloader в Docker ---
    step "Подпись IPA (бесплатно, 7 дней)"
    echo "Подписываю через ipasideloader..."

    # Создаём workdir для ipasideloader
    WORKDIR="$IPA_DIR/ipasideloader-work"
    mkdir -p "$WORKDIR"
    cp "$IPA_DIR/Ugolek-unsigned.ipa" "$WORKDIR/"

    # Запускаем подпись в Docker
    docker compose -f "$IPALOADER_DIR/docker-compose.yml" build 2>/dev/null || {
        warn "Docker build занял время, продолжаю..."
    }

    # Подпись с бесплатным Apple ID
    docker compose -f "$IPALOADER_DIR/docker-compose.yml" run --rm ipasideloader \
      sign-install /work/Ugolek-unsigned.ipa \
      --apple-id "$APPLE_EMAIL" \
      --apple-password "$APPLE_PASS" \
      --no-install -o /work/Ugolek-signed.ipa 2>&1

    if [ ! -f "$WORKDIR/Ugolek-signed.ipa" ]; then
        err "Подпись не удалась. Проверь Apple ID и пароль."
        exit 1
    fi
    ok "IPA подписан"

    # --- Установка на iPhone ---
    step "Установка на iPhone"
    source "$VENV_DIR/bin/activate"
    pymobiledevice3 apps install "$WORKDIR/Ugolek-signed.ipa"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo -e "${GREEN}  Готово! 🔥${NC}"
    echo "═══════════════════════════════════════════════════════"
    echo "Подпись живёт 7 дней. Чтобы продлить:"
    echo "  Перезапусти скрипт: bash ~/ugolek-install.sh"
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
