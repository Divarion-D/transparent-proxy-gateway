# 🌐 Прозрачный шлюз с SOCKS-проксированием

Шлюз для перенаправления трафика через SOCKS-прокси на основе списка доменов. Решение для организации безопасного доступа и мониторинга сетевой активности. 🔒

## ✨ Особенности

- 🚀 Автоматическое перенаправление трафика для заданных доменов/IP через прокси  
- 🔌 Поддержка различных типов WAN-подключений:
  - 🏠 DHCP
  - 🌍 Статический IP
  - 📡 PPPoE
  - 🔗 L2TP
- 🔄 Динамическое обновление IP-адресов доменов
- 🛡️ Интеграция с SOCKS5 прокси
- 📜 Логирование всех операций
- 🔧 Модульная архитектура с поддержкой параметров командной строки
- ⏰ Автоматическое обновление адресов каждые 3 часа

## 🖥️ Требования

- Сервер/ПК с Linux (рекомендуется Ubuntu 22.04+)
- Два сетевых интерфейса (LAN/WAN)

## 📡 Архитектура системы

```mermaid
graph LR
    A[Локальная сеть] --> B(LAN Интерфейс)
    B --> C{Проверка правил}
    C -->|Совпадение| D[SOCKS Прокси]
    C -->|Нет совпадения| E[Прямое подключение]
    D --> F[WAN Интерфейс]
    E --> F
```

## 🚀 Быстрый старт

### 📥 Установка
1. Клонируйте репозиторий:
```bash
git clone https://github.com/Divarion-D/transparent-proxy-gateway.git
cd transparent-proxy-gateway
```

2. Запустите установку:
```bash
chmod +x proxy.sh
sudo ./proxy.sh --install
```

3. Следуйте инструкциям на экране:
   - 🖧 Выберите LAN и WAN интерфейсы
   - 🔌 Настройте тип WAN-подключения

### ⚙️ Конфигурация

* ⚠️ Каждая новая запись должна начинатся с новой строки

1. Добавьте домены в `config/domains.txt`:
```bash
sudo nano config/domains.txt
```

2. Добавьте IP в `config/ips.txt`:
```bash
sudo nano config/ips.txt
```

3. Настройте прокси в `config/redsocks.conf`:
```bash
sudo nano config/redsocks.conf
```

```ini
redsocks {
    local_ip = 0.0.0.0; # Не изменять
    local_port = 12345; # Не изменять
    ip = proxy_ip; # Адрес SOCKS-прокси
    port = proxy_port; # Порт прокси
    # login = proxy_login; # Имя пользователя прокси
    # password = proxy_password; # Пароль прокси
    type = socks5;
}
```

Раскомментируйте строки с логином и паролем если требуется аутентификация для прокси:
```
login = proxy_login;
password = proxy_password;
```

4. Примените изменения:
```bash
sudo ./proxy.sh --update-ips
sudo ./proxy.sh --restart-redsocks
```

## 🛠️ Использование

### 🔑 Основные команды

| Команда                     | Описание                          |
|-----------------------------|-----------------------------------|
| `sudo ./proxy.sh --install` | 🚀 Полная установка системы       |
| `sudo ./proxy.sh --uninstall` | 🚀 Полное удаление шлюза        |
| `sudo ./proxy.sh --wan`     | 🔄 Перенастройка WAN-подключения  |
| `sudo ./proxy.sh --update-ips`  | 🌍 Принудительное обновление IP  |
| `sudo ./proxy.sh --restart-redsocks`    | 🌍 Перезапуск readsocks  |
| `sudo ./proxy.sh --help`    | 📖 Показать справку               |

### 📌 Примеры

1. 🔄 Обновить список IP-адресов:
```bash
sudo ./proxy.sh --update-ips
```

2. ⚙️ Изменить тип WAN-подключения:
```bash
sudo ./proxy.sh --wan
```

3. 🔍 Проверить статус сервисов:
```bash
systemctl status redsocks
```

4. 📋 Проверить добавленные IP-адреса доменов:
```bash
ipset list proxy_domains
```

5. 📋 Проверить созданы ли правила роутинга:
```bash
sudo nft list ruleset
```

## 📌 Добавление правил роутинга

Правила роутинга можно взять отсюда [RockBlack-VPN](https://github.com/RockBlack-VPN/ip-address/tree/main/Global)

1. Выбираем сайт который нам нужен
2. Открываем файл с правилами.
3. Содержимое файла будет выглядеть примерно так:
```
route ADD 23.32.0.0 MASK 255.224.0.0 0.0.0.0
route ADD 47.236.0.0 MASK 255.252.0.0 0.0.0.0
route ADD 47.235.0.0 MASK 255.255.0.0 0.0.0.0
```
4. Нужно удалить все кроме самого IP адреса чтобы выглядело так:
```
23.32.0.0
47.236.0.0
47.235.0.0
```
5. Сохраниете эти правила в текстовый файл и положите его в папку routing
6. Выполните команду для обновления правил роутинга
```
sudo ./proxy.sh --update-ips
```

## 📂 Структура проекта

```
/transparent-proxy-gateway/
├── proxy.sh              # 🖥️ Основной скрипт
├── config.sh             # 🖥️ Главный файл конфигурации
├── config/
│   ├── redsocks.conf     # ⚙️ Конфигурация прокси
│   ├── domains.txt       # 📜 Список ваших доменов для перенаправления
│   ├── ips.txt           # 📜 Список ваших IP для перенаправления
│   └── cache.txt         # 📜 Кеш с обработаными IP для перенаправления (не трогать генерируется автоматически)
├── scripts/
│   └── update_ips.sh     # 🔄 Скрипт обновления IP
├── routing/              # 📜 Файлы с ip адресами для сайтов
└── logs/                 # 🗂️ Директория логов
```

## 📊 Логирование

Все операции записываются в папку `logs/`. Для мониторинга в реальном времени:

```bash
tail -f logs/redsocks/redsocks.log
```

## ❓ Частые вопросы

### ❌ Нет интернет-доступа после настройки
1. 🔌 Проверьте физическое подключение кабелей
2. ⚙️ Убедитесь в правильности выбора WAN-интерфейса
3. 🕵️‍♂️ Проверьте настройки прокси в `redsocks.conf`

### 🚫 Домены не перенаправляются
1. 📝 Убедитесь, что домены добавлены в `domains.txt`
2. 🔄 Выполните принудительное обновление IP:
```bash
sudo ./proxy.sh --update-ips
```

### ⚠️ Ошибки в конфигурации
Проверьте синтаксис файлов:
```bash
redsocks --test -c config/redsocks.conf
```

## 📜 Лицензия

AGPL License. Подробнее см. в файле [LICENSE](LICENSE).

---

**💻 Разработано**: Divarion-D  
**📂 Репозиторий**: https://github.com/Divarion-D/transparent-proxy-gateway

