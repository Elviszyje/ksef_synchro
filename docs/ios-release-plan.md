# Plan wydania natywnej aplikacji iOS (KSeF Invoices Mobile)

Stan: plan zatwierdzony co do decyzji kierunkowych, 2026-10-11. Źródłem logiki domenowej jest aplikacja Django w tym repo.

Nazwa aplikacji: **KS-eFektywnie**. Kod iOS: katalog `ios/` w tym repo.

## 1. Założenia produktu

- Aplikacja natywna (Swift 6.2, SwiftUI, Liquid Glass), minimalna wersja **iOS 26**. Działa w 100% lokalnie na telefonie. Brak kont, brak logowania, brak własnego backendu.
- Połączenia sieciowe: API KSeF 2.0 (test/prod), Biała Lista MF (podpowiedź danych nabywcy po NIP), StoreKit (napiwek dla dewelopera) oraz iCloud Drive użytkownika (kopia danych w jego własnym koncie Apple, bez serwera dewelopera).
- Opcjonalna blokada Face ID / Touch ID (z fallbackiem na kod urządzenia).
- Języki UI: polski (domyślny), angielski, hiszpański, ukraiński.
- Zakres v1: faktury kosztowe z KSeF, zarządzanie statusami, pliki przelewów dla banku, import wyciągów i dopasowanie płatności, **wystawianie i wysyłka faktur sprzedażowych do KSeF** (z UPO).
- Jedna firma (jeden NIP) w v1, ale z gotowością na kilka podmiotów: każda tabela ma `companyId`, token KSeF w Keychain pod kluczem per firma, repozytoria przyjmują `companyId` jako parametr, a UI ma jeden `ActiveCompany` jako źródło prawdy. Dodanie przełącznika firm w v2 to wyłącznie praca w UI i onboardingu.

### Poza zakresem v1 (świadomie)
- Role użytkowników, licencje, panel firm, audit log – nie mają sensu w aplikacji jednoosobowej.
- Powiadomienia Telegram – zastąpione lokalnymi powiadomieniami iOS.
- Export Excel (.xlsx) – w v1 export CSV przez arkusz udostępniania; .xlsx w v2 (wymaga pakietu do zapisu xlsx).
- Dwukierunkowa synchronizacja między urządzeniami – v2 (na bazie katalogu iCloud Drive z sekcji 4.8 lub CloudKit). W v1: jednokierunkowe lustro do iCloud Drive + odtworzenie danych na nowym urządzeniu.

## 2. Architektura

| Warstwa | Decyzja | Uzasadnienie |
|---|---|---|
| UI | SwiftUI, NavigationStack, iOS 26+, Liquid Glass | Jeden kod bez gałęzi na stare systemy; iOS 26 obsługuje iPhone 11 i nowsze. Nowe API: Observation, String Catalogs, Swift Charts, `@Entry`, domyślna izolacja MainActor w Swift 6.2 |
| Stan | `@Observable` ViewModele, struktura MVVM + warstwa "Domain" bez zależności od UI | Logika portowana z Pythona musi być testowalna bez symulatora |
| Baza | SQLite przez GRDB.swift | Precyzja `Decimal` kwot, pełna kontrola migracji, zapytania matchera w SQL. SwiftData odrzucony ze względu na dojrzałość i problemy z unikalnością/Decimal |
| Sieć | URLSession async/await, bez bibliotek zewnętrznych | Klient KSeF to kilkanaście endpointów |
| Krypto | Security.framework: `SecCertificateCreateWithData` + `SecKeyCreateEncryptedData(.rsaEncryptionOAEPSHA256)`; CommonCrypto dla AES-256-CBC przy wysyłce faktur | Szyfrowanie tokena identyczne z `apps/ksef/client.py` bez bibliotek zewnętrznych; CryptoKit nie ma AES-CBC, więc do sesji wysyłkowej KSeF potrzebny CommonCrypto |
| Sekrety | Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); przy włączonym Face ID dodatkowo `SecAccessControl` z `.biometryCurrentSet` | Token KSeF nigdy nie trafia do bazy ani do kopii zapasowej |
| Pliki | Data Protection `NSFileProtectionComplete` na katalogu bazy | Baza nieczytelna przy zablokowanym telefonie |
| iCloud | iCloud Documents (kontener ubiquity, katalog widoczny w aplikacji Pliki), `NSFileCoordinator` + `NSMetadataQuery`; `NSUbiquitousKeyValueStore` dla drobnych ustawień | Dane w koncie Apple użytkownika, czytelne JSON/XML, zero infrastruktury po stronie dewelopera. CloudKit odrzucony w v1: GRDB nie ma integracji, a rekordy nie byłyby widoczne dla użytkownika |
| XML | Odczyt: Foundation `XMLParser` (SAX) ze stosem ścieżek + wykrywanie namespace FA(2)/FA(3). Zapis: Foundation `XMLDocument` nie istnieje na iOS, więc własny lekki builder elementów z escapowaniem | Brak XPath w Foundation; SAX wystarcza, bo ścieżki są płytkie i znane |
| Kodowania | `String.Encoding.windowsCP1250` z Foundation | Pliki Erste/mBank/Elixir wymagają CP1250 i CRLF |
| Biometria | LocalAuthentication, `deviceOwnerAuthentication` | Face ID z fallbackiem na kod |
| Napiwki | StoreKit 2, produkty konsumowalne | Wymóg App Store 3.1.1: napiwek dla dewelopera musi być IAP |
| Lokalizacja | String Catalogs (.xcstrings), pl/en/es/uk, `Locale` do formatów liczb i dat | Jeden plik na język, pluralizacja wbudowana |
| Opcjonalnie (iOS 26) | Foundation Models (model na urządzeniu) | Kandydat na v2: podpowiedź kategorii kosztu i streszczenie opisu faktury, bez wysyłania danych poza telefon |
| Testy | XCTest + golden files generowane kodem Django | Port 1:1 weryfikowany bajt w bajt |
| CI/dystrybucja | Xcode Cloud lub fastlane, TestFlight | Beta zamknięta przed publikacją |

Repozytorium: katalog `ios/` w tym repo. Struktura:

```
ios/
  KSeFektywnie.xcodeproj
  KSeFektywnie/            # app target (SwiftUI, nawigacja, ekrany)
  Packages/
    Domain/                # modele, statusy, przejścia, matcher, generatory, parsery (czysty Swift, bez UIKit)
    KSeFClient/            # klient API KSeF 2.0 + krypto
    Persistence/           # GRDB, migracje, repozytoria
  Tests/
    Fixtures/              # golden files generowane z Django (patrz sekcja 8)
```

Pakiety lokalne (Swift Package) wymuszają separację warstw i pozwalają uruchamiać testy Domain bez symulatora. Istniejąca aplikacja Expo w `mobile/` to klient backendu i pozostaje niezależnym produktem.

## 3. Model danych (SQLite)

Odwzorowanie modeli Django z pominięciem pól wieloużytkownikowych.

- `company` – nip, nazwa, adres, środowisko KSeF (test/prod), interwał sync, kursor `lastSyncAt`.
- `bank_account` – NRB firmy, `bankKey` wykryty z pozycji 3–6 NRB (tabela z `apps/payments/bank_detection.py`), domyślny tak/nie.
- `invoice` – pola z `apps/invoices/models.py` (ksefReferenceNumber UNIQUE per company, numer, sprzedawca, kwoty jako tekst Decimal lub INTEGER w groszach, MPP, daty, NRB sprzedawcy, status, notatki, rawXml).
- `invoice_status_log` – historia zmian statusu.
- `payment_file` + `payment_file_item` – wygenerowane pliki (treść jako BLOB) i pozycje.
- `bank_statement`, `bank_transaction`, `transaction_match` – import wyciągów i dopasowania.
- `sync_log` – przebieg synchronizacji (etap, pobrane, nowe, błąd).
- `buyer` – nabywcy (NIP UNIQUE per company, nazwa, adres, e-mail, telefon, notatki).
- `outgoing_invoice` + `outgoing_invoice_item` – faktury sprzedażowe z `apps/outgoing/models.py`: numer UNIQUE per company, daty, forma płatności, dane nabywcy (kopia w momencie wystawienia), status (`draft/queued/sending/accepted/rejected`), referencja wysyłki, numer KSeF, wygenerowany XML, UPO XML, komunikat błędu. Pozycje: lp, nazwa, jednostka, ilość (3 miejsca), cena netto, stawka (23/8/5/0/zw/np), kwoty netto/VAT/brutto liczone jak w `InvoiceItem.calculate_amounts` (ROUND_HALF_UP).
- `company_settings` – prefiks i wzór numeracji (domyślnie `FV/{rok}/{nnnn}`), domyślny termin płatności, domyślny rachunek do faktur sprzedażowych.
- `cloud_mirror_state` – dla każdego rekordu eksportowanego do iCloud: ścieżka pliku, `updatedAt` ostatnio zapisanej wersji, hash treści. Pozwala eksportować tylko zmiany i wykrywać pliki zmodyfikowane po stronie iCloud.

Statusy i przejścia: port `STATUS_TRANSITIONS` oraz `STATUS_TRANSITIONS_CORRECTION` z `apps/invoices/views.py`, w tym automatyczne `oplacona` dla zaakceptowanej korekty.

## 4. Moduły do zaimplementowania (port z Django)

### 4.1 KSeF
Źródło: `apps/ksef/client.py`, `apps/ksef/parser.py`, `apps/ksef/tasks.py`.

1. Auth: `POST auth/challenge` → pobranie certyfikatu `security/public-key-certificates` → RSA-OAEP(SHA-256) na `"{token}|{timestampMs}"` → `POST auth/ksef-token` → polling `GET auth/{ref}` do kodu 200 → `POST auth/token/redeem`. AccessToken trzymany w pamięci (ważny ok. 15 min), odnawiany przy 401.
2. Query: `POST invoices/query/metadata` (`subjectType: Subject2`, `dateType: PermanentStorage`), chunki po 89 dni, paginacja `pageOffset`.
3. XML: `GET invoices/ksef/{nr}` z `Accept: application/octet-stream`; 404 = fallback na metadane.
4. Limity: obsługa 429 z parsowaniem czasu oczekiwania z komunikatu PL ("godzin", "minut", "sekund"); limit pobierania XML ok. 64/h, więc sync musi być **wznawialny**: kolejka `ksefNumber` do pobrania, pobieranie partiami, komunikat "pobrano X z Y, reszta po HH:MM".
5. Parser FA(2)/FA(3): te same ścieżki co w Pythonie (P_1, P_2, P_13_x, P_14_x, P_15, Podmiot1/Podmiot2, Platnosc/TerminPlatnosci, NrKonta/NrRB, MechanizmPodzielonejPlatnosci, FaWiersz). Namespace wykrywany z elementu głównego.
6. Harmonogram: sync na żądanie (pull-to-refresh + przycisk) jako tryb główny. `BGAppRefreshTask` jako best-effort z lokalnym powiadomieniem "N nowych faktur". iOS nie gwarantuje wykonania, dokumentacja pomocy ma o tym mówić wprost.
7. Test połączenia w ustawieniach: pełny auth bez pobierania faktur, czytelna mapa błędów (zły NIP, zły token, token wygasł, brak uprawnień, limit, brak sieci).

### 4.2 Faktury
Źródło: `apps/invoices/`.

- Lista z filtrami (status, sprzedawca, zakres dat, przeterminowane, MPP), wyszukiwanie, sortowanie, zaznaczanie wielu i zmiana zbiorcza statusu.
- Szczegół: nagłówek, kwoty, pozycje (`FaWiersz`), dane płatności, historia statusów, notatki, podgląd/udostępnienie surowego XML.
- Dashboard: suma 12 mies., średnia, słupki miesięczne, top 5 sprzedawców (Swift Charts).
- Export CSV z aktualnego filtra przez `ShareLink`.

### 4.3 Pliki przelewów
Źródło: `apps/payments/`.

- Wybór faktur `zaakceptowana` z uzupełnionym NRB, wybór rachunku obciążeniowego firmy, grupowanie per bank nadawcy.
- Generatory: Erste TXT (`4120414|1`, typ 1 i typ 6 MPP), mBank TXT, Elixir-0 PLI (17 pól, kwoty w groszach). Transliteracja PL, `_clean_text`, limity długości i nazewnictwo plików jak w Pythonie.
- Po wygenerowaniu: faktury → `przekazano_do_oplacenia`, plik zapisany w historii, reset pliku cofa statusy.
- Dystrybucja pliku: arkusz udostępniania (Zapisz do Plików, AirDrop na Maca, Mail, iCloud Drive). Pomoc opisuje realny scenariusz: import pliku odbywa się najczęściej w bankowości na komputerze.

### 4.4 Wyciągi bankowe
Źródło: `apps/bank_statements/`.

- `fileImporter` (typy: plain text, CSV, `.sta`, `.mt940`, `.txt`), dekodowanie UTF-8 → fallback CP1250.
- Auto-detekcja formatu: MT940, CSV Erste, CSV VeloBank (port `detect.py`); preferencja wg banków rachunków firmowych.
- Matcher: port hierarchii (kwota + NRB, kwota + numer FV + NIP, kwota + NIP, kwota + numer FV, unikalna kwota) z normalizacją numeru faktury (usuwanie wiodących zer segmentów).
- Ekran przeglądu: lista transakcji debetowych z propozycjami, przełączanie potwierdzeń, ręczne przypięcie faktury, "Zatwierdź wyciąg" → `oplacona`.

### 4.5 Faktury wychodzące (sprzedażowe)
Źródło: `apps/outgoing/`, `apps/ksef/generator.py`, metody `send_invoice`, `get_send_status`, `get_upo` w `apps/ksef/client.py`.

- Nabywcy: lista, wyszukiwanie, edycja, podpowiedź danych po NIP z Białej Listy MF (odpowiednik `NipLookupView`); zapisanie nabywcy przy pierwszym użyciu.
- Formularz faktury: numer nadawany automatycznie z `generate_number` (ostatni numer w roku + 1, z możliwością ręcznej zmiany), data wystawienia, data dostawy, termin płatności, forma płatności, pozycje z przeliczaniem kwot na żywo, podsumowanie wg stawek, uwagi.
- Generator XML: **FA(3)** (namespace `http://crd.gov.pl/wzor/2025/06/25/13775/`), nie FA(2) jak w Django. Od 1 lutego 2026 KSeF przyjmuje wyłącznie FA(3), więc port generatora wymaga aktualizacji schematu (nagłówek `WariantFormularza` 3, `Nazwa` zamiast `PelnaNazwa`, zmiany w `Platnosc`). Wymaga walidacji przeciw XSD FA(3) na środowisku testowym przed pierwszą wysyłką produkcyjną.
- Wysyłka: zweryfikować rzeczywisty przebieg KSeF 2.0 w dokumentacji (`/docs/v2`). Django wysyła surowy XML na `invoices/send`; w API 2.0 standardowa ścieżka to otwarcie sesji interaktywnej (`sessions/online`), zaszyfrowanie faktury AES-256-CBC kluczem symetrycznym zaszyfrowanym RSA-OAEP kluczem publicznym KSeF, wysłanie, odpytanie statusu i pobranie UPO sesji. Klient iOS ma implementować przebieg zgodny z dokumentacją, a nie kopiować Django 1:1. To jedyne miejsce, gdzie port nie jest wierny.
- Statusy i akcje: `draft` → edycja i "Wyślij do KSeF" → `sending` (polling statusu co kilka sekund w pierwszej minucie, potem na żądanie) → `accepted` z numerem KSeF i UPO lub `rejected` z komunikatem błędu i możliwością poprawy i ponownej wysyłki. Bez kolejki Celery: wysyłka wykonuje się w tle aplikacji przez `URLSession` background-friendly z zapisem stanu po każdym kroku, aby przerwanie nie zgubiło referencji.
- Szczegół: podgląd XML, UPO (udostępnienie jako plik), wydruk/PDF faktury do wysłania klientowi (SwiftUI `ImageRenderer` do PDF, prosty szablon zgodny z danymi FA).
- Tryb testowy: wysyłka na `api-test` z fikcyjnym NIP, wprost oznaczona w UI banerem "ŚRODOWISKO TESTOWE", aby nikt nie pomylił faktury testowej z prawdziwą.

### 4.6 Bezpieczeństwo i Face ID
- Przełącznik w ustawieniach; po włączeniu wymóg uwierzytelnienia przy starcie i po powrocie z tła (próg np. 30 s), rozmycie ekranu w app switcherze.
- `NSFaceIDUsageDescription` w Info.plist.
- Opcja "Usuń wszystkie dane" (baza + Keychain) z potwierdzeniem.

### 4.7 Ustawienia
- Firma: NIP, nazwa, adres (35 znaków do plików bankowych), rachunki bankowe, numeracja i domyślne wartości faktur sprzedażowych. Ekran zaprojektowany jako "profil firmy", aby lista profili w v2 była naturalnym rozszerzeniem.
- KSeF: środowisko, token (wklej / skanuj QR jeżeli użytkownik ma go na ekranie komputera), test połączenia, interwał, ostatnia sync, logi sync.
- Bezpieczeństwo: Face ID, usuń dane (z pytaniem, czy usunąć także katalog w iCloud).
- iCloud Drive: włącz/wyłącz lustro, stan ostatniego zapisu, liczba plików, "Zapisz wszystko ponownie", "Sprawdź spójność", "Otwórz w Pliki".
- Język aplikacji (link do ustawień systemowych per-app language).
- Pomoc (sekcja 5).
- **Tip for developer**: 3 produkty konsumowalne (np. kawa / obiad / duże dzięki), ekran z podziękowaniem, bez żadnego odblokowywania funkcji. Wymaga podpisania Paid Apps Agreement i danych podatkowych w App Store Connect.
- O aplikacji: wersja, polityka prywatności, licencje open source.

### 4.8 Katalog danych w iCloud Drive
Nowy moduł, bez odpowiednika w Django (tam rolę trwałego magazynu pełni PostgreSQL).

Zasada: baza SQLite na telefonie jest źródłem prawdy i jedynym miejscem, z którego czyta UI. iCloud Drive jest lustrem zapisywanym po każdej zmianie (write-through), czytelnym dla człowieka i dla innych programów. Dzięki temu użytkownik ma kopię niezależną od aplikacji, księgowa dostaje pliki bez eksportu ręcznego, a nowy telefon odtwarza dane bez serwera.

Struktura katalogu (widoczna w Pliki → iCloud Drive → KS-eFektywnie):

```
KS-eFektywnie/
  manifest.json                      # wersja schematu, lista firm, data ostatniego zapisu, identyfikator urządzenia
  <NIP>/
    firma.json                       # profil firmy, rachunki, numeracja (bez tokena)
    faktury-kosztowe/
      2026/2026-10/
        <numerKSeF>.json             # pola faktury + status + notatki + historia statusów
        <numerKSeF>.xml              # surowy XML FA z KSeF
    faktury-sprzedazowe/
      2026/
        FV-2026-0001.json
        FV-2026-0001.xml             # wygenerowany FA(3)
        FV-2026-0001.upo.xml
        FV-2026-0001.pdf
    nabywcy.json
    przelewy/
      2026-10-11_Erste_Bank.txt      # dokładnie ten plik, który poszedł do banku
      2026-10-11_Erste_Bank.json     # lista faktur w pliku, kwoty, rachunek obciążeniowy
    wyciagi/
      2026-10_MT940.sta              # oryginał importu
      2026-10_MT940.json             # transakcje + dopasowania + kto/kiedy zatwierdził
    eksport/
      faktury-kosztowe-2026-10.csv   # eksporty generowane na żądanie
```

Zasady formatu:
- JSON z polem `schemaVersion`, daty ISO 8601, kwoty jako tekst (`"1234.56"`), aby nie tracić precyzji. Nazwy pól takie jak w serializerach REST w `apps/api/` (np. `ksef_reference_number`, `amount_gross`, `payment_due_date`), co pozwala w przyszłości zaimportować katalog do aplikacji webowej jednym skryptem.
- Jeden plik na dokument, nie jeden wielki plik: iCloud synchronizuje per plik, konflikty dotyczą pojedynczej faktury, a użytkownik widzi kompletne dokumenty w Pliki.
- Nazwy plików tylko ASCII, separatory `-` i `_`, bez `/` z numerów faktur.
- Token KSeF, dane biometryczne i klucze nigdy nie trafiają do katalogu. `firma.json` zawiera tylko dane jawne.

Przebieg:
1. Zapis: po każdej transakcji w bazie kolejka eksportu (actor `CloudMirror`) zapisuje zmienione pliki przez `NSFileCoordinator` poza głównym wątkiem. Przy braku iCloud (wyłączony w ustawieniach systemu, brak miejsca) ten sam katalog powstaje lokalnie w Documents i jest widoczny w Pliki → Na moim iPhonie, a w ustawieniach aplikacji pojawia się ostrzeżenie.
2. Odtworzenie: przy pierwszym uruchomieniu aplikacja sprawdza kontener ubiquity; jeśli znajdzie `manifest.json`, proponuje "Przywróć dane z iCloud" i importuje katalog do SQLite (statusy, notatki, historia, pliki bankowe, wyciągi). Pobieranie plików z iCloud wymaga `startDownloadingUbiquitousItem` i może trwać, więc ekran pokazuje postęp per katalog.
3. Przebudowa: w ustawieniach przycisk "Zapisz wszystko do iCloud ponownie" (pełny eksport) oraz "Sprawdź spójność" (porównanie hashy z `cloud_mirror_state`).
4. Konflikty: w v1 aplikacja nie czyta zmian przychodzących z iCloud poza odtworzeniem, więc konflikt powstaje tylko, gdy dwa urządzenia piszą do jednego katalogu. Aplikacja wykrywa to po `deviceId` w `manifest.json` i ostrzega, że drugie urządzenie nadpisze pliki. Pełna dwukierunkowa synchronizacja (`NSMetadataQuery` na zmiany, reguła ostatni zapis wygrywa po `updated_at`, `NSFileVersion` do rozwiązywania konfliktów) to v2 i wymaga od razu właściwego modelu w v1: każdy rekord ma `updated_at` i `device_id`.

`NSUbiquitousKeyValueStore` (limit 1 MB) przechowuje tylko preferencje: język pomocy, czy włączono Face ID, ostatnio wybrany rachunek. Nie przechowuje danych faktur.

Konfiguracja projektu: entitlement iCloud Documents, kontener `iCloud.pl.ksefektywnie.app`, w Info.plist `NSUbiquitousContainers` z `NSUbiquitousContainerIsDocumentScopePublic = true` i nazwą katalogu, aby pojawił się w aplikacji Pliki.

## 5. Pomoc dla użytkownika (wbudowana, zlokalizowana)

Pomoc jako zbiór ekranów Markdown w zasobach aplikacji, osobno na każdy język, ze zrzutami ekranu. Dostępna z ustawień i kontekstowo (ikona "?" na ekranie konfiguracji KSeF, na ekranie importu wyciągu i generowania pliku). Pierwsze uruchomienie prowadzi przez kreator onboardingu oparty na tych samych krokach.

### 5.1 Połączenie z KSeF krok po kroku
1. Co jest potrzebne: NIP firmy, dostęp do KSeF (Profil Zaufany, e-Dowód, podpis kwalifikowany lub pieczęć firmy; dla spółek dodatkowo nadane uprawnienie np. przez ZAW-FA).
2. Zaloguj się do Aplikacji Podatnika KSeF 2.0 w kontekście swojej firmy (NIP).
3. Przejdź do sekcji tokenów i wygeneruj nowy token z uprawnieniami: przeglądanie faktur (odczyt) oraz wystawianie faktur (zapis). Pomoc pokazuje oba pola wyboru i tłumaczy, co się stanie, gdy zabraknie jednego z nich.
4. Skopiuj token natychmiast: KSeF pokazuje go tylko raz.
5. W aplikacji: Ustawienia → KSeF → wybierz środowisko (produkcyjne), wpisz NIP, wklej token, naciśnij "Testuj połączenie".
6. Pierwsza synchronizacja: wybór zakresu dat (domyślnie 30 dni), ostrzeżenie o limitach KSeF i czasie trwania przy dużej liczbie faktur.
7. Rozwiązywanie problemów: tabela błędów (401/403 → token lub uprawnienia, 429 → limit, timeout → sieć), jak unieważnić i wygenerować token ponownie, czym różni się środowisko testowe (osobny adres, dane testowe) od produkcyjnego.

### 5.2 Pozostałe tematy pomocy
- Cykl życia faktury kosztowej i znaczenie statusów.
- Wystawianie faktury sprzedażowej: dane nabywcy z Białej Listy, stawki VAT, co oznacza odrzucenie przez KSeF i jak poprawić fakturę, czym jest UPO i jak przekazać fakturę klientowi.
- Jak przygotować plik przelewów i jak zaimportować go w banku (Erste/George, mBank, Elixir w pozostałych bankach), gdzie trafia plik po "Udostępnij".
- Jak wyeksportować wyciąg MT940/CSV w bankowości i zaimportować go w aplikacji; jak czytać poziomy pewności dopasowań.
- Bezpieczeństwo danych: co jest w telefonie, co w Keychain, co trafia do katalogu iCloud Drive i do kopii zapasowej iOS, jak usunąć dane.
- Katalog iCloud Drive: jak go znaleźć w Pliki i na Macu, jak udostępnić księgowej, jak odtworzyć dane na nowym telefonie, dlaczego token trzeba wpisać ponownie, co zrobić gdy iCloud jest wyłączony lub pełny.
- Tryb demo: przykładowe faktury do obejrzenia aplikacji bez tokena (potrzebny również dla recenzentów Apple).

## 6. Lokalizacja

- Język bazowy: polski. Tłumaczenia en/es/uk w String Catalog; przegląd przez native speakerów przed publikacją (szczególnie terminologia podatkowa po ukraińsku).
- Zawartość plików bankowych i tytuły przelewów pozostają po polsku/ASCII niezależnie od języka UI (wymóg formatów).
- Formaty kwot/dat wg `Locale`, waluta zawsze z kodem (PLN).
- Metadane App Store (nazwa, opis, zrzuty) w 4 językach; pomoc w 4 językach.

## 7. Harmonogram (1 developer iOS)

| Faza | Czas | Zakres | Kryterium wyjścia |
|---|---|---|---|
| 0. Fundament | 1 tydz. | Projekt Xcode, GRDB, schemat bazy, nawigacja, String Catalog, design system, CI + TestFlight | Pusta aplikacja na TestFlight w 4 językach |
| 1. KSeF i faktury | 3 tyg. | Auth, sync wznawialny, parser, lista/szczegół/statusy/notatki, test połączenia | Realne faktury z api-test, parser zgodny z fixture'ami Django |
| 2. Przelewy | 2 tyg. | Rachunki firmy, detekcja banku, 3 generatory, historia, reset, udostępnianie | Pliki bajt w bajt zgodne z golden files z Django |
| 3. Wyciągi | 2 tyg. | Import, 3 parsery, matcher, przegląd, zatwierdzanie | Zgodność dopasowań z wynikami Django na tych samych plikach |
| 4. Faktury wychodzące | 3 tyg. | Nabywcy + Biała Lista, formularz, generator FA(3), sesja wysyłkowa, statusy, UPO, PDF | Faktura testowa zaakceptowana na api-test z pobranym UPO |
| 5. iCloud Drive | 1,5 tyg. | Lustro write-through, struktura katalogu, odtworzenie na nowym urządzeniu, tryb bez iCloud, spójność | Świeża instalacja odtwarza komplet danych z katalogu; pliki czytelne w Pliki i na Macu |
| 6. Wykończenie | 2 tyg. | Face ID, ustawienia, Tip (StoreKit), pomoc + onboarding, dashboard, CSV, tryb demo, lokalne powiadomienia | Kompletna ścieżka użytkownika bez instrukcji zewnętrznej |
| 7. Beta i publikacja | 1–2 tyg. | Beta zamknięta (księgowi), poprawki, zrzuty ekranu, polityka prywatności, review | Zatwierdzenie App Store |

Razem ok. 15–17 tygodni. Faza 4 jest najbardziej ryzykowna czasowo, bo zależy od weryfikacji przebiegu wysyłki w KSeF 2.0 i schematu FA(3); warto ją rozpocząć od dwudniowego prototypu wysyłki na api-test jeszcze w fazie 1.

## 8. Strategia testów

- Golden files: skrypt `manage.py` w Django produkuje dla zestawu faktur testowych: sparsowane pola JSON, pliki Erste/mBank/Elixir, wyniki matchera. Testy Swift porównują wyniki portu z tymi plikami. Każda rozbieżność jest błędem portu, nie "różnicą implementacji".
- Fixture'y XML: FA(2) i FA(3) (oba namespace produkcyjne), korekty, MPP, faktury bez NRB, bez nazwy sprzedawcy (Imie/Nazwisko).
- Generator FA(3): walidacja XSD w testach (libxml2 przez `XMLParser` nie waliduje XSD; walidację robi skrypt Python z `lxml` na plikach wygenerowanych przez Swift, uruchamiany w CI).
- Testy liczenia kwot pozycji: porównanie z `InvoiceItem.calculate_amounts` dla przypadków brzegowych zaokrągleń.
- Testy integracyjne auth i query przeciw `api-test.ksef.mf.gov.pl` uruchamiane ręcznie (limity).
- Testy UI: ścieżka onboarding → sync → akceptacja → plik → import wyciągu → opłacona.
- iCloud: testy round-trip (baza → katalog → pusta baza → porównanie), testy w trybie bez iCloud, test odtworzenia na drugim symulatorze z tym samym kontem testowym; kodowanie/dekodowanie JSON weryfikowane schematem (JSON Schema w `Tests/Fixtures/schemas/`).

## 9. Ryzyka i wymagania App Store

- **Recenzja Apple bez dostępu do KSeF**: konieczny tryb demo z danymi przykładowymi i notatka dla recenzenta.
- **Nazwa i znak KSeF**: KSeF to system Ministerstwa Finansów; nazwa aplikacji nie powinna sugerować aplikacji urzędowej (np. "Faktury Kosztowe" z podtytułem "dla KSeF"). Ikona bez godła/logo MF.
- **Napiwki**: tylko IAP, bez obietnicy funkcji w zamian; opis "wesprzyj rozwój".
- **Prywatność**: etykieta "Dane nie są zbierane", publiczny URL polityki prywatności, `ITSAppUsesNonExemptEncryption = NO` (HTTPS i standardowe RSA).
- **Limity KSeF**: 64 XML/h przy pierwszej synchronizacji dużej firmy oznacza wiele godzin; UX musi to komunikować i działać partiami.
- **Background refresh**: niegwarantowany; nie obiecywać "automatycznej synchronizacji" w opisie sklepu.
- **Utrata telefonu = utrata danych**: w v1 polegamy na kopii zapasowej iOS; w pomocy wprost opisać, że token trzeba wygenerować ponownie na nowym urządzeniu (Keychain `ThisDeviceOnly`).
- **Przebieg wysyłki faktur**: implementacja w Django (`invoices/send` z surowym XML) może nie odpowiadać produkcyjnemu API 2.0; przed fazą 4 potwierdzić w dokumentacji i prototypem. Schemat FA(2) z Django jest już nieaktualny, iOS generuje FA(3).
- **Nazwa KS-eFektywnie**: zawiera ciąg "KSeF"; w opisie sklepu dodać zdanie, że aplikacja nie jest produktem Ministerstwa Finansów. Sprawdzić dostępność nazwy w App Store Connect i domeny na politykę prywatności.
- **iCloud Drive**: synchronizacja jest asynchroniczna i bez gwarancji czasu; pliki mogą być tylko "w chmurze" (placeholder) do czasu pobrania. Użytkownik z wyłączonym iCloud lub pełnym kontem musi dostać jasny komunikat. Dwa urządzenia piszące jednocześnie to ryzyko nadpisania, stąd ostrzeżenie po `deviceId` w v1 i właściwa synchronizacja w v2.
- **Zmiany API KSeF 2.0**: endpoint limitów jest heurystyczny również w Django; trzymać warstwę klienta w izolacji i mieć szybki cykl wydawniczy.

## 10. Podjęte decyzje (2026-10-11)

| Pytanie | Decyzja |
|---|---|
| Minimalna wersja iOS | 26 |
| Liczba firm | Jedna w v1, architektura gotowa na wiele podmiotów |
| Faktury wychodzące | W zakresie v1 |
| Export | CSV w v1, xlsx później |
| Nazwa | KS-eFektywnie |
| Lokalizacja kodu | `ios/` w tym repo |
| Kopia danych | Katalog iCloud Drive z JSON/XML/plikami bankowymi, lustro write-through + odtworzenie w v1, dwukierunkowa sync w v2 |

## 11. Następne kroki

1. Faza 0: szkielet projektu w `ios/`, pakiety Domain/KSeFClient/Persistence, String Catalog z 4 językami, TestFlight.
2. Skrypt `manage.py export_ios_fixtures` w Django generujący golden files do `ios/Tests/Fixtures/`.
3. Specyfikacja JSON (JSON Schema) dla katalogu iCloud, uzgodniona z serializerami REST w `apps/api/`.
4. Prototyp wysyłki faktury na api-test (sesja, szyfrowanie, status, UPO) w celu potwierdzenia przebiegu przed fazą 4.

## 12. Stan realizacji (2026-10-11)

### Zrobione
- **Faza 0**: projekt `ios/` (XcodeGen, iOS 26, Swift 6), pakiet `KSeFektywnieKit` z celami Domain, KSeFClient, Persistence i AppServices, String Catalogs pl/en/es/uk, ikona i kolor akcentu (placeholder).
- **Golden files**: komenda `manage.py export_ios_fixtures` w Django; testy Swift porównują port z wynikami Django.
- **Domain (logika faz 1–3)**: parser FA(2)/FA(3), mapowanie metadanych KSeF, scalanie przy ponownej synchronizacji, reguły statusów, generatory Erste/mBank/Elixir-0 (zgodne bajt w bajt, CP1250), rozpoznawanie banku po NRB, parsery MT940/CSV Erste/CSV VeloBank, matcher transakcji, walidacja NIP i NRB.
- **Persistence**: schemat v1 (UUID, `companyId` wszędzie, kwoty w groszach, `updatedAt`/`updatedByDevice`), repozytoria faktur i plików przelewów (generowanie, reset paczki), kolejka XML i logi synchronizacji.
- **KSeFClient**: autoryzacja tokenem (RSA-OAEP SHA-256 przez Security.framework), zapytania o metadane z podziałem na 89 dni i stronicowaniem, pobieranie XML, obsługa 429.
- **AppServices**: synchronizacja z trwałą kolejką XML (wznawianie po limicie), dane demo.
- **Aplikacja**: onboarding firmy, tryb demo, lista faktur z wyszukiwaniem i filtrami, szczegół z pozycjami, zmianą statusu, notatkami i historią, ustawienia (firma, rachunki z walidacją NRB, token KSeF w Keychain, test połączenia, synchronizacja), blokada Face ID, „Tip for developer” (StoreKit 2 + plik `Tips.storekit` do testów lokalnych), przewodnik po połączeniu z KSeF.
- Testy: 39 testów pakietu, build aplikacji na symulator iOS 26.

### Odchylenia od planu
- Golden files leżą w `ios/Packages/KSeFektywnieKit/Tests/DomainTests/Fixtures`, bo SwiftPM wymaga zasobów testów wewnątrz celu.
- Dodany czwarty cel `AppServices` (synchronizacja, demo), żeby orkiestracja była testowalna bez UI.
- Pomoc KSeF jest na razie w String Catalog zamiast osobnych plików Markdown; zrzuty ekranu dojdą w fazie wykończenia.

### Błędy znalezione w Django przy porcie (poprawione 2026-10-12)
1. **Elixir-0, MPP**: kwota VAT w tytule traciła przecinek (`/VAT/460000/` zamiast `/VAT/4600,00/`). Poprawione zgodnie z `format_danych.pdf`, s. 15–17.
2. **Import wyciągów**: ISO-8859-1 było sprawdzane przed Windows-1250, więc pliki CP1250 traciły polskie znaki. Wspólna funkcja `decode_statement` w obu widokach (web i API).
3. **Generator faktur wychodzących**: przepisany z FA(2) na FA(3) i walidowany XSD w testach. Poprawione przy okazji: ilość w `P_8B` i cena w `P_9A` (wcześniej `P_9A`/`P_10`), stawki 0%/NP w `P_13_6_1`/`P_13_8`, wymagane `Adnotacje`, `RodzajFaktury`, `DataWytworzeniaFa`, `JST`/`GV`, `RachunekBankowy`. Stawka ZW zgłasza błąd, dopóki formularz nie zbiera podstawy prawnej zwolnienia.
4. **Parser faktur zakupowych**: netto sumowało tylko `P_13_1`–`P_13_7`, gubiąc 0%, NP, odwrotne obciążenie i marżę. Poprawione w Django i w porcie Swift.

Do zweryfikowania osobno: przebieg wysyłki faktur w Django (`invoices/send` z surowym XML) prawdopodobnie nie odpowiada sesji interaktywnej KSeF 2.0 z szyfrowaniem AES (sekcja 4.5).

### Dodane 2026-10-12: zwolnienie z VAT i katalog pozycji (web + iOS)
- **Podstawa zwolnienia z VAT** na fakturze sprzedażowej: rodzaj (ustawa / dyrektywa / inna → `P_19A`/`P_19B`/`P_19C`) i treść, wymagane, gdy pozycja ma stawkę ZW. Podpowiedzi: wcześniej użyte podstawy + najczęstsze przepisy.
- **Katalog pozycji**: każda zapisana pozycja (nazwa + jednostka) jest zapamiętywana z ostatnią ceną i stawką; przy kolejnej fakturze można ją wybrać albo wpisać nową. Zarządzanie katalogiem: web `/outgoing/catalog/`, iOS Ustawienia → Katalog pozycji. API: `GET /api/outgoing/catalog/`.
- **iOS, faza 4 (bez wysyłki)**: zakładka Sprzedaż z szkicami faktur, formularz z nabywcami i katalogiem, generator FA(3) w Swift zgodny z Django (golden files walidowane XSD), podgląd i eksport XML. Wysyłka do KSeF czeka na weryfikację przebiegu sesji KSeF 2.0.

### Dodane 2026-10-12 (punkty 1–6 kolejności prac)
1. **Przelewy**: wybór zaakceptowanych faktur, rachunek obciążany, generowanie pliku, udostępnianie (Pliki, AirDrop, poczta), historia i reset paczki.
2. **Wyciągi**: import z aplikacji Pliki (MT940, CSV Erste/VeloBank, UTF-8 i Windows-1250), automatyczne dopasowanie z poziomem pewności, potwierdzanie, ręczne przypisanie, zatwierdzenie oznaczające faktury jako opłacone. Przykładowy wyciąg w trybie demo.
3. **Wysyłka do KSeF** zgodnie z oficjalną specyfikacją OpenAPI KSeF 2.0 (`/v2`): sesja interaktywna, AES-256-CBC + RSA-OAEP (certyfikat `SymmetricKeyEncryption`), hashe SHA-256, zamknięcie sesji, status (100/150/200/4xx) i UPO. Potwierdzenie przed wysyłką na produkcję, poprawka i ponowna wysyłka po odrzuceniu. **Nie zweryfikowane na żywo** — wymaga tokena KSeF ze środowiska testowego.
4. **iCloud Drive**: lustro różnicowe po każdej zmianie, struktura katalogu z sekcji 4.8, przywracanie przy pierwszym uruchomieniu, katalog lokalny gdy iCloud wyłączony, ostrzeżenie o drugim urządzeniu, „Zapisz wszystko ponownie”.
5. **Wykończenie**: podsumowanie kosztów (Swift Charts), eksport CSV, komunikaty błędów w 4 językach, synchronizacja w tle (BGAppRefreshTask) i powiadomienia o nowych fakturach, tymczasowa ikona (`scripts/generate_icon.swift`).
6. **Publikacja (przygotowanie)**: manifest prywatności, materiały do App Store w 4 językach, notatka dla recenzenta i polityka prywatności w `docs/ios-app-store.md`.

### Ustalenia ze specyfikacji KSeF 2.0 ważne dla Django
- Endpoint `invoices/send` używany w `apps/ksef/client.py` **nie istnieje** w API 2.0 — wysyłka faktur w Django nie może działać. Właściwy przebieg jak w iOS (sesja interaktywna).
- Django wybiera pierwszy certyfikat z `security/public-key-certificates`; KSeF zwraca dwa (token i klucz symetryczny) — należy wybierać po `usage`.

### Następne kroki
1. Test wysyłki na `api-test` z prawdziwym tokenem; potem ta sama poprawka wysyłki w Django (na `main`).
2. Pomoc ze zrzutami ekranu (gdy UI się ustabilizuje) i przegląd tłumaczeń es/uk.
3. Konto Apple Developer, App Store Connect, IAP, kontener iCloud, TestFlight z księgowymi.

### Poprzednie następne kroki (zrealizowane)
1. Ekrany przelewów (wybór faktur, rachunek, udostępnienie pliku, historia, reset) — logika i repozytorium są gotowe.
2. Ekrany wyciągów (import z Plików, przegląd dopasowań, zatwierdzanie) — wymaga repozytorium wyciągów w Persistence.
3. Prototyp wysyłki faktury FA(3) na `api-test` przed fazą 4.
4. Lustro iCloud Drive (faza 5) i przegląd tłumaczeń es/uk.
