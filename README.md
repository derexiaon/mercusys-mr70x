# OpenWrt 25.12 + Xray + pbr для Mercusys MR70X v1

Сборка **OpenWrt 25.12.5** для **Mercusys MR70X v1** (MT7621, 16 МБ флеш, 128 МБ ОЗУ),
в которую уже встроены:

- **Xray-core 26.3.27** (облегчённая сборка из исходников) — клиент VLESS
  (REALITY / TLS, XTLS Vision, XHTTP, WebSocket, HTTPUpgrade);
- **pbr** + **luci-app-pbr** — маршрутизация по спискам доменов и подсетей;
- **dnsmasq-full** с nftset — чтобы pbr мог работать с доменами;
- списки заблокированных ресурсов [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains)
  («Russia inside» + подсети Telegram, Meta, Twitter, Discord), обновляются каждый день;
- страница **LuCI → Службы → Xray**: вставляете `vless://` ссылку — и всё работает;
- LuCI на русском, часовой пояс MSK.

В туннель уходит **только** трафик к ресурсам из списков, остальное идёт напрямую
через провайдера (как в AntiZapret).

> **Статус.** Сборка, размер образа, генерация и проверка конфигов Xray
> автоматически проверяются в CI (qemu-chroot собранного rootfs). На живом
> MR70X прошивка пока не проверялась — держите под рукой аварийное восстановление
> (см. ниже) и сообщайте о проблемах в Issues.

## Почему именно так

Полный Xray для MIPS весит 34 МБ (6,8 МБ в xz), а образ OpenWrt с LuCI, pbr и
dnsmasq-full — уже 9,2 МБ при лимите прошивки 15,4 МБ. Вместе они не помещаются
(и на настройки места не остаётся). Поэтому:

| Решение | Почему |
| --- | --- |
| Xray собирается из исходников с урезанным набором протоколов (`xray-slim/`) | убраны gRPC, WireGuard, Hysteria/QUIC-прокси, VMess, Trojan, Shadowsocks, API, TOML/YAML — всё, что не нужно клиенту VLESS на роутере |
| Нет `geoip.dat` / `geosite.dat` | они весят мегабайты; маршрутизацию по доменам делает pbr + dnsmasq nftset |
| Списки скачиваются в ОЗУ при старте pbr | во флеш ничего не пишется |
| Xray создаёт TUN-интерфейс `xray0` | pbr работает с ним как с обычным VPN-интерфейсом, всё настраивается в LuCI |
| `GOMEMLIMIT=40MiB`, `GOGC=50` | Xray не съедает всю память роутера |
| Весь DNS идёт через туннель (dnsmasq → Xray → 1.1.1.1) | провайдер не может подменить ответы для заблокированных доменов |

Итог: прошивка ≈15,3 МБ из 15,4 МБ, под настройки (overlay) остаётся ≈750 КБ —
для конфигов этого с запасом, но ставить дополнительные пакеты через `apk` места
почти нет. Точные размеры Xray и образа — в сводке каждой сборки в Actions.

## Как это работает

```
Клиент LAN ──► dnsmasq ──(DNS)──► 127.0.0.1:5353 ─► Xray ─► VPN-сервер ─► 1.1.1.1
     │            │
     │            └─ домены из списков → nft set pbr
     │
     └──► pbr: адрес в списке? ──да──► xray0 (TUN) ─► Xray ─► VPN-сервер
                              └─нет──► wan (напрямую)
```

Интерфейс `xray` (устройство `xray0`, адрес 172.19.0.1/30) и зона firewall `xray`
создаются при первой загрузке; соединение Xray с самим сервером всегда идёт мимо
туннеля (политика `Xray server (direct)`).

## Где взять прошивку

- **Releases** — готовые сборки для тегов `v*`;
- **Actions → build → последний успешный запуск → Artifacts** — сборка любого коммита.

Файлы:

- `...-mercusys_mr70x-v1-squashfs-factory.bin` — для прошивки из заводского веб-интерфейса;
- `...-mercusys_mr70x-v1-squashfs-sysupgrade.bin` — для обновления из OpenWrt.

## Установка

**С заводской прошивки Mercusys**

1. Веб-интерфейс роутера → *Система / System Tools → Обновление ПО / Firmware Upgrade* →
   загрузить `factory.bin`.
2. После перезагрузки роутер доступен на `http://192.168.1.1` (логин `root`, без пароля) —
   сразу задайте пароль.

**С OpenWrt**

LuCI → *Система → Резервная копия / прошивка → Установить новую прошивку* → `sysupgrade.bin`.
При переходе с другой сборки лучше **не сохранять настройки** (первичная настройка
pbr/firewall выполняется только на чистой системе).

**Восстановление** (если что-то пошло не так): выключить роутер, зажать Reset,
включить и держать 5–10 секунд, вручную задать компьютеру IP `192.168.1.2/24`
и открыть `http://192.168.1.1` — это аварийный веб-интерфейс загрузчика, через него
можно залить `factory.bin` OpenWrt или заводскую прошивку.

## Настройка

1. Настройте интернет (*Сеть → Интерфейсы → WAN*, для PPPoE укажите логин/пароль) и Wi-Fi.
2. *Службы → Xray*: вставьте ссылку вида

   ```
   vless://UUID@сервер:443?type=tcp&security=reality&pbk=...&sid=...&sni=...&fp=chrome&flow=xtls-rprx-vision#имя
   ```

   и нажмите «Сохранить и применить». Ссылку выдаёт панель сервера (3x-ui, Marzban, Remnawave и т.п.).
   То же самое из консоли: `xray-link 'vless://...'`.
3. Через минуту проверьте, что открываются заблокированные сайты.

### Какие сайты идут через VPN

*Службы → Маршрутизация по политикам (pbr)*. Предустановлены политики:

| Политика | Что делает |
| --- | --- |
| `Xray server (direct)` | соединение с самим VPN-сервером всегда идёт напрямую (заполняется автоматически) |
| `Russia inside: domains` | [список доменов itdoginfo](https://github.com/itdoginfo/allow-domains) — YouTube, Instagram, Discord, ChatGPT и т.д. |
| `Telegram, Meta, Twitter, Discord subnets` | подсети этих сервисов (для приложений, которые ходят по IP) |
| `My domains` | ваш собственный список доменов через пробел — добавляйте сюда что нужно |

В политике можно указывать домены, IP, подсети и ссылки на списки (`https://...`).
Можно также ограничить политику отдельными устройствами (поле «Локальные адреса»),
например чтобы телевизор ходил через VPN целиком.

Списки обновляются каждый день в 05:30 (`/etc/init.d/pbr restart` в cron) или кнопкой
«Обновить списки» на странице Xray.

### Если VPN-сервер недоступен

Весь DNS идёт через туннель, поэтому при неработающем сервере «пропадёт интернет».
Нажмите **Stop** на странице *Службы → Xray* — DNS сразу вернётся на провайдера.
Отключить DNS через туннель насовсем: `uci set xray.main.dns_tunnel=0; uci commit xray; /etc/init.d/xray restart`.

### Настройки `/etc/config/xray`

| Опция | По умолчанию | Описание |
| --- | --- | --- |
| `enabled` | `1` | запускать Xray |
| `config` | `/etc/xray/config.json` | конфиг Xray (генерируется `xray-link`, можно писать руками) |
| `dns_tunnel` | `1` | весь DNS роутера через туннель |
| `dns_port` | `5353` | локальный порт DNS-форвардера Xray |
| `upstream_dns` | `1.1.1.1` | DNS-сервер на той стороне туннеля (применяется при следующем `xray-link`) |
| `bootstrap_dns` | `77.88.8.8` | DNS для имени VPN-сервера и NTP (в обход туннеля) |
| `memlimit` | `40MiB` | мягкий лимит памяти Go |

Конфиг `/etc/xray/config.json` можно написать и вручную — главное, чтобы в нём был
inbound `tun` с именем `xray0` (и `dokodemo-door` на `127.0.0.1:5353` для DNS).
Конфиг и ссылка сохраняются при sysupgrade.

### Диагностика

```sh
logread -e xray                  # лог Xray
/etc/init.d/pbr status           # что делает pbr
nft list sets inet fw4 | grep pbr   # nft set'ы, которые заполняет pbr
ip route show table all | grep xray0
xray-link --show                 # сохранённая ссылка
```

Не запускайте `xray run -test` на конфиге с TUN при работающем Xray: тест
действительно открывает устройство `xray0`. `xray-link` проверяет копию конфига без TUN.

## Ограничения облегчённого Xray

Поддерживается: VLESS (+ flow `xtls-rprx-vision`, + VLESS Encryption), транспорты
RAW/TCP, XHTTP, WebSocket, HTTPUpgrade, безопасность REALITY/TLS; inbound TUN,
dokodemo-door, SOCKS, HTTP; outbound freedom, blackhole, DNS.

Не поддерживается (конфиг с ними не запустится с понятной ошибкой): VMess, Trojan,
Shadowsocks, WireGuard, Hysteria, gRPC-транспорт, API/статистика через gRPC, metrics,
TOML/YAML-конфиги, `geoip:` / `geosite:` в правилах маршрутизации Xray.

## Сборка самостоятельно

Всё собирается в GitHub Actions (`.github/workflows/build.yml`) примерно за 5 минут:

1. Xray-core клонируется по тегу и собирается скриптом `xray-slim/build.sh`
   (`GOARCH=mipsle GOMIPS=softfloat`, `-trimpath -s -w`).
2. Скачивается официальный ImageBuilder OpenWrt (с проверкой sha256).
3. `make image` с пакетами из `packages.txt` и файлами из `files/`.
4. Проверяется размер и запускается smoke-тест: в собранном rootfs под qemu
   выполняется `xray-link` и `xray run -test`.

Сменить версии можно при ручном запуске (*Actions → build → Run workflow*) или в `env`
workflow. Релиз: *Actions → build → Run workflow* с заполненным `release_tag`
(например `v25.12.5-2`) или `git tag v25.12.5-2 && git push --tags`.

Структура:

```
packages.txt                       пакеты OpenWrt
xray-slim/                         урезанная сборка Xray (список модулей + заглушки)
files/etc/init.d/xray              procd-сервис, DNS через туннель
files/usr/bin/xray-link            vless:// → /etc/xray/config.json
files/etc/uci-defaults/99-mr70x-xray  первичная настройка сети, firewall, pbr
files/www/.../view/xray-link.js    страница LuCI
```
