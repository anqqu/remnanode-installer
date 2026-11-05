# 🌐 RemnaNode Installer

> Интерактивный bash-скрипт для автоматической установки и управления нодой [Remnawave](https://github.com/remnawave) на Linux VPS.

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Docker-required-2496ED?style=flat-square&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-orange?style=flat-square&logo=linux&logoColor=white"/>
  <img src="https://img.shields.io/badge/version-1.3-blue?style=flat-square"/>
</p>

---

## ⚡ Быстрый старт

```bash
sudo curl -fsSL https://raw.githubusercontent.com/anqqu/remnanode-installer/main/node-installer.sh | sudo bash
```

После первого запуска команда `rw-install` будет доступна из любого места:

```bash
rw-install
```

---

## 📋 Меню

```
╔═══════════════════════════════════════════════╗
║      🌐 RemnaNode Installer  v1.3             ║
║      github.com/anqqu/remnanode-installer     ║
╚═══════════════════════════════════════════════╝

  ● RemnaNode: запущена
  ● Caddy (HTTPS/XHTTP): запущен
  🔒 SSL: node.example.com
  🛡️  Fail2Ban: активен

  Установка:
   1) 🐳 Установить ноду (без SSL)
   2) 🔒 Установить ноду + SSL (Certbot / Hysteria / XTLS)
   3) 🌐 Установить ноду + Caddy (XHTTP / авто-TLS / сайт-заглушка) ← хит
   4) 🔐 Добавить SSL к существующей ноде (апгрейд)

  Управление нодой:
   5) 🔄 Обновить RemnaNode / Caddy
   6) 📋 Показать логи (RemnaNode / Caddy)
   7) 🛑 Остановить ноду и Caddy
   8) ▶️  Запустить/Перезапустить ноду и Caddy

  Безопасность и защита:
   9) 🔥 Настроить UFW (фаервол: SSH + 443 + порт ноды)
  10) 🛡️  Fail2Ban (защита от брутфорса → подменю)

  Утилиты:
  11) 📥 Установить команду rw-install

  Удаление:
  12) 🗑️  Удалить скрипт и компоненты (с выбором что удалять)

   0) ❌ Выход
```

В шапке меню всегда показывается актуальный статус ноды, статус Caddy, домен активного SSL-сертификата и статус Fail2Ban.

---

## ❓ Какой режим мне выбрать?

| Протокол | Какой режим выбрать? | Описание |
|----------|----------------------|----------|
| **VLESS + XHTTP** | **🌐 Пункт 3 (Caddy)** | **Рекомендуется!** Caddy сам выпускает и продлевает TLS через 443 порт (без 80 порта), маскирует сервер сайтом-заглушкой и проксирует трафик в Xray |
| **VLESS + Reality** | 🐳 Пункт 1 (Без SSL) | Reality использует собственные публичные ключи, SSL-сертификаты на сервере не нужны |
| **Hysteria2** | 🔒 Пункт 2 (Certbot) | Требует валидный TLS-сертификат, который монтируется напрямую в контейнер ноды |
| **VLESS + TLS / Vision** | 🔒 Пункт 2 (Certbot) | Требует TLS-сертификат напрямую в контейнере ноды |

---

## 🐳 Режим 1 — Установка без SSL

Подходит для **VLESS+Reality** и любых конфигураций, где SSL терминируется на внешнем балансировщике.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директории `/opt/remnanode` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели Remnawave |
| 4 | Запись `docker-compose.yml` и запуск ноды |

---

## 🔒 Режим 2 — Установка с SSL (Certbot)

Подходит для протоколов, требующих файлы сертификатов прямо в ноде: **Hysteria2**, **VLESS+TLS** и др.

> ⚠️ Домен должен указывать на IP сервера. Порт 80 временно используется Certbot standalone для проверки Let's Encrypt.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директории `/opt/remnanode` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели |
| 4 | Запрос домена и email для Let's Encrypt |
| 5 | Получение SSL-сертификата через Certbot standalone |
| 6 | Запись `docker-compose.yml` с монтированием сертификатов (`/opt/certbot/certs:/etc/letsencrypt:ro`) |
| 7 | Настройка задачи в cron для автообновления 28-го числа каждого месяца |
| 8 | Запуск ноды с сертификатами |

---

## 🌐 Режим 3 — Установка с Caddy (XHTTP + Авто-TLS + Заглушка)

**Лучший выбор маскировки под настоящий веб-сайт!**

В этом режиме Caddy работает на порту 443 во внешнем интернете, автоматически получает бесплатный сертификат Let's Encrypt / ZeroSSL, отдает красивый сайт-заглушку и незаметно проксирует запросы по секретному пути в локальный Xray на порт `127.0.0.1:10085`.

### Особенности режима:
- **Порт 80 НЕ требуется:** Caddy выпускает сертификаты по протоколу **TLS-ALPN-01 напрямую через 443 порт**. Порт 80 открывать не нужно!
- **Совместимость с Hysteria2:** В Caddy автоматически прописана директива `auto_https disable_h3`, поэтому порт **443/UDP свободен** и готов для параллельной работы Hysteria2!
- **Сайт-заглушка:** Автоматически создается в `/opt/caddy/site/index.html`. При переходе по твоему домену в браузере открывается реальная страница статуса сервиса.
- **Чистый JSON без сертификатов в Xray:** В инбаунде Xray указывается `"security": "none"`, файлы ключей вписывать не нужно.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директорий `/opt/remnanode` и `/opt/caddy/site` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели Remnawave |
| 4 | Запрос домена, секретного пути (по умолчанию `/api/v1/telemetry`) и внутреннего порта Xray (`10085`) |
| 5 | Создание страницы-заглушки и `Caddyfile` |
| 6 | Создание `docker-compose.yml` для Caddy и для RemnaNode (`network_mode: host`) |
| 7 | Запуск Caddy и RemnaNode, вывод итоговой памятки для RemnaWave |

---

## 🔐 Режим 4 — Апгрейд существующей ноды до SSL (Certbot)

Пункт **4** позволяет добавить SSL через Certbot к уже работающей ноде без ручной переустановки. Скрипт считывает параметры текущей ноды, запрашивает сертификат и перезапускает контейнер.

---

## 🔥 UFW (Фаервол) — Пункт 9

Настройка фаервола сервера с защитой от случайной блокировки SSH:

| Вариант | Команда | Применение |
|---------|---------|------------|
| 1 — TCP+UDP (рекомендуется) | `ufw allow 443` | Универсально для Caddy (TCP) и Hysteria2 (UDP) |
| 2 — только TCP | `ufw allow 443/tcp` | Для VLESS, XHTTP, Reality |
| 3 — только UDP | `ufw allow 443/udp` | Для Hysteria2 |

SSH и порт ноды открываются автоматически. Для Caddy порт 80 открывать не требуется.

---

## 🛡️ Fail2Ban — Пункт 10

Защита SSH от подбора паролей (брутфорса) с интерактивным подменю:

```
  1) 📦 Установить / переустановить Fail2Ban
  2) ⏱️  Время бана           (bantime)
  3) 🔢 Попыток до бана      (maxretry)
  4) 🔍 Окно поиска          (findtime)
  5) 📊 Статус и заблокированные IP
  6) 🗑️  Удалить Fail2Ban
  0) ← Назад в главное меню
```

---

## 📁 Структура на сервере

```
/opt/
├── remnanode/
│   └── docker-compose.yml     ← конфиг ноды RemnaWave
├── caddy/                     ← только при Caddy (пункт 3)
│   ├── Caddyfile              ← конфиг реверс-прокси
│   ├── docker-compose.yml
│   └── site/
│       └── index.html         ← сайт-заглушка
└── certbot/                   ← только при Certbot SSL (пункты 2 и 4)
    ├── docker-compose.yml
    ├── certs/                 ← сертификаты Let's Encrypt
    └── var-lib-letsencrypt/

/etc/fail2ban/
└── jail.local                 ← конфиг Fail2Ban (если установлен)

/usr/local/bin/
└── rw-install                 ← алиас для быстрого запуска скрипта
```

---

## ⚙️ Требования

| Требование | Подробности |
|------------|-------------|
| **ОС** | Debian 11/12, Ubuntu 22.04/24.04 LTS |
| **Виртуализация** | KVM |
| **Права** | root (`sudo`) |
| **Docker** | Устанавливается автоматически если отсутствует |
| **Домен** | Нужен для SSL (пункты 2, 3 и 4). Должен указывать на IP сервера |
| **Порт 80** | Нужен **только** для Certbot (пункты 2 и 4). Для Caddy (пункт 3) порт 80 **НЕ требуется** |

---

## 🔧 Управление вручную через Docker Compose

```bash
# Логи ноды
docker compose -f /opt/remnanode/docker-compose.yml logs -f -t

# Логи Caddy
docker compose -f /opt/caddy/docker-compose.yml logs -f -t

# Перезапуск ноды
docker compose -f /opt/remnanode/docker-compose.yml restart

# Перезапуск Caddy
docker compose -f /opt/caddy/docker-compose.yml restart
```

---

## 📄 Лицензия

MIT License © [anqqu](https://github.com/anqqu)
