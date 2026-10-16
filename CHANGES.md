# Изменения

## v25.12.5-3

- **Исправлено: списки сайтов pbr по https не скачивались.** pbr считает, что https
  поддерживается, только если установлен curl или wget-ssl, и с одним `uclient-fetch`
  пропускал все списки itdoginfo — через VPN шли только домены из «My domains».
  Теперь pbr скачивает их через `uclient-fetch` (сборка патчит pbr, smoke-тест скачивает
  список по https тем же кодом pbr).
- **Xray 26.10.10** (было 26.3.27). Облегчённая сборка — 5,9 МБ: из нового Xray
  вырезаны MASQUE, XDrive, Lua-скрипты, редкие маски finalmask.
- **HWID для подписок**: заголовки `x-hwid`, `x-device-os`, `x-ver-os`, `x-device-model`
  для панелей с лимитом устройств (Remnawave, Marzban…). Включено по умолчанию,
  отключается галочкой на странице Xray.
- **Варианты с zapret2** (`xray-zapret`, `xray-awg-zapret-proton`): YouTube и Discord идут
  напрямую с обходом DPI (nfqws2), а не через VPN. +260 КБ.
- **zram**: 32 МБ сжатого swap в ОЗУ во всех вариантах.

## v25.12.5-2

- Сборка из исходников, Hysteria2/Trojan/Shadowsocks, подписки, AmneziaWG, тема Proton2025,
  варианты прошивки; варианты с apk — на официальном ядре (официальные `kmod-*` ставятся).
