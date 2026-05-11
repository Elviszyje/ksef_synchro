# KSeF Invoices — dokumentacja projektu

## Stos technologiczny
- **Backend**: Django 5.1 (Python 3.12)
- **Frontend**: Bootstrap 5.3 + HTMX 1.9 (server-side rendering, brak SPA)
- **Baza danych**: PostgreSQL 16
- **Kolejka zadań**: Celery 5 + Redis 7
- **Docker**: multi-platform (linux/amd64, linux/arm64)

## Struktura aplikacji
| App | Odpowiedzialność |
|-----|-----------------|
| `apps.accounts` | CustomUser z rolami (viewer/accountant/approver/admin), logowanie |
| `apps.invoices` | Model Invoice, statusy, filtrowanie, export Excel |
| `apps.ksef` | KSeFConfig, klient API KSeF 2.0, parser FA(2) XML, Celery sync |
| `apps.payments` | Generatory plików Erste TXT i Elixir-0 PLI, historia plików |
| `apps.bank_statements` | Upload MT940, matcher transakcji do faktur, zatwierdzanie |
| `core` | Uprawnienia (RoleRequiredMixin), templatetagi |

## Role użytkowników
| Rola | Uprawnienia |
|------|-------------|
| viewer | Przegląd faktur, export Excel |
| accountant | + zmiana statusów, import wyciągów |
| approver | + generowanie plików przelewów |
| admin | + konfiguracja KSeF, zarządzanie użytkownikami |

## Statusy faktur
`nowa` → `sporna` ↔ `zaakceptowana` → `przekazano_do_oplacenia` → `oplacona`

## Uruchomienie
```bash
cp .env.example .env   # Uzupełnij zmienne
docker compose up -d
docker compose exec web python manage.py createsuperuser
```

## KSeF API
- Test: `https://api-test.ksef.mf.gov.pl`
- Prod: `https://api.ksef.mf.gov.pl`
- Konfiguracja: `/ksef/config/` (rola admin)
- Sync manualny: `/ksef/sync/` (POST)

## Format pliku bankowego
- **Erste TXT**: `4120414|1` header, separator `|`, Windows-1250
- **Elixir-0 PLI**: separator `,`, CP1250, bez nagłówka
- Specyfikacja: `format_danych.pdf`

## Zmienne środowiskowe kluczowe
- `KSEF_TOKEN_ENCRYPTION_KEY` — klucz Fernet do szyfrowania tokena KSeF
- `COMPANY_BANK_ACCOUNT` — NRB konta firmowego (26 cyfr bez spacji)
- `COMPANY_NIP` — NIP firmy płatnika
