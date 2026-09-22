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

        echo ""
        sep
        echo -e "  ${BOLD}Установка:${RESET}"
        echo -e "  ${GREEN} 1)${RESET} 🐳 Установить ноду ${YELLOW}(без SSL)${RESET}"
        echo -e "  ${GREEN} 2)${RESET} 🔒 Установить ноду + SSL ${YELLOW}(Certbot / Hysteria / XTLS)${RESET}"
        echo ""
        echo -e "  ${BOLD}Управление нодой:${RESET}"
        echo -e "  ${GREEN} 3)${RESET} 🔄 Обновить RemnaNode ${YELLOW}(docker compose pull + up)${RESET}"
        echo -e "  ${GREEN} 4)${RESET} 📋 Показать логи ноды"
        echo -e "  ${GREEN} 5)${RESET} 🛑 Остановить ноду"
        echo -e "  ${GREEN} 6)${RESET} ▶️  Запустить/Перезапустить ноду"
        echo ""
        echo -e "  ${BOLD}Утилиты:${RESET}"
        echo -e "  ${GREEN} 7)${RESET} 📥 Установить команду ${CYAN}rw-install${RESET} ${YELLOW}(запуск из любого места)${RESET}"
        sep
        echo -e "  ${RED} 0)${RESET} ❌ Выход"
        echo ""

        read -rp "  Выбери пункт [0-7]: " choice
        echo ""

        case "$choice" in
            1)  fn_install_node     ;;
            2)  fn_install_node_ssl ;;
            3)  fn_update_node      ;;
            4)  fn_logs             ;;
            5)  fn_stop             ;;
            6)  fn_start            ;;
            7)  fn_install_alias    ;;
            0)
                echo -e "${GREEN}Удачи! 👋${RESET}"
                exit 0 ;;
            *)
                warn "Неверный выбор: '$choice'. Введи 0-7." ;;
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
