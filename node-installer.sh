#!/bin/bash
# =============================================================================
#  🌐 RemnaNode Installer v1.0
#  Автор: anqqu | https://github.com/anqqu/remnanode-installer
#  ОС: Debian 11/12, Ubuntu 22.04/24.04 LTS | Виртуализация: KVM
# =============================================================================

# ЗАЩИТА ОТ curl | bash: если stdin не терминал — скачиваем себя и перезапускаем
if [[ ! -t 0 ]]; then
    _SELF_TMP=$(mktemp /tmp/rw-install-XXXXXX.sh)
    curl -fsSL "https://raw.githubusercontent.com/anqqu/remnanode-installer/main/node-installer.sh" \
         -o "$_SELF_TMP" 2>/dev/null || { echo "Ошибка загрузки"; exit 1; }
    chmod +x "$_SELF_TMP"
    exec bash "$_SELF_TMP" "$@" < /dev/tty
fi

# =============================================================================
# ЦВЕТА И ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✅ $*${RESET}"; }
err()  { echo -e "  ${RED}❌ $*${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠️  $*${RESET}"; }
info() { echo -e "  ${BLUE}ℹ️  $*${RESET}"; }
sep()  { echo -e "  ${CYAN}────────────────────────────────────────────${RESET}"; }

# =============================================================================
# ПУТИ
# =============================================================================
REMNANODE_DIR="/opt/remnanode"   # директория ноды
CERTBOT_DIR="/opt/certbot"       # директория certbot

# =============================================================================
# ПРОВЕРКИ
# =============================================================================

check_root() {
    [[ $EUID -ne 0 ]] && { err "Запусти от root: sudo bash node-installer.sh"; exit 1; }
}

# Проверяем Docker, при необходимости устанавливаем
check_docker() {
    if ! command -v docker &>/dev/null; then
        warn "Docker не найден. Устанавливаем..."
        curl -fsSL https://get.docker.com | sh
        if ! command -v docker &>/dev/null; then
            err "Ошибка установки Docker! Проверь подключение к интернету."
            exit 1
        fi
        ok "Docker установлен!"
    else
        ok "Docker уже установлен: $(docker --version | awk '{print $3}' | tr -d ',')"
    fi
}

# =============================================================================
# РЕЖИМ 1: ОБЫЧНАЯ НОДА (БЕЗ SSL)
# =============================================================================
fn_install_node() {
    sep; echo -e "${BOLD}🐳 Установка RemnaNode (без SSL)${RESET}"; sep

    # Шаг 1: Проверяем Docker
    info "Шаг 1/4: Проверка Docker..."
    check_docker

    # Шаг 2: Создаём рабочую директорию
    info "Шаг 2/4: Создание директории ${REMNANODE_DIR}..."
    mkdir -p "${REMNANODE_DIR}"
    ok "Директория готова: ${REMNANODE_DIR}"

    # Шаг 3: Запрашиваем параметры из панели у пользователя
    sep
    info "Шаг 3/4: Введи данные из панели Remnawave"
    echo ""
    echo -e "  ${YELLOW}⚡ Эти данные берутся при создании ноды в панели Remnawave${RESET}"
    echo ""

    # Запрос порта (валидация: только цифры, не пустой)
    read -rp "  Введи NODE_PORT (порт из панели): " NODE_PORT
    while [[ -z "$NODE_PORT" || ! "$NODE_PORT" =~ ^[0-9]+$ ]]; do
        warn "Порт должен быть числом и не пустым!"
        read -rp "  Введи NODE_PORT: " NODE_PORT
    done

    echo ""
    # Запрос секретного ключа
    read -rp "  Введи SECRET_KEY (секретный ключ из панели): " SECRET_KEY
    while [[ -z "$SECRET_KEY" ]]; do
        warn "Секретный ключ не может быть пустым!"
        read -rp "  Введи SECRET_KEY: " SECRET_KEY
    done

    # Шаг 4: Записываем docker-compose.yml с подставленными значениями
    info "Шаг 4/4: Создание docker-compose.yml..."
    cat > "${REMNANODE_DIR}/docker-compose.yml" <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF
    ok "docker-compose.yml создан в ${REMNANODE_DIR}"

    # Запускаем ноду и сразу показываем логи
    sep
    info "Запуск RemnaNode..."
    cd "${REMNANODE_DIR}" && docker compose up -d
    ok "Нода запущена! Показываем логи (Ctrl+C для выхода в меню)..."
    echo ""
    docker compose logs -f -t
}

# =============================================================================
# РЕЖИМ 2: НОДА + SSL (CERTBOT / HYSTERIA / XTLS)
# =============================================================================
fn_install_node_ssl() {
    sep; echo -e "${BOLD}🔒 Установка RemnaNode + SSL (Certbot)${RESET}"; sep

    # Шаг 1: Проверяем Docker
    info "Шаг 1/9: Проверка Docker..."
    check_docker

    # Шаг 2: Создаём директорию ноды
    info "Шаг 2/9: Создание директории ${REMNANODE_DIR}..."
    mkdir -p "${REMNANODE_DIR}"
    ok "Директория готова: ${REMNANODE_DIR}"

    # Шаг 3: Параметры ноды из панели
    sep
    info "Шаг 3/9: Введи данные из панели Remnawave"
    echo ""
    echo -e "  ${YELLOW}⚡ Эти данные берутся при создании ноды в панели Remnawave${RESET}"
    echo ""

    read -rp "  Введи NODE_PORT (порт из панели): " NODE_PORT
    while [[ -z "$NODE_PORT" || ! "$NODE_PORT" =~ ^[0-9]+$ ]]; do
        warn "Порт должен быть числом и не пустым!"
        read -rp "  Введи NODE_PORT: " NODE_PORT
    done

    echo ""
    read -rp "  Введи SECRET_KEY (секретный ключ из панели): " SECRET_KEY
    while [[ -z "$SECRET_KEY" ]]; do
        warn "Секретный ключ не может быть пустым!"
        read -rp "  Введи SECRET_KEY: " SECRET_KEY
    done

    # Шаг 4: Данные для SSL-сертификата
    sep
    info "Шаг 4/9: Введи данные для SSL-сертификата"
    echo ""
    echo -e "  ${YELLOW}⚠️  Домен должен уже указывать на IP этого сервера!${RESET}"
    echo -e "  ${YELLOW}⚠️  Порт 80 будет временно нужен Certbot для проверки.${RESET}"
    echo ""

    read -rp "  Введи домен (например: node.example.com): " DOMAIN
    while [[ -z "$DOMAIN" ]]; do
        warn "Домен не может быть пустым!"
        read -rp "  Введи домен: " DOMAIN
    done

    echo ""
    read -rp "  Введи email для уведомлений Let's Encrypt: " EMAIL
    # Простая проверка формата email (содержит @ и .)
    while [[ -z "$EMAIL" || ! "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
        warn "Введи корректный email (например: admin@example.com)!"
        read -rp "  Введи email: " EMAIL
    done

    # Шаг 5: Создаём docker-compose.yml ноды С секцией volumes для сертификатов
    info "Шаг 5/9: Создание docker-compose.yml ноды (с SSL volumes)..."
    cat > "${REMNANODE_DIR}/docker-compose.yml" <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - '/opt/certbot/certs:/etc/letsencrypt:ro'
EOF
    ok "docker-compose.yml ноды создан (с монтированием сертификатов)"

    # Шаг 6: Создаём директорию и docker-compose.yml для Certbot
    info "Шаг 6/9: Подготовка Certbot..."
    mkdir -p "${CERTBOT_DIR}/certs"
    cat > "${CERTBOT_DIR}/docker-compose.yml" <<EOF
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
EOF
    ok "Certbot готов: ${CERTBOT_DIR}"

    # Шаг 7: Получаем SSL-сертификат через Certbot standalone
    sep
    info "Шаг 7/9: Получение SSL-сертификата для домена: ${DOMAIN}..."
    warn "Certbot поднимет временный HTTP-сервер на порту 80 для проверки домена"
    echo ""

    # Если ufw активен — временно открываем порт 80
    UFW_OPENED=false
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        info "ufw активен → временно открываем порт 80..."
        ufw allow 80/tcp >/dev/null 2>&1
        UFW_OPENED=true
    fi

    # Запускаем certbot в режиме standalone (сам поднимает веб-сервер для проверки)
    docker run --rm \
        -v "${CERTBOT_DIR}/certs:/etc/letsencrypt" \
        -v "${CERTBOT_DIR}/var-lib-letsencrypt:/var/lib/letsencrypt" \
        --network host \
        certbot/certbot certonly --standalone \
        --non-interactive --agree-tos \
        --email "${EMAIL}" \
        -d "${DOMAIN}"

    CERT_EXIT=$?

    # Закрываем порт 80 обратно если открывали
    if [[ "${UFW_OPENED}" == "true" ]]; then
        ufw delete allow 80/tcp >/dev/null 2>&1
        info "Порт 80 закрыт обратно"
    fi

    # Проверяем результат получения сертификата
    if [[ $CERT_EXIT -ne 0 ]]; then
        err "Ошибка получения сертификата! Возможные причины:"
        warn "  1. Домен ${DOMAIN} не указывает на IP этого сервера"
        warn "  2. Порт 80 был занят другим процессом"
        warn "  3. Проблема с DNS (записи не успели применить)"
        return 1
    fi
    ok "Сертификат успешно получен для: ${DOMAIN}"

    # Шаг 8: Настраиваем cron для автообновления сертификата (28-е число каждого месяца)
    info "Шаг 8/9: Настройка автообновления сертификата..."
    # Строка cron: в 00:00 28-го числа — разрешаем 80, обновляем, закрываем 80
    CRON_JOB="0 0 28 * * ufw allow 80/tcp && cd ${CERTBOT_DIR} && docker compose run --rm certbot renew; ufw delete allow 80/tcp"
    # Добавляем в crontab, предварительно удалив старую задачу если была
    ( crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$CRON_JOB" ) | crontab -
    ok "Cron добавлен: автообновление сертификата 28-го числа каждого месяца"
    info "Просмотр crontab: crontab -l"

    # Шаг 9: Запускаем ноду с сертификатами
    sep
    info "Шаг 9/9: Запуск RemnaNode с SSL..."
    cd "${REMNANODE_DIR}" && docker compose up -d
    ok "Нода запущена с SSL! Показываем логи (Ctrl+C для выхода в меню)..."
    echo ""
    docker compose logs -f -t
}

# =============================================================================
# ОБНОВЛЕНИЕ НОДЫ
# =============================================================================
fn_update_node() {
    sep; echo -e "${BOLD}🔄 Обновление RemnaNode${RESET}"; sep

    # Проверяем что нода вообще установлена
    if [[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        err "Файл ${REMNANODE_DIR}/docker-compose.yml не найден!"
        warn "Сначала установи ноду (пункт 1 или 2)"
        return 1
    fi

    info "Скачиваем новый образ remnawave/node:latest..."
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" pull
    info "Перезапускаем ноду с новым образом..."
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" up -d
    ok "RemnaNode обновлена и перезапущена!"
}

# =============================================================================
# ЛОГИ НОДЫ
# =============================================================================
fn_logs() {
    sep; echo -e "${BOLD}📋 Логи RemnaNode${RESET}"; sep

    if [[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        err "Файл ${REMNANODE_DIR}/docker-compose.yml не найден!"
        warn "Сначала установи ноду (пункт 1 или 2)"
        return 1
    fi

    info "Показываем логи (Ctrl+C для выхода в меню)..."
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" logs -f -t
}

# =============================================================================
# ОСТАНОВКА НОДЫ
# =============================================================================
fn_stop() {
    sep; echo -e "${BOLD}🛑 Остановка RemnaNode${RESET}"; sep

    if [[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        err "Файл ${REMNANODE_DIR}/docker-compose.yml не найден!"
        return 1
    fi

    read -rp "  Остановить ноду? [y/N]: " c
    [[ "$c" =~ ^[Yy]$ ]] || { info "Отменено."; return; }

    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" down
    ok "RemnaNode остановлена"
}

# =============================================================================
# ЗАПУСК / ПЕРЕЗАПУСК НОДЫ
# =============================================================================
fn_start() {
    sep; echo -e "${BOLD}▶️  Запуск/Перезапуск RemnaNode${RESET}"; sep

    if [[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        err "Файл ${REMNANODE_DIR}/docker-compose.yml не найден!"
        warn "Сначала установи ноду (пункт 1 или 2)"
        return 1
    fi

    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" up -d
    ok "RemnaNode запущена!"
    echo ""
    info "Статус контейнера:"
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" ps
}

# =============================================================================
# УСТАНОВКА АЛИАС-КОМАНДЫ 'rw-install'
# =============================================================================
fn_install_alias() {
    sep; echo -e "${BOLD}📥 Установка команды 'rw-install'${RESET}"; sep

    ALIAS_PATH="/usr/local/bin/rw-install"

    # Записываем маленький враппер-скрипт, который скачивает и запускает актуальную версию
    cat > "$ALIAS_PATH" <<'ALIAS_EOF'
#!/bin/bash
# Враппер: скачивает актуальный node-installer.sh и запускает его
_TMP=$(mktemp /tmp/rw-install-XXXXXX.sh)
curl -fsSL "https://raw.githubusercontent.com/anqqu/remnanode-installer/main/node-installer.sh" \
     -o "$_TMP" 2>/dev/null || { echo "Ошибка загрузки скрипта!"; exit 1; }
chmod +x "$_TMP"
exec bash "$_TMP" "$@" < /dev/tty
ALIAS_EOF

    chmod +x "$ALIAS_PATH"
    ok "Команда 'rw-install' установлена → ${ALIAS_PATH}"
    info "Теперь запускай меню командой: rw-install"
}

# =============================================================================
# РЕЖИМ 3: ДОБАВИТЬ SSL К СУЩЕСТВУЮЩЕЙ НОДЕ (АПГРЕЙД)
# =============================================================================
fn_upgrade_to_ssl() {
    sep; echo -e "${BOLD}🔐 Добавление SSL к существующей ноде${RESET}"; sep

    # Проверяем что нода вообще установлена
    if [[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        err "Нода не установлена!"
        warn "Сначала установи ноду (пункт 1), затем добавь к ней SSL"
        return 1
    fi

    # Предупреждаем если SSL уже прописан
    if grep -q "letsencrypt" "${REMNANODE_DIR}/docker-compose.yml" 2>/dev/null; then
        warn "SSL уже прописан в docker-compose.yml ноды"
        read -rp "  Перепривязать другой сертификат/домен? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] || { info "Отменено."; return; }
    fi

    # Читаем PORT и KEY из текущего docker-compose.yml — они нам понадобятся
    NODE_PORT=$(grep "NODE_PORT=" "${REMNANODE_DIR}/docker-compose.yml" | cut -d= -f2 | tr -d '[:space:]')
    SECRET_KEY=$(grep "SECRET_KEY=" "${REMNANODE_DIR}/docker-compose.yml" | cut -d= -f2 | tr -d '[:space:]')

    if [[ -z "$NODE_PORT" || -z "$SECRET_KEY" ]]; then
        err "Не удалось прочитать NODE_PORT или SECRET_KEY из docker-compose.yml"
        return 1
    fi
    info "Найдены параметры: NODE_PORT=${NODE_PORT}"

    # Запрашиваем домен и email
    sep
    echo ""
    echo -e "  ${YELLOW}⚠️  Домен должен уже указывать на IP этого сервера!${RESET}"
    echo -e "  ${YELLOW}⚠️  Порт 80 будет временно нужен Certbot для проверки.${RESET}"
    echo ""
    read -rp "  Введи домен (например: node.example.com): " DOMAIN
    while [[ -z "$DOMAIN" ]]; do
        warn "Домен не может быть пустым!"
        read -rp "  Введи домен: " DOMAIN
    done
    echo ""
    read -rp "  Введи email для Let's Encrypt: " EMAIL
    while [[ -z "$EMAIL" || ! "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
        warn "Введи корректный email (например: admin@example.com)!"
        read -rp "  Введи email: " EMAIL
    done

    # Останавливаем ноду перед получением сертификата (порт 80 должен быть свободен)
    info "Останавливаем ноду перед получением сертификата..."
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" down 2>/dev/null || true

    # Готовим Certbot
    info "Подготовка Certbot в ${CERTBOT_DIR}..."
    mkdir -p "${CERTBOT_DIR}/certs"
    cat > "${CERTBOT_DIR}/docker-compose.yml" <<EOF
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
EOF

    # Временно открываем 80 если ufw активен
    UFW_OPENED=false
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        info "ufw активен → временно открываем порт 80..."
        ufw allow 80/tcp >/dev/null 2>&1
        UFW_OPENED=true
    fi

    # Получаем сертификат через Certbot standalone
    info "Получение SSL-сертификата для домена: ${DOMAIN}..."
    docker run --rm \
        -v "${CERTBOT_DIR}/certs:/etc/letsencrypt" \
        -v "${CERTBOT_DIR}/var-lib-letsencrypt:/var/lib/letsencrypt" \
        --network host \
        certbot/certbot certonly --standalone \
        --non-interactive --agree-tos \
        --email "${EMAIL}" \
        -d "${DOMAIN}"
    CERT_EXIT=$?

    # Закрываем 80 обратно
    if [[ "${UFW_OPENED}" == "true" ]]; then
        ufw delete allow 80/tcp >/dev/null 2>&1
        info "Порт 80 закрыт"
    fi

    if [[ $CERT_EXIT -ne 0 ]]; then
        err "Ошибка получения сертификата! Запускаем ноду без SSL..."
        docker compose -f "${REMNANODE_DIR}/docker-compose.yml" up -d
        return 1
    fi
    ok "Сертификат получен для: ${DOMAIN}"

    # Перезаписываем docker-compose.yml с volumes для сертификатов
    # (сохраняем NODE_PORT и SECRET_KEY которые прочитали выше)
    info "Обновляем docker-compose.yml (добавляем SSL volumes)..."
    cat > "${REMNANODE_DIR}/docker-compose.yml" <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - '/opt/certbot/certs:/etc/letsencrypt:ro'
EOF
    ok "docker-compose.yml обновлён с SSL volumes"

    # Добавляем cron для автообновления
    info "Настройка cron автообновления (28-е число каждого месяца)..."
    CRON_JOB="0 0 28 * * ufw allow 80/tcp && cd ${CERTBOT_DIR} && docker compose run --rm certbot renew; ufw delete allow 80/tcp"
    ( crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$CRON_JOB" ) | crontab -
    ok "Cron добавлен"

    # Запускаем ноду с сертификатами
    info "Запуск ноды с SSL..."
    docker compose -f "${REMNANODE_DIR}/docker-compose.yml" up -d
    ok "SSL успешно добавлен! Нода перезапущена с сертификатом для ${DOMAIN}"
}

# =============================================================================
# НАСТРОЙКА UFW (ФАЕРВОЛ)
# =============================================================================
fn_setup_ufw() {
    sep; echo -e "${BOLD}🔥 Настройка UFW (фаервол)${RESET}"; sep

    # Устанавливаем ufw если не установлен
    if ! command -v ufw &>/dev/null; then
        info "ufw не найден, устанавливаем..."
        apt-get install -y ufw >/dev/null 2>&1
        ok "ufw установлен"
    fi

    # Читаем NODE_PORT из docker-compose ноды если есть
    NODE_PORT_CURRENT=""
    if [[ -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        NODE_PORT_CURRENT=$(grep "NODE_PORT=" "${REMNANODE_DIR}/docker-compose.yml" | cut -d= -f2 | tr -d '[:space:]')
    fi

    # Читаем порт заглушки если установлена
    STUB_PORT_CURRENT=""
    if [[ -f "/opt/remnanode-stub/nginx.conf" ]]; then
        STUB_PORT_CURRENT=$(grep "listen" "/opt/remnanode-stub/nginx.conf" 2>/dev/null | awk '{print $2}' | tr -d ';')
    fi

    echo ""
    warn "SSH будет разрешён автоматически — без этого потеряешь доступ!"
    echo ""
    echo -e "  ${BOLD}Выбери протокол для порта 443:${RESET}"
    echo -e "  ${GREEN}1)${RESET} 443 (TCP + UDP) ${YELLOW}— универсально, подходит для всего${RESET} ${GREEN}← рекомендуется${RESET}"
    echo -e "  ${GREEN}2)${RESET} 443/tcp — VLESS, Reality, XTLS-Reality"
    echo -e "  ${GREEN}3)${RESET} 443/udp — Hysteria2"
    echo ""
    read -rp "  Выбери [1-3]: " proto_choice

    case "$proto_choice" in
        2) UFW_443="443/tcp"  ;;
        3) UFW_443="443/udp"  ;;
        *) UFW_443="443"      ;;  # TCP+UDP — универсально
    esac

    # Показываем итоговые правила перед применением
    echo ""
    sep
    echo -e "  ${BOLD}Будут применены правила:${RESET}"
    echo -e "  ${GREEN}✓${RESET} ufw allow OpenSSH"
    echo -e "  ${GREEN}✓${RESET} ufw allow ${UFW_443}"
    [[ -n "$NODE_PORT_CURRENT" ]] && \
        echo -e "  ${GREEN}✓${RESET} ufw allow ${NODE_PORT_CURRENT}/tcp ${YELLOW}(порт ноды из панели)${RESET}"
    [[ -n "$STUB_PORT_CURRENT" ]] && \
        echo -e "  ${GREEN}✓${RESET} ufw allow ${STUB_PORT_CURRENT}/tcp ${YELLOW}(порт заглушки)${RESET}"
    echo -e "  ${GREEN}✓${RESET} ufw enable"
    sep
    echo ""

    read -rp "  Применить? [y/N]: " c
    [[ "$c" =~ ^[Yy]$ ]] || { info "Отменено."; return; }

    # Применяем правила
    ufw allow OpenSSH
    ufw allow "$UFW_443"
    [[ -n "$NODE_PORT_CURRENT" ]] && ufw allow "${NODE_PORT_CURRENT}/tcp"
    [[ -n "$STUB_PORT_CURRENT" ]] && ufw allow "${STUB_PORT_CURRENT}/tcp"

    # Включаем ufw (echo y — автоматическое подтверждение)
    echo "y" | ufw enable

    ok "UFW активирован!"
    echo ""
    ufw status numbered
}

# =============================================================================
# ЗАГЛУШКА — NGINX FALLBACK (страница "сайт на тех. работах")
# =============================================================================
fn_setup_stub() {
    sep; echo -e "${BOLD}🎭 Установка страницы-заглушки (Nginx fallback)${RESET}"; sep

    check_docker

    STUB_DIR="/opt/remnanode-stub"

    echo ""
    echo -e "  ${CYAN}Как это работает:${RESET}"
    echo -e "  • Nginx запускается на локальном порту (например, 8080)"
    echo -e "  • В панели Remnawave (Xray Inbound) добавляется fallback"
    echo -e "  • Если обычный браузер зайдёт на 443 — получит страницу-заглушку"
    echo -e "  • VPN-клиенты при этом продолжают работать как обычно"
    echo ""

    # Запрашиваем порт для nginx
    read -rp "  Порт для заглушки [по умолчанию 8080]: " STUB_PORT
    [[ -z "$STUB_PORT" || ! "$STUB_PORT" =~ ^[0-9]+$ ]] && STUB_PORT="8080"

    # Запрашиваем название сайта и текст сообщения
    echo ""
    read -rp "  Название сайта (например: MyService): " SITE_NAME
    [[ -z "$SITE_NAME" ]] && SITE_NAME="Сервис"

    echo ""
    read -rp "  Текст сообщения для посетителей: " STUB_MSG
    [[ -z "$STUB_MSG" ]] && STUB_MSG="Ведутся технические работы. Вернитесь позже."

    # Создаём рабочую директорию
    mkdir -p "${STUB_DIR}/html"

    # Генерируем HTML страницу-заглушку (минималистичный тёмный дизайн)
    info "Создаём страницу-заглушку..."
    cat > "${STUB_DIR}/html/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${SITE_NAME}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .card {
            text-align: center;
            padding: 3rem 2rem;
            max-width: 480px;
            background: #111;
            border: 1px solid #1f1f1f;
            border-radius: 16px;
        }
        .icon { font-size: 3.5rem; margin-bottom: 1.5rem; }
        h1 { font-size: 1.6rem; font-weight: 600; color: #fff; margin-bottom: 0.75rem; }
        p { font-size: 0.95rem; color: #666; line-height: 1.7; }
        .badge {
            display: inline-flex; align-items: center; gap: 8px;
            background: #1a1a1a; border: 1px solid #2a2a2a;
            padding: 0.4rem 1rem; border-radius: 999px;
            font-size: 0.8rem; color: #888; margin-bottom: 1.5rem;
        }
        .dot {
            width: 7px; height: 7px; border-radius: 50%;
            background: #ff4444;
            animation: pulse 2s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.4; transform: scale(0.85); }
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">🔧</div>
        <div class="badge"><span class="dot"></span>Временно недоступно</div>
        <h1>${SITE_NAME}</h1>
        <p>${STUB_MSG}</p>
    </div>
</body>
</html>
HTMLEOF

    # Создаём Nginx конфиг (слушает на STUB_PORT, отдаёт HTML)
    info "Создаём конфиг Nginx..."
    cat > "${STUB_DIR}/nginx.conf" <<EOF
server {
    listen ${STUB_PORT};
    root /usr/share/nginx/html;
    index index.html;
    server_tokens off;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

    # Docker Compose для заглушки (образ nginx:alpine — лёгкий)
    cat > "${STUB_DIR}/docker-compose.yml" <<EOF
services:
  remnanode-stub:
    container_name: remnanode-stub
    image: nginx:alpine
    network_mode: host
    restart: always
    volumes:
      - ./html:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
EOF

    # Запускаем заглушку
    info "Запуск заглушки на порту ${STUB_PORT}..."
    docker compose -f "${STUB_DIR}/docker-compose.yml" up -d

    ok "Заглушка запущена на порту ${STUB_PORT}!"
    echo ""
    sep
    echo -e "  ${BOLD}📌 Следующие шаги для подключения fallback в Xray:${RESET}"
    echo ""
    echo -e "  ${CYAN}1.${RESET} Зайди в панель Remnawave → Ноды → Xray Inbound (443)"
    echo -e "  ${CYAN}2.${RESET} Добавь в конфиг fallback (секция fallbacks):"
    echo ""
    echo -e "     ${YELLOW}{\"dest\": \"${STUB_PORT}\", \"xver\": 0}${RESET}"
    echo ""
    echo -e "  ${CYAN}3.${RESET} Открой порт в ufw: ${YELLOW}ufw allow ${STUB_PORT}/tcp${RESET}"
    echo -e "  ${CYAN}4.${RESET} Сохрани и примени конфиг в панели"
    echo ""
    echo -e "  ${BLUE}ℹ️  Файлы заглушки: ${STUB_DIR}/${RESET}"
    echo -e "  ${BLUE}ℹ️  HTML страница: ${STUB_DIR}/html/index.html${RESET}"
    sep
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ
# =============================================================================
main_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║      🌐 RemnaNode Installer  v1.0             ║${RESET}"
        echo -e "${CYAN}${BOLD}║   github.com/anqqu/remnanode-installer        ║${RESET}"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════╝${RESET}"
        echo ""

        # Динамический статус: запущена / остановлена / не установлена
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode$"; then
            echo -e "  ${GREEN}● RemnaNode: запущена${RESET}"
        elif [[ -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
            echo -e "  ${RED}● RemnaNode: остановлена${RESET}"
        else
            echo -e "  ${YELLOW}● RemnaNode: не установлена${RESET}"
        fi

        # Показываем домен если есть SSL-сертификат
        if [[ -d "${CERTBOT_DIR}/certs/live" ]]; then
            CERT_DOMAIN=$(ls "${CERTBOT_DIR}/certs/live" 2>/dev/null | head -n1)
            echo -e "  ${GREEN}🔒 SSL: ${CERT_DOMAIN:-активен}${RESET}"
        fi

        # Показываем статус заглушки если установлена
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode-stub$"; then
            echo -e "  ${GREEN}🎭 Заглушка: запущена${RESET}"
        fi

        echo ""
        sep
        echo -e "  ${BOLD}Установка:${RESET}"
        echo -e "  ${GREEN} 1)${RESET} 🐳 Установить ноду ${YELLOW}(без SSL)${RESET}"
        echo -e "  ${GREEN} 2)${RESET} 🔒 Установить ноду + SSL ${YELLOW}(Certbot / Hysteria / XTLS)${RESET}"
        echo -e "  ${GREEN} 3)${RESET} 🔐 Добавить SSL к существующей ноде ${YELLOW}(апгрейд)${RESET}"
        echo ""
        echo -e "  ${BOLD}Управление нодой:${RESET}"
        echo -e "  ${GREEN} 4)${RESET} 🔄 Обновить RemnaNode ${YELLOW}(docker compose pull + up)${RESET}"
        echo -e "  ${GREEN} 5)${RESET} 📋 Показать логи ноды"
        echo -e "  ${GREEN} 6)${RESET} 🛑 Остановить ноду"
        echo -e "  ${GREEN} 7)${RESET} ▶️  Запустить/Перезапустить ноду"
        echo ""
        echo -e "  ${BOLD}Безопасность и защита:${RESET}"
        echo -e "  ${GREEN} 8)${RESET} 🔥 Настроить UFW ${YELLOW}(фаервол: SSH + 443 + порт ноды)${RESET}"
        echo -e "  ${GREEN} 9)${RESET} 🎭 Установить заглушку ${YELLOW}(Nginx fallback на 443)${RESET}"
        echo ""
        echo -e "  ${BOLD}Утилиты:${RESET}"
        echo -e "  ${GREEN}10)${RESET} 📥 Установить команду ${CYAN}rw-install${RESET} ${YELLOW}(запуск из любого места)${RESET}"
        sep
        echo -e "  ${RED} 0)${RESET} ❌ Выход"
        echo ""

        read -rp "  Выбери пункт [0-10]: " choice
        echo ""

        case "$choice" in
            1)  fn_install_node       ;;
            2)  fn_install_node_ssl   ;;
            3)  fn_upgrade_to_ssl     ;;
            4)  fn_update_node        ;;
            5)  fn_logs               ;;
            6)  fn_stop               ;;
            7)  fn_start              ;;
            8)  fn_setup_ufw          ;;
            9)  fn_setup_stub         ;;
            10) fn_install_alias      ;;
            0)
                echo -e "${GREEN}Удачи! 👋${RESET}"
                exit 0 ;;
            *)
                warn "Неверный выбор: '$choice'. Введи 0-10." ;;
        esac

        echo ""
        read -rp "  Нажми Enter чтобы вернуться в меню..." _
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
check_root
# Авто-установка команды 'rw-install' при первом запуске (тихо, без вывода)
fn_install_alias 2>/dev/null || true
main_menu
