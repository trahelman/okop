# Туннели для секций VPN

Секция VPN отправляет трафик в сетевой интерфейс туннеля. Сам туннель настраивается средствами OpenWrt, Okop его не создаёт. Ниже — то, что важно при настройке туннеля именно для Okop.

## Общие правила

- **Зона firewall и перенаправление из LAN не нужны.** Okop сам направляет в интерфейс нужный трафик.
- **Не отправляйте весь трафик в туннель.**
  - Для WireGuard и AmneziaWG снимите у пира галочку **Route Allowed IPs** (`route_allowed_ips '0'`).
  - Для OpenVPN уберите из конфига `redirect-gateway` или добавьте `pull-filter ignore redirect-gateway`.
- **Уберите DNS-серверы туннеля** в *Дополнительных настройках → Использовать свои DNS-серверы*, чтобы туннель не подменял DNS роутера.
- **Persistent Keep Alive = 25** для WireGuard и AmneziaWG. Без него туннель за NAT может не подниматься.

Как проверить туннель:

- **WireGuard и AmneziaWG:** счётчики RX и TX ненулевые, последнее рукопожатие было меньше двух минут назад.
- **Любой туннель:** `ping -I wg0 openwrt.org`, внешний адрес — `curl --interface wg0 ifconfig.me`.

## WireGuard

```
opkg update && opkg install wireguard-tools luci-proto-wireguard      # 24.10
apk update && apk add wireguard-tools luci-proto-wireguard            # 25.12
```

Интерфейс создаётся в **Сеть → Интерфейсы → Добавить**, протокол WireGuard. Конфиг можно импортировать кнопкой загрузки конфигурации. Состояние туннеля: `wg show`.

## AmneziaWG

Пакетов нет в репозиториях OpenWrt. Их можно установить скриптом стороннего проекта [awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt): на вопрос о настройке интерфейса ответьте «нет» и настройте его сами по правилам выше. Если интерфейс настроил скрипт, проверьте галочку Route Allowed IPs.

Параметры обфускации хранятся в опциях интерфейса `awg_jc`, `awg_jmin`, `awg_jmax`, `awg_s1`, `awg_s2`, `awg_h1`…`awg_h4`. Состояние: `amneziawg show`.

## OpenVPN

```
opkg update && opkg install openvpn-openssl luci-app-openvpn       # 24.10
apk update && apk add openvpn-openssl luci-app-openvpn             # 25.12
```

Загрузите `.ovpn` в **VPN → OpenVPN** или положите конфиг в `/etc/openvpn/` с расширением `.conf`. Интерфейс по умолчанию — `tun0`. Если в `ip route` появился маршрут `0.0.0.0/1 via … dev tun0`, в туннель уходит весь трафик: уберите `redirect-gateway`.

## OpenConnect

```
opkg update && opkg install openconnect luci-proto-openconnect     # 24.10
apk update && apk add openconnect luci-proto-openconnect           # 25.12
```

У интерфейса укажите `option defaultroute '0'`. Интерфейс в системе называется `vpn-<имя>`, например `vpn-oc0`. Логи: `logread -f -e openconnect`.

## Cloudflare WARP и списки Cloudflare

Если WARP подключён по WireGuard, а список `cloudflare` в другой секции идёт через другой туннель, трафик самого WARP попадает в этот список, и получается петля. Укажите у интерфейса WARP **Firewall Mark** `0x00200000`: трафик с этой меткой Okop не перехватывает.
