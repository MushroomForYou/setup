# 3X-UI Auto-Installer

Автоматический установщик панели 3X-UI с поддержкой SSL сертификатов Let's Encrypt и настройкой Nginx в качестве reverse proxy.

## Возможности

- Автоматическая установка и настройка 3X-UI панели
- Получение SSL сертификатов через Let's Encrypt (acme.sh)
- Настройка Nginx как reverse proxy с SSL offloading
- Настройка UFW firewall
- Автоматическое обновление SSL сертификатов
- Красивый вывод с прогрессом установки

## Требования

- Ubuntu/Debian сервер
- Root доступ
- Домен с A-записью, указывающей на IP сервера
- Открытые порты: 22 (SSH), 80 (HTTP), 443 (HTTPS)

## Быстрый старт

### Удаленная установка через curl

```bash
bash <(curl -sL https://raw.githubusercontent.com/MushroomForYou/setup/main/install.sh) \
  --domain your.domain.com \
  --ip 1.2.3.4 \
  --email admin@domain.com
```

### Локальная установка

```bash
git clone https://github.com/MushroomForYou/setup.git
cd setup
sudo bash install.sh --domain your.domain.com --ip 1.2.3.4 --email admin@domain.com
```

## Параметры CLI

### Обязательные параметры

| Параметр | Описание | Пример |
|----------|----------|--------|
| `--domain` | Доменное имя сервера | `vpn.example.com` |
| `--ip` | IP адрес сервера | `1.2.3.4` |
| `--email` | Email для Let's Encrypt | `admin@example.com` |

### Опциональные параметры

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `--username` | `admin` | Имя пользователя админки |
| `--password` | `admin` | Пароль админки |

### Дополнительные флаги

| Флаг | Описание |
|------|----------|
| `-h, --help` | Показать справку |
| `-q, --quiet` | Тихий режим (только ошибки) |
| `-v, --verbose` | Подробный вывод (debug) |

## Примеры

### Минимальная установка

```bash
bash <(curl -sL https://raw.githubusercontent.com/MushroomForYou/setup/main/install.sh) \
  --domain vpn.example.com \
  --ip 192.168.1.100 \
  --email admin@example.com
```

### С кастомными учетными данными

```bash
bash <(curl -sL https://raw.githubusercontent.com/MushroomForYou/setup/main/install.sh) \
  --domain vpn.example.com \
  --ip 192.168.1.100 \
  --email admin@example.com \
  --username myuser \
  --password mysecretpass
```

### Тихий режим (для автоматизации)

```bash
bash <(curl -sL https://raw.githubusercontent.com/MushroomForYou/setup/main/install.sh) \
  --domain vpn.example.com \
  --ip 192.168.1.100 \
  --email admin@example.com \
  --quiet
```

## Структура проекта

```
setup/
├── install.sh          # Главный скрипт запуска
├── README.md           # Документация
└── lib/
    ├── colors.sh       # Цвета и иконки
    ├── logger.sh       # Функции логирования
    ├── cli.sh          # Парсинг аргументов
    ├── validators.sh   # Валидация параметров
    ├── system.sh       # Системные функции
    ├── ssl.sh          # Работа с SSL сертификатами
    ├── nginx.sh        # Конфигурация Nginx
    └── panel.sh        # Установка 3X-UI
```

## Что делает скрипт

1. Обновляет системные пакеты
2. Устанавливает зависимости (curl, socat, nginx, ufw, cron)
3. Настраивает UFW firewall
4. Проверяет DNS резолвинг домена
5. Устанавливает acme.sh для SSL сертификатов
6. Устанавливает 3X-UI панель
7. Получает SSL сертификат Let's Encrypt
8. Настраивает Nginx как reverse proxy
9. Запускает все сервисы
10. Выводит информацию для доступа

## Полезные команды

После установки вы можете использовать:

```bash
x-ui              # Меню управления панелью
x-ui status       # Статус панели
x-ui settings     # Просмотр учетных данных
x-ui update       # Обновление панели
x-ui restart      # Перезапуск панели
```

## Устранение неполадок

### SSL сертификат не выдается

1. Проверьте, что A-запись домена указывает на правильный IP
2. Убедитесь, что порт 80 доступен из интернета
3. Если используете Cloudflare, отключите оранжевое облако (proxy)

### Панель недоступна

1. Проверьте статус: `x-ui status`
2. Проверьте порты: `ufw status`
3. Проверьте логи: `journalctl -u x-ui -f`

### Nginx ошибки

1. Проверьте конфигурацию: `nginx -t`
2. Проверьте логи: `tail -f /var/log/nginx/error.log`

## Безопасность

- Меняйте дефолтный пароль `admin/admin` на сложный
- Используйте нестандартный username
- Регулярно обновляйте панель: `x-ui update`
- Мониторьте логи доступа

## Автор

MushroomForYou
