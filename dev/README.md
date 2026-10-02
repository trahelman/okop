# Локальная тестовая среда

OpenWrt в Docker с исходниками okop, смонтированными напрямую из репозитория. Правки в `okop/files` и `luci-app-okop` видны в контейнере сразу, пересобирать пакеты не нужно.

## Что внутри

```
          wan 172.31.77.0/24                     lan 192.168.77.0/24
 интернет ── Docker ── router (OpenWrt 24.10) ── client (alpine)
                  │     172.31.77.2 / 192.168.77.1   192.168.77.10
                  └── proxy (sing-box, shadowsocks)
                        172.31.77.3:8388
```

- **router** — официальный образ `openwrt/rootfs` с procd, netifd, dnsmasq, fw4 и LuCI. Зависимости okop установлены в образе, сам okop смонтирован из `okop/files` и `luci-app-okop`.
- **client** — устройство в LAN. С него проверяем DNS и доступ в интернет так, как их видит пользователь.
- **proxy** — shadowsocks-сервер на стороне WAN, рабочий аутбаунд для роутера. Его можно остановить, чтобы сымитировать недоступный аутбаунд.

Перезапуск контейнера роутера ведёт себя как перезагрузка: `/tmp` очищается, `/etc` сохраняется.

Если git удалил и заново создал каталоги `okop/` или `luci-app-okop/` (например, при переключении на ветку, где их нет), роутер продолжит видеть старые пустые каталоги. Пересоздайте его командой `dev/okop-dev reset`.

## Требования

Docker с `docker compose`. Образ по умолчанию собран под arm64 (Apple Silicon). Для x86_64:

```
OPENWRT_IMAGE=openwrt/rootfs:x86-64-24.10.8 OPENWRT_PLATFORM=linux/amd64 dev/okop-dev up
```

## Использование

```
dev/okop-dev up                 # собрать и запустить
dev/okop-dev fixture proxy      # загрузить dev/fixtures/proxy.uci и перезапустить okop
dev/okop-dev i18n               # пересобрать русский перевод LuCI после правки .po
dev/okop-dev check              # DNS и HTTPS с клиента, состояние sing-box
dev/okop-dev logs               # логи okop и sing-box
dev/okop-dev reboot             # перезагрузить роутер
dev/okop-dev proxy down         # остановить прокси
dev/okop-dev sh                 # shell на роутере (sh client — на клиенте)
dev/okop-dev scenarios          # прогнать все сценарии
dev/okop-dev down               # остановить всё
```

LuCI: http://127.0.0.1:8080, пользователь `root` без пароля. Порт меняется переменной `DEV_LUCI_PORT`.

Интерфейс LuCI по умолчанию на русском: перевод приложения компилируется из `luci-app-okop/po/ru/okop.po` при `up` и `reset` (утилита `po2lmo` из LuCI, сервис `po2lmo` в `compose.yml`). После правки перевода выполните `dev/okop-dev i18n`. Язык меняется переменной `DEV_LUCI_LANG`, например `DEV_LUCI_LANG=en`.

## Фикстуры и сценарии

- `fixtures/*.uci` — готовые `/etc/config/okop`. Загружаются командой `fixture <имя>`. При первом старте роутера загружается фикстура из переменной `DEV_FIXTURE`, по умолчанию `proxy`: okop сразу работает через тестовый прокси и виден в меню LuCI. Чтобы поднять роутер без конфига okop, запустите `DEV_FIXTURE= dev/okop-dev up`.
- `scenarios/*.sh` — проверки поведения: выставляют состояние, перезагружают роутер и проверяют результат с клиента. Код возврата 0 означает, что сценарий пройден.

| Сценарий | Что проверяет |
|---|---|
| `outbound-down-on-boot` | Роутер загружается, пока прокси для скачивания списков недоступен |
| `traffic-through-proxy` | Реальный трафик через fake-IP: tproxy, sing-box и прокси-сервер, а не только DNS |
| `vpn-interface-missing` | Списки скачиваются через VPN-секцию, интерфейса которой нет |
| `start-without-stop` | Повторный старт без остановки (краш, OOM): пользовательские списки на месте, правила nftables не дублируются |
| `sing-box-crash-at-runtime` | sing-box останавливается во время работы и потом возвращается |
| `no-cached-lists-on-boot` | Первый запуск без скачанных списков при недоступном GitHub, затем списки появляются |
| `cli-returns-promptly` | `okop reload` и `okop restart` через пайп (как по SSH без терминала) не ждут фоновых задач |
| `damaged-cached-list` | Сохранённый список повреждён, GitHub недоступен |
| `direct-download-fallback` | Прокси для скачивания списков не работает: прямое скачивание только при включённой настройке |
| `dont-touch-dhcp-manual-setup` | «Не трогать мой DHCP!» с dnsmasq, настроенным на sing-box вручную: okop не трогает эти настройки |
| `dhcp-user-settings-preserved` | Ручные перенаправления DNS и другие настройки dnsmasq работают при включённом okop и точно восстанавливаются после его остановки |
| `dnsmasq-restored-when-disabled` | «Не трогать мой DHCP!» включили при работающем okop или okop выключили кнопкой: настройки dnsmasq возвращаются |
| `reload-keeps-lists-routed` | После `reload` dnsmasq снова направляет запросы в sing-box, домены из списков маршрутизируются |
| `diagnostics-mask-secrets` | Вывод диагностики не содержит ключа Clash API, путей DoH, логинов и паролей прокси и WAN |
| `dns-guard-detects-dead-upstream` | DNS-сервер sing-box недоступен: защита DNS возвращает dnsmasq на обычные серверы |
| `failed-start-leaves-no-blackhole` | Неудачный запуск снимает перехват и возвращает dnsmasq |
| `shutdown-and-disabled-upgrade` | При выключении роутера okop возвращает dnsmasq; обновление пакета не запускает выключенный okop |
| `stop-during-start` | `stop` во время `start` и `start`, убитый сигналом TERM: okop остаётся выключенным целиком, без перехвата |
| `singbox-fails-after-start` | Конфиг проходит `sing-box check`, но sing-box не может запуститься (порт занят): старт откатывается |
| `init-reload-then-stop` | `service okop reload` (как при мониторинге интерфейсов), затем stop, start и restart: фоновые задачи не держат блокировку procd |
| `lists-from-cache-on-boot` | После перезагрузки без доступа к GitHub подсети и текстовые списки применяются из сохранённых копий, обновление повторяется |
| `list-update-repeated` | Повторные и одновременные обновления списков: правило Discord не дублируется, обновления не идут параллельно |
| `mixed-remote-subnet-list` | Подсети извлекаются из rule-set, где правила с `ip_cidr` смешаны с другими |
| `proxy-url-credentials` | Пароли и логины из ссылок на прокси попадают в конфиг без искажений |
| `podkop-migration` | Перенос конфига Podkop: один раз, без перезаписи при обновлениях; конфиг Podkop до 0.7 не трогает настройки okop |
| `proxy-url-defaults` | trojan без `security=`, ss в base64url, ss с `plugin=`: outbound собирается правильно |
| `proxy-url-transport` | Транспорт из ссылки (ws, grpc, httpupgrade) попадает в конфиг |
