# Strona www KS-eFektywnie

Statyczna strona aplikacji iOS KS-eFektywnie pod adresem **https://ksefektywnie.ikolek.pl**.
W App Store Connect służy jako adres polityki prywatności, adres wsparcia (Support URL) i strona marketingowa.

Czysty HTML + CSS i kilka linii JS. Bez kroku budowania, frameworków, zewnętrznych CDN i fontów,
bez cookies, analityki i trackerów (polityka prywatności to obiecuje, więc nie dodawaj ich).

## Struktura

```
website/
├── index.html                  strona główna (PL, domyślna)
├── polityka-prywatnosci.html   polityka prywatności (PL)
├── wsparcie.html               wsparcie + FAQ (PL)
├── en/
│   ├── index.html              home (EN)
│   ├── privacy.html            privacy policy (EN)
│   └── support.html            support + FAQ (EN)
├── assets/
│   ├── style.css               cały wygląd; tryb jasny/ciemny przez prefers-color-scheme
│   ├── config.js               APP_STORE_URL — link do App Store (jedyne miejsce do zmiany)
│   ├── site.js                 pokazuje przycisk App Store, gdy link jest ustawiony
│   ├── icon-512.png            ikona na stronie (rogi zaokrąglane w CSS)
│   ├── apple-touch-icon.png    180×180
│   ├── favicon-32.png          32×32
│   └── og-image.png            1200×630, podgląd linku (Open Graph)
├── robots.txt
├── sitemap.xml                 z adnotacjami hreflang PL/EN
└── README.md                   ten plik (nie musi trafiać na serwer)
```

Obrazki wygenerowano z `docs/ikona.png`. Linki do podstron są względne, więc stronę można też
otworzyć lokalnie: `cd website && python3 -m http.server 8000` → http://localhost:8000.

Adresy w App Store Connect:

| Pole | PL | EN |
|---|---|---|
| Privacy Policy URL | https://ksefektywnie.ikolek.pl/polityka-prywatnosci.html | https://ksefektywnie.ikolek.pl/en/privacy.html |
| Support URL | https://ksefektywnie.ikolek.pl/wsparcie.html | https://ksefektywnie.ikolek.pl/en/support.html |
| Marketing URL | https://ksefektywnie.ikolek.pl/ | https://ksefektywnie.ikolek.pl/en/ |

Zmieniając treść polityki prywatności, zaktualizuj datę obowiązywania na obu stronach (PL i EN)
oraz `lastmod` w `sitemap.xml`.

## Włączenie przycisku App Store

1. W `assets/config.js` wpisz link:
   ```js
   const APP_STORE_URL = "https://apps.apple.com/pl/app/ks-efektywnie/id0000000000";
   ```
2. Wgraj stronę ponownie (patrz niżej).

Gdy `APP_STORE_URL` jest pusty (albo nie zaczyna się od `https://`), przycisk jest ukryty, a w jego
miejscu widać „Wkrótce w App Store” / „Coming soon to the App Store”. Działa to na obu wersjach
językowych naraz. Bez JavaScriptu zawsze widać napis „Wkrótce…”.

### Oficjalny badge Apple

Teraz jest to prosty przycisk tekstowy. Żeby użyć oficjalnego badge'a „Download on the App Store”:

1. Pobierz badge (SVG, wersja PL i EN; najlepiej czarny i biały) z
   https://developer.apple.com/app-store/marketing/guidelines/ (sekcja *App Store badges*).
2. Zapisz pliki w `assets/`, np. `app-store-badge-pl.svg`, `app-store-badge-en.svg`.
3. W `index.html` i `en/index.html` zamień zawartość elementu `<a … data-app-store-link hidden>`
   na obrazek i usuń z niego `class="button"`, np.:
   ```html
   <a href="#" data-app-store-link hidden>
     <img src="assets/app-store-badge-pl.svg" alt="Pobierz z App Store" width="150" height="50">
   </a>
   ```
   (w `en/index.html` ścieżka to `../assets/app-store-badge-en.svg`). Atrybuty `data-app-store-link`
   i `hidden` muszą zostać — to z nich korzysta `site.js`.

## Wystawienie strony

Konfiguracja serwera nie jest w repo (Django działa w Dockerze, reverse proxy jest poza repo).
Potrzebny jest rekord DNS `A`/`AAAA` dla `ksefektywnie.ikolek.pl` wskazujący na serwer.

### Kopiowanie plików

```bash
rsync -avz --delete --exclude README.md website/ user@serwer:/var/www/ksefektywnie/
```

Ukośnik na końcu `website/` jest ważny (kopiuje zawartość, nie katalog).

### (a) nginx

`/etc/nginx/sites-available/ksefektywnie.ikolek.pl` (potem `ln -s` do `sites-enabled/`):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name ksefektywnie.ikolek.pl;

    # Weryfikacja certbota (webroot), reszta → HTTPS
    location /.well-known/acme-challenge/ {
        root /var/www/ksefektywnie;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ksefektywnie.ikolek.pl;

    ssl_certificate     /etc/letsencrypt/live/ksefektywnie.ikolek.pl/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ksefektywnie.ikolek.pl/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;

    root /var/www/ksefektywnie;
    index index.html;
    charset utf-8;

    # Nagłówki bezpieczeństwa (strona nie ładuje nic z zewnątrz)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), interest-cohort=()" always;

    location / {
        try_files $uri $uri.html $uri/ =404;
    }

    # Obrazki: długi cache. CSS/JS: krótki (nazwy plików bez hashy).
    # Uwaga: używamy tylko `expires`, żeby nie zgubić add_header z poziomu server.
    location ~* \.(png|jpe?g|svg|ico|webp)$ {
        expires 30d;
        access_log off;
    }
    location ~* \.(css|js)$ {
        expires 1h;
    }

    location = /README.md { return 404; }
}
```

Certyfikat (certbot, metoda webroot):

```bash
# 1. Na start włącz tylko pierwszy blok (port 80) — drugi zakomentuj, bo certyfikatu jeszcze nie ma.
sudo nginx -t && sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/ksefektywnie -d ksefektywnie.ikolek.pl
# 2. Odkomentuj blok 443 i przeładuj nginx. Odnawianie działa automatycznie (timer certbota).
sudo nginx -t && sudo systemctl reload nginx
```

Jeśli `/etc/letsencrypt/options-ssl-nginx.conf` nie istnieje (instaluje go wtyczka `python3-certbot-nginx`),
usuń linię `include` albo zamiast webroot użyj `sudo certbot --nginx -d ksefektywnie.ikolek.pl`.

### (b) Caddy

Caddy sam pobiera i odnawia certyfikat oraz przekierowuje http→https:

```caddyfile
ksefektywnie.ikolek.pl {
    root * /var/www/ksefektywnie
    encode zstd gzip
    try_files {path} {path}.html {path}/
    file_server

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }

    @images path *.png *.jpg *.jpeg *.svg *.ico *.webp
    header @images Cache-Control "public, max-age=2592000"

    @readme path /README.md
    respond @readme 404
}
```

Jeśli reverse proxy działa w kontenerze, zamontuj katalog strony jako wolumen tylko do odczytu,
np. `- /var/www/ksefektywnie:/var/www/ksefektywnie:ro`.
