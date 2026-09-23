# 🌐 RemnaNode Installer

> Интерактивный bash-скрипт для автоматической установки и управления нодой [Remnawave](https://github.com/remnawave) на Linux VPS.

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Docker-required-2496ED?style=flat-square&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-orange?style=flat-square&logo=linux&logoColor=white"/>
  <img src="https://img.shields.io/badge/version-1.2-blue?style=flat-square"/>
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
║      🌐 RemnaNode Installer  v1.2             ║
║      github.com/anqqu/remnanode-installer     ║
╚═══════════════════════════════════════════════╝

  ● RemnaNode: запущена
  🔒 SSL: node.example.com
  🛡️  Fail2Ban: активен

  Установка:
   1) 🐳 Установить ноду (без SSL)
   2) 🔒 Установить ноду + SSL (Certbot / Hysteria / XTLS)
   3) 🔐 Добавить SSL к существующей ноде (апгрейд)

  Управление нодой:
   4) 🔄 Обновить RemnaNode (docker compose pull + up)
   5) 📋 Показать логи ноды
   6) 🛑 Остановить ноду
   7) ▶️  Запустить/Перезапустить ноду

  Безопасность и защита:
   8) 🔥 Настроить UFW (фаервол: SSH + 443 + порт ноды)
   9) 🛡️  Fail2Ban (защита от брутфорса → подменю)

  Утилиты:
  10) 📥 Установить команду rw-install

  Удаление:
  11) 🗑️  Удалить скрипт и компоненты (с выбором что удалять)

   0) ❌ Выход
```

В шапке меню всегда показывается актуальный статус ноды, домен SSL-сертификата и статус Fail2Ban.

---

## ❓ Нужен ли мне SSL?

> **TL;DR:** Если у тебя уже работает нода (например, с VLESS+Reality) — SSL через Certbot **не нужен**. Выбирай пункт 1.

| Протокол | Нужен ли Certbot SSL? | Почему |
|----------|----------------------|--------|
| VLESS + Reality | ❌ Нет | Reality использует собственные ключи, сертификаты Let's Encrypt не нужны |
| Hysteria2 | ✅ Да | Требует валидный TLS-сертификат |
| VLESS + TLS | ✅ Да | Требует TLS-сертификат |
| XTLS-Vision + TLS | ✅ Да | Требует TLS-сертификат |

---

## 🐳 Режим 1 — Установка без SSL

Подходит для **VLESS+Reality** и любых нод, где SSL терминируется иначе.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директории `/opt/remnanode` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели Remnawave |
| 4 | Запись `docker-compose.yml` и запуск ноды |

Итоговый `docker-compose.yml`:

```yaml
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
      - NODE_PORT=<твой порт>
      - SECRET_KEY=<твой ключ>
```

---

## 🔒 Режим 2 — Установка с SSL (Certbot)

Подходит для протоколов, требующих TLS-сертификат на ноде: **Hysteria2**, **VLESS+TLS** и др.

> ⚠️ Домен должен уже указывать на IP сервера. Порт 80 должен быть свободен.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директории `/opt/remnanode` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели |
| 4 | Запрос домена и email для Let's Encrypt |
| 5 | Получение SSL-сертификата через Certbot standalone |
| 6 | Запись `docker-compose.yml` с `volumes` для сертификатов |
| 7 | Настройка cron для автообновления (28-е число каждого месяца) |
| 8 | Запуск ноды |

### Режим 3 — Апгрейд существующей ноды до SSL

Пункт **3** позволяет добавить SSL к уже работающей ноде без переустановки. Скрипт прочитает `NODE_PORT` и `SECRET_KEY` из текущего `docker-compose.yml`, получит сертификат и перезапустит ноду.

### Автообновление сертификата

Скрипт добавляет задачу в crontab — сертификат обновляется 28-го числа каждого месяца:

```
0 0 28 * * ufw allow 80/tcp && cd /opt/certbot && docker compose run --rm certbot renew; ufw delete allow 80/tcp
```

> Порт 80 временно открывается только на время проверки Let's Encrypt и сразу закрывается.

---

## 🔥 UFW — Пункт 8

Настройка фаервола с выбором протокола для порта 443:

| Вариант | Команда | Применение |
|---------|---------|------------|
| 1 — TCP+UDP (рекомендуется) | `ufw allow 443` | Универсально для всего |
| 2 — только TCP | `ufw allow 443/tcp` | VLESS, Reality, XTLS |
| 3 — только UDP | `ufw allow 443/udp` | Hysteria2 |

SSH и порт ноды открываются автоматически. Показывает итоговый список правил перед применением.

---

## 🛡️ Fail2Ban — Пункт 9

Защита SSH от брутфорса. После выбора пункта 9 открывается подменю:

```
  1) 📦 Установить / переустановить Fail2Ban
  2) ⏱️  Время бана           (bantime)
  3) 🔢 Попыток до бана      (maxretry)
  4) 🔍 Окно поиска          (findtime)
  5) 📊 Статус и заблокированные IP
  6) 🗑️  Удалить Fail2Ban
  0) ← Назад в главное меню
```

| Параметр | По умолчанию | Описание |
|----------|-------------|----------|
| `bantime` | 3600 (1 час) | Сколько секунд IP остаётся заблокированным |
| `maxretry` | 5 | Допустимое число неудачных попыток |
| `findtime` | 600 (10 мин) | Окно подсчёта неудачных попыток |

Конфиг хранится в `/etc/fail2ban/jail.local`.

---

## 📁 Структура на сервере

```
/opt/
├── remnanode/
│   └── docker-compose.yml     ← конфиг ноды
└── certbot/                   ← только при SSL (пункты 2 и 3)
    ├── docker-compose.yml
    ├── certs/                 ← сертификаты Let's Encrypt
    └── var-lib-letsencrypt/

/etc/fail2ban/
└── jail.local                 ← конфиг Fail2Ban (если установлен)

/usr/local/bin/
└── rw-install                 ← алиас для запуска скрипта
```

---

## ⚙️ Требования

| Требование | Подробности |
|------------|-------------|
| **ОС** | Debian 11/12, Ubuntu 22.04/24.04 LTS |
| **Виртуализация** | KVM |
| **Права** | root (`sudo`) |
| **Docker** | Устанавливается автоматически если отсутствует |
| **Домен** | Нужен только для SSL (пункты 2 и 3). Должен указывать на IP сервера |
| **Порт 80** | Нужен только для получения/обновления сертификата |

---

## 🔧 Управление нодой вручную

Если нужно управлять нодой без меню:

```bash
# Посмотреть логи
docker compose -f /opt/remnanode/docker-compose.yml logs -f -t

# Остановить
docker compose -f /opt/remnanode/docker-compose.yml down

# Запустить / перезапустить
docker compose -f /opt/remnanode/docker-compose.yml up -d

# Обновить до последней версии
docker compose -f /opt/remnanode/docker-compose.yml pull
docker compose -f /opt/remnanode/docker-compose.yml up -d
```

---

## 🛡️ Безопасность

- Скрипт работает **только от root**
- Защита от `curl | bash`: если stdin не является терминалом — скрипт скачивает себя во временный файл и перезапускается с `/dev/tty`, чтобы корректно читать ввод пользователя
- Порт 80 открывается **только на время** получения/обновления сертификата и сразу закрывается
- Сертификаты монтируются в ноду в режиме **read-only** (`:ro`)
- Fail2Ban защищает SSH от брутфорса, все настройки через удобное подменю

---

## 🤝 Связанные проекты

- [anqqu/optimizer](https://github.com/anqqu/optimizer) — VPS Network Optimizer: XanMod, BBRv3, sysctl-тюнинг и другие оптимизации для вашего сервера

---

## 📄 Лицензия

MIT License
