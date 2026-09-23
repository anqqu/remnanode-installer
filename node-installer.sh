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
# FAIL2BAN — ЗАЩИТА ОТ БРУТФОРСА (вспомогательные функции)
# =============================================================================

F2B_CONF="/etc/fail2ban/jail.local"   # конфиг с нашими настройками

# Читаем текущее значение параметра из jail.local
_f2b_get() { grep "^${1}" "$F2B_CONF" 2>/dev/null | head -1 | awk '{print $3}'; }

# Форматируем секунды в человекочитаемый вид
_f2b_fmt() {
    local s=$1
    [[ ! "$s" =~ ^[0-9]+$ ]] && { echo "$s"; return; }
    (( s >= 86400 )) && { echo "$((s/86400))д $((s%86400/3600))ч"; return; }
    (( s >= 3600  )) && { echo "$((s/3600))ч $((s%3600/60))м";     return; }
    (( s >= 60    )) && { echo "$((s/60))м $((s%60))с";            return; }
    echo "${s}с"
}

# Записываем jail.local с текущими значениями переменных
_f2b_write_conf() {
    local bt=${1:-$(_f2b_get bantime)};  bt=${bt:-3600}
    local mr=${2:-$(_f2b_get maxretry)}; mr=${mr:-5}
    local ft=${3:-$(_f2b_get findtime)}; ft=${ft:-600}
    cat > "$F2B_CONF" <<EOF
# Конфиг Fail2Ban — создан rw-install скриптом
[DEFAULT]
bantime  = ${bt}
maxretry = ${mr}
findtime = ${ft}
backend  = auto

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = ${mr}
EOF
    ok "Конфиг записан: ${F2B_CONF}"
}

# Перезапускаем если запущен
_f2b_apply() {
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        systemctl reload-or-restart fail2ban 2>/dev/null
        ok "Fail2Ban перезапущен с новыми настройками"
    fi
}

# --- Установка ---
_f2b_install() {
    sep; echo -e "${BOLD}📦 Установка Fail2Ban${RESET}"; sep
    info "Обновляем пакеты и устанавливаем fail2ban..."
    apt-get update -qq
    apt-get install -y fail2ban >/dev/null 2>&1
    if ! command -v fail2ban-client &>/dev/null; then
        err "Ошибка установки fail2ban!"; return 1
    fi
    ok "Fail2Ban установлен"

    # Сохраняем текущие значения если конфиг уже есть, иначе дефолтные
    local bt=$(_f2b_get bantime);  bt=${bt:-3600}
    local mr=$(_f2b_get maxretry); mr=${mr:-5}
    local ft=$(_f2b_get findtime); ft=${ft:-600}
    _f2b_write_conf "$bt" "$mr" "$ft"

    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    ok "Fail2Ban запущен и добавлен в автозапуск"
    echo ""
    info "Активный jail — sshd (защита SSH от брутфорса)"
    info "Текущие настройки: bantime=${bt}с, maxretry=${mr}, findtime=${ft}с"
}

# --- Изменить время бана ---
_f2b_set_bantime() {
    local cur=$(_f2b_get bantime); cur=${cur:-3600}
    echo ""
    echo -e "  ${BOLD}⏱️  Время бана (bantime)${RESET}"
    echo -e "  Текущее: ${YELLOW}${cur}с${RESET} ($(_f2b_fmt $cur))"
    echo -e "  Сколько секунд IP остаётся заблокированным."
    echo -e "  ${BLUE}Примеры: 600 (10мин), 3600 (1ч), 86400 (1день)${RESET}"
    echo ""
    read -rp "  Введи bantime в секундах [Enter = оставить ${cur}]: " val
    [[ -z "$val" ]] && { info "Без изменений."; return; }
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then warn "Только цифры!"; return; fi
    _f2b_write_conf "$val" "$(_f2b_get maxretry)" "$(_f2b_get findtime)"
    _f2b_apply
    ok "bantime = ${val}с ($(_f2b_fmt $val))"
}

# --- Изменить кол-во попыток ---
_f2b_set_maxretry() {
    local cur=$(_f2b_get maxretry); cur=${cur:-5}
    echo ""
    echo -e "  ${BOLD}🔢 Попыток до бана (maxretry)${RESET}"
    echo -e "  Текущее: ${YELLOW}${cur}${RESET}"
    echo -e "  Сколько неудачных попыток входа разрешено за findtime."
    echo -e "  ${BLUE}Примеры: 3 (строго), 5 (стандарт), 10 (мягко)${RESET}"
    echo ""
    read -rp "  Введи maxretry [Enter = оставить ${cur}]: " val
    [[ -z "$val" ]] && { info "Без изменений."; return; }
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then warn "Только цифры!"; return; fi
    _f2b_write_conf "$(_f2b_get bantime)" "$val" "$(_f2b_get findtime)"
    _f2b_apply
    ok "maxretry = ${val}"
}

# --- Изменить окно поиска ---
_f2b_set_findtime() {
    local cur=$(_f2b_get findtime); cur=${cur:-600}
    echo ""
    echo -e "  ${BOLD}🔍 Окно поиска (findtime)${RESET}"
    echo -e "  Текущее: ${YELLOW}${cur}с${RESET} ($(_f2b_fmt $cur))"
    echo -e "  За какой период считаются неудачные попытки."
    echo -e "  ${BLUE}Примеры: 300 (5мин), 600 (10мин), 1800 (30мин)${RESET}"
    echo ""
    read -rp "  Введи findtime в секундах [Enter = оставить ${cur}]: " val
    [[ -z "$val" ]] && { info "Без изменений."; return; }
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then warn "Только цифры!"; return; fi
    _f2b_write_conf "$(_f2b_get bantime)" "$(_f2b_get maxretry)" "$val"
    _f2b_apply
    ok "findtime = ${val}с ($(_f2b_fmt $val))"
}

# --- Статус и заблокированные IP ---
_f2b_status() {
    sep; echo -e "${BOLD}📊 Статус Fail2Ban${RESET}"; sep
    if ! command -v fail2ban-client &>/dev/null; then
        err "Fail2Ban не установлен (пункт 1)"; return
    fi
    echo ""
    fail2ban-client status
    echo ""
    sep
    echo -e "${BOLD}  Детали jail sshd:${RESET}"
    sep
    fail2ban-client status sshd 2>/dev/null || warn "Jail sshd не активен"
}

# --- Удалить fail2ban ---
_f2b_remove() {
    echo ""
    warn "Это остановит и полностью удалит Fail2Ban!"
    read -rp "  Удалить fail2ban? [y/N]: " c
    [[ "$c" =~ ^[Yy]$ ]] || { info "Отменено."; return; }
    systemctl stop fail2ban 2>/dev/null || true
    systemctl disable fail2ban 2>/dev/null || true
    apt-get remove -y --purge fail2ban >/dev/null 2>&1
    rm -f "$F2B_CONF"
    ok "Fail2Ban удалён"
}

# --- Главная функция подменю Fail2Ban ---
fn_fail2ban() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}${BOLD}  ╔═════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}  ║   🛡️  Fail2Ban — Защита от брутфорса   ║${RESET}"
        echo -e "${CYAN}${BOLD}  ╚═════════════════════════════════════════╝${RESET}"
        echo ""

        # Показываем текущий статус и настройки
        if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
            local jails
            jails=$(fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}')
            ok "Fail2Ban запущен | Jail-ов активно: ${jails:-?}"
        elif command -v fail2ban-client &>/dev/null; then
            warn "Fail2Ban установлен, но не запущен"
        else
            warn "Fail2Ban не установлен"
        fi

        # Текущие значения из конфига
        local bt mr ft
        bt=$(_f2b_get bantime);  bt=${bt:-—}
        mr=$(_f2b_get maxretry); mr=${mr:-—}
        ft=$(_f2b_get findtime); ft=${ft:-—}

        echo ""
        echo -e "  ${BLUE}bantime:${RESET}  ${YELLOW}${bt}${RESET}$([ "$bt" != "—" ] && echo " ($(_f2b_fmt $bt))" || true)"
        echo -e "  ${BLUE}maxretry:${RESET} ${YELLOW}${mr}${RESET}"
        echo -e "  ${BLUE}findtime:${RESET} ${YELLOW}${ft}${RESET}$([ "$ft" != "—" ] && echo " ($(_f2b_fmt $ft))" || true)"
        echo ""
        sep
        echo -e "  ${GREEN}1)${RESET} 📦 Установить / переустановить Fail2Ban"
        echo -e "  ${GREEN}2)${RESET} ⏱️  Время бана           ${CYAN}(bantime)${RESET}"
        echo -e "  ${GREEN}3)${RESET} 🔢 Попыток до бана      ${CYAN}(maxretry)${RESET}"
        echo -e "  ${GREEN}4)${RESET} 🔍 Окно поиска          ${CYAN}(findtime)${RESET}"
        echo -e "  ${GREEN}5)${RESET} 📊 Статус и заблокированные IP"
        echo -e "  ${RED}6)${RESET} 🗑️  Удалить Fail2Ban"
        sep
        echo -e "  ${YELLOW} 0)${RESET} ← Назад в главное меню"
        echo ""

        read -rp "  Выбери пункт [0-6]: " f2b_choice
        echo ""

        case "$f2b_choice" in
            1) _f2b_install    ;;
            2) _f2b_set_bantime  ;;
            3) _f2b_set_maxretry ;;
            4) _f2b_set_findtime ;;
            5) _f2b_status     ;;
            6) _f2b_remove     ;;
            0) return          ;;
            *) warn "Неверный выбор '$f2b_choice'. Введи 0-6." ;;
        esac

        echo ""
        read -rp "  Нажми Enter для продолжения..." _
    done
}




# =============================================================================
# УДАЛЕНИЕ — СКРИПТ И ВСЁ УСТАНОВЛЕННОЕ
# =============================================================================
fn_uninstall() {
    sep; echo -e "${BOLD}🗑️  Удаление RemnaNode Installer${RESET}"; sep

    echo ""
    warn "Каждый компонент будет спрошен отдельно — ничего не удалится без подтверждения."
    echo ""

    RM_NODE=false; RM_CERTBOT=false; RM_F2B=false
    RM_CRON=false; RM_UFW=false;    RM_ALIAS=false

    # --- 1. RemnaNode ---
    if [[ -f "${REMNANODE_DIR}/docker-compose.yml" ]] || \
       docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode$"; then
        echo -e "  ${CYAN}[Нода]${RESET} Найдена нода в ${REMNANODE_DIR}"
        read -rp "  Остановить контейнер и удалить ${REMNANODE_DIR}? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && RM_NODE=true
    fi

    # --- 2. Certbot + сертификаты ---
    if [[ -d "${CERTBOT_DIR}" ]]; then
        echo ""
        echo -e "  ${CYAN}[SSL]${RESET} Найден Certbot в ${CERTBOT_DIR}"
        read -rp "  Удалить сертификаты и директорию ${CERTBOT_DIR}? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && RM_CERTBOT=true
    fi

    # --- 3. Fail2Ban ---
    if command -v fail2ban-client &>/dev/null; then
        echo ""
        echo -e "  ${CYAN}[Fail2Ban]${RESET} Найден fail2ban"
        read -rp "  Удалить fail2ban? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && RM_F2B=true
    fi

    # --- 4. Cron-задача для certbot ---
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        echo ""
        echo -e "  ${CYAN}[Cron]${RESET} Найдена задача автообновления сертификата"
        read -rp "  Удалить cron-задачу certbot renew? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && RM_CRON=true
    fi

    # --- 5. Правила UFW ---
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "443"; then
        echo ""
        echo -e "  ${CYAN}[UFW]${RESET} Найдены правила UFW для порта 443"
        read -rp "  Удалить правила UFW для 443 (и порта ноды)? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && RM_UFW=true
    fi

    # --- 6. Алиас rw-install ---
    echo ""
    echo -e "  ${CYAN}[Алиас]${RESET} Команда /usr/local/bin/rw-install"
    read -rp "  Удалить команду rw-install? [y/N]: " c
    [[ "$c" =~ ^[Yy]$ ]] && RM_ALIAS=true

    # Итоговое подтверждение
    echo ""; sep
    echo -e "  ${BOLD}Итоговый список действий:${RESET}"
    [[ "$RM_NODE"    == true ]] && echo -e "  ${RED}✗${RESET} Остановить и удалить RemnaNode (${REMNANODE_DIR})"
    [[ "$RM_CERTBOT" == true ]] && echo -e "  ${RED}✗${RESET} Удалить Certbot + сертификаты (${CERTBOT_DIR})"
    [[ "$RM_F2B"     == true ]] && echo -e "  ${RED}✗${RESET} Удалить Fail2Ban"
    [[ "$RM_CRON"    == true ]] && echo -e "  ${RED}✗${RESET} Удалить cron-задачу certbot"
    [[ "$RM_UFW"     == true ]] && echo -e "  ${RED}✗${RESET} Удалить правила UFW для 443"
    [[ "$RM_ALIAS"   == true ]] && echo -e "  ${RED}✗${RESET} Удалить команду rw-install"

    if [[ "$RM_NODE$RM_CERTBOT$RM_F2B$RM_CRON$RM_UFW$RM_ALIAS" == *"true"* ]]; then
        echo ""
        read -rp "  Всё верно? Запустить удаление? [y/N]: " final
        [[ "$final" =~ ^[Yy]$ ]] || { info "Отменено. Ничего не удалено."; return; }
    else
        info "Ничего не выбрано. Выход."; return
    fi

    sep; echo ""

    [[ "$RM_NODE" == true ]] && {
        info "Останавливаем и удаляем RemnaNode..."
        docker compose -f "${REMNANODE_DIR}/docker-compose.yml" down 2>/dev/null || true
        docker rm -f remnanode 2>/dev/null || true
        rm -rf "${REMNANODE_DIR}"
        ok "RemnaNode удалена"
    }
    [[ "$RM_CERTBOT" == true ]] && {
        info "Удаляем Certbot и сертификаты..."
        docker compose -f "${CERTBOT_DIR}/docker-compose.yml" down 2>/dev/null || true
        docker rm -f certbot 2>/dev/null || true
        rm -rf "${CERTBOT_DIR}"
        ok "Certbot и сертификаты удалены"
    }
    [[ "$RM_F2B" == true ]] && {
        info "Удаляем Fail2Ban..."
        _f2b_remove 2>/dev/null || {
            systemctl stop fail2ban 2>/dev/null; systemctl disable fail2ban 2>/dev/null
            apt-get remove -y --purge fail2ban >/dev/null 2>&1
        }
        ok "Fail2Ban удалён"
    }
    [[ "$RM_CRON" == true ]] && {
        info "Удаляем cron-задачу certbot..."
        ( crontab -l 2>/dev/null | grep -v "certbot renew" ) | crontab -
        ok "Cron-задача удалена"
    }
    [[ "$RM_UFW" == true ]] && {
        info "Удаляем правила UFW для 443..."
        ufw delete allow 443     2>/dev/null || true
        ufw delete allow 443/tcp 2>/dev/null || true
        ufw delete allow 443/udp 2>/dev/null || true
        NODE_PORT_RM=$(grep "NODE_PORT=" "${REMNANODE_DIR}/docker-compose.yml" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
        [[ -n "$NODE_PORT_RM" ]] && ufw delete allow "${NODE_PORT_RM}/tcp" 2>/dev/null || true
        ok "Правила UFW для 443 удалены"
        info "SSH и другие правила НЕ тронуты"
    }
    [[ "$RM_ALIAS" == true ]] && {
        info "Удаляем команду rw-install..."
        rm -f "/usr/local/bin/rw-install"
        ok "Команда rw-install удалена"
    }

    sep; ok "Удаление завершено!"
    echo ""
    info "Docker-образы НЕ удалялись. Очистить: docker image prune -a"
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

        # Показываем статус fail2ban если установлен
        if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo -e "  ${GREEN}🛡️  Fail2Ban: активен${RESET}"
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
        echo -e "  ${GREEN} 9)${RESET} 🛡️  Fail2Ban ${YELLOW}(защита от брутфорса → подменю)${RESET}"
        echo ""
        echo -e "  ${BOLD}Утилиты:${RESET}"
        echo -e "  ${GREEN}10)${RESET} 📥 Установить команду ${CYAN}rw-install${RESET} ${YELLOW}(запуск из любого места)${RESET}"
        echo ""
        echo -e "  ${BOLD}Удаление:${RESET}"
        echo -e "  ${RED}11)${RESET} 🗑️  Удалить скрипт и компоненты ${YELLOW}(с выбором что удалять)${RESET}"
        sep
        echo -e "  ${RED} 0)${RESET} ❌ Выход"
        echo ""

        read -rp "  Выбери пункт [0-11]: " choice
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
            9)  fn_fail2ban           ;;
            10) fn_install_alias      ;;
            11) fn_uninstall          ;;
            0)
                echo -e "${GREEN}Удачи! 👋${RESET}"
                exit 0 ;;
            *)
                warn "Неверный выбор: '$choice'. Введи 0-11." ;;
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
