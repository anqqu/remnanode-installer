# 🌐 RemnaNode Installer

> Интерактивный bash-скрипт для автоматической установки и управления нодой [Remnawave](https://github.com/remnawave) на Linux VPS.

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Docker-required-2496ED?style=flat-square&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-orange?style=flat-square&logo=linux&logoColor=white"/>
  <img src="https://img.shields.io/badge/version-1.0-blue?style=flat-square"/>
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
║      🌐 RemnaNode Installer  v1.0             ║
║      github.com/anqqu/remnanode-installer     ║
╚═══════════════════════════════════════════════╝

  ● RemnaNode: не установлена

  Установка:
   1) 🐳 Установить ноду (без SSL)
   2) 🔒 Установить ноду + SSL (Certbot / Hysteria / XTLS)

  Управление нодой:
   3) 🔄 Обновить RemnaNode (docker compose pull + up)
   4) 📋 Показать логи ноды
   5) 🛑 Остановить ноду
   6) ▶️  Запустить/Перезапустить ноду

  Утилиты:
   7) 📥 Установить команду rw-install
   0) ❌ Выход
```

В шапке меню всегда показывается актуальный статус ноды и домен SSL-сертификата (если установлен).

---

## 🐳 Режим 1 — Установка без SSL

Подходит для работы за обратным прокси (например, если SSL терминируется на панели).

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

Подходит для протоколов, требующих TLS на ноде: **Hysteria2**, **XTLS-Reality**, **VLESS-TLS** и др.

Скрипт выполнит по шагам:

| Шаг | Действие |
|-----|----------|
| 1 | Проверка Docker → автоустановка если нет |
| 2 | Создание директории `/opt/remnanode` |
| 3 | Запрос `NODE_PORT` и `SECRET_KEY` из панели |
| 4 | Запрос домена и email для Let's Encrypt |
| 5 | Запись `docker-compose.yml` ноды с volume для сертификатов |
| 6 | Создание `docker-compose.yml` для Certbot в `/opt/certbot` |
| 7 | Получение SSL-сертификата через Certbot standalone |
| 8 | Настройка cron для автообновления сертификата |
| 9 | Запуск ноды |

### Автообновление сертификата

Скрипт автоматически добавляет задачу в crontab — сертификат обновляется 28-го числа каждого месяца:

```
0 0 28 * * ufw allow 80/tcp && cd /opt/certbot && docker compose run --rm certbot renew; ufw delete allow 80/tcp
```

> **Примечание:** Порт 80 на время проверки Let's Encrypt временно открывается и сразу закрывается после обновления. Если `ufw` не активен — команды ufw пропускаются.

Проверить что задача добавилась:

```bash
crontab -l
```

---

## 📁 Структура на сервере

```
/opt/
├── remnanode/
│   └── docker-compose.yml     ← конфиг ноды
└── certbot/                   ← только при режиме 2 (SSL)
    ├── docker-compose.yml
    ├── certs/                 ← сертификаты Let's Encrypt
    └── var-lib-letsencrypt/
```

---

## ⚙️ Требования

| Требование | Подробности |
|------------|-------------|
| **ОС** | Debian 11/12, Ubuntu 22.04/24.04 LTS |
| **Виртуализация** | KVM |
| **Права** | root (`sudo`) |
| **Docker** | Устанавливается автоматически если отсутствует |
| **Домен** | Нужен только для режима 2 (SSL). Должен указывать на IP сервера |
| **Порт 80** | Нужен только для получения и обновления сертификата |

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

---

## 🤝 Связанные проекты

- [anqqu/optimizer](https://github.com/anqqu/optimizer) — VPS Network Optimizer: XanMod, BBRv3, sysctl-тюнинг и другие оптимизации для вашего сервера

---

## 📄 Лицензия

MIT License
