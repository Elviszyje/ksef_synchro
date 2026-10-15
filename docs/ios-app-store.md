# KS-eFektywnie — App Store Connect: wszystkie teksty i ustawienia

Stan: 2026-10-15 (wersja 0.2.1, przed pierwszym zgłoszeniem do recenzji). Teksty do wklejenia w App Store Connect (ASC), pole po polu, z limitami znaków. Długości pól z limitem sprawdzone skryptem.

Języki karty w sklepie: **polski (główny)**, angielski (U.K. lub U.S.), hiszpański (Spain), ukraiński. Tłumaczenia es/uk do przeglądu przez native speakera.

---

## 1. Informacje o aplikacji (App Information)

| Pole | Wartość |
|---|---|
| Nazwa (30) | `KS-eFektywnie` — ta sama we wszystkich językach |
| Język główny | Polski |
| Bundle ID | `pl.ksefektywnie.app` |
| SKU | `ksefektywnie-ios` (dowolny, niewidoczny dla użytkowników) |
| Kategoria główna | Finanse (Finance) |
| Kategoria dodatkowa | Biznes (Business) |
| Prawa do treści (Content Rights) | **Nie** — aplikacja nie zawiera, nie pokazuje i nie udostępnia treści stron trzecich |
| Adres polityki prywatności | pl: `https://ksefektywnie.ikolek.pl/polityka-prywatnosci.html` · en/es/uk: `https://ksefektywnie.ikolek.pl/en/privacy.html` (pole jest lokalizowane) |
| Kategoria wiekowa | 4+ (odpowiedzi w sekcji 4) |

### Podtytuł (30 znaków, lokalizowany)

| Język | Podtytuł | Znaki |
|---|---|---|
| pl | Faktury z KSeF i przelewy | 25 |
| en | KSeF invoices & bank transfers | 30 |
| es | Facturas KSeF y transferencias | 30 |
| uk | Рахунки KSeF і перекази | 23 |

---

## 2. Cena i dostępność (Pricing and Availability)

| Pole | Wartość |
|---|---|
| Cena | Bezpłatna (Free) |
| Dostępność | Wszystkie kraje albo tylko Polska. Aplikacja ma sens dla firm z polskim NIP-em, ale angielski, hiszpański i ukraiński interfejs przydaje się obcokrajowcom prowadzącym firmę w Polsce. **Rekomendacja: wszystkie kraje.** |
| Mac z Apple Silicon / Vision Pro | Wyłącz „Make this app available” dla Maca i Vision Pro (aplikacja nie była na nich testowana; iCloud Drive i Face ID działają inaczej). |
| Dystrybucja w UE (alternatywne sklepy) | Bez zmian (tylko App Store). |

---

## 3. Prywatność aplikacji (App Privacy)

**Data Types → „No, we do not collect data from this app”** („Dane nie są zbierane”).

Uzasadnienie (gdyby recenzent zapytał):
- Brak kont, serwera autora, analityki, reklam i SDK stron trzecich (jedyna zależność: GRDB — lokalna baza SQLite).
- Połączenia sieciowe idą do API Ministerstwa Finansów (KSeF, Biała Lista) wyłącznie na żądanie użytkownika i do App Store (napiwki). Apple nie traktuje przekazania danych do usługi, z której użytkownik sam korzysta (tu: rządowy system KSeF z jego tokenem), jako „zbierania” przez dewelopera.
- Kopia w iCloud Drive trafia do prywatnego iCloud użytkownika — deweloper nie ma do niej dostępu.
- „Zgłoś problem” otwiera aplikację Mail użytkownika; nic nie jest wysyłane automatycznie.

Manifest prywatności (`PrivacyInfo.xcprivacy`) jest w aplikacji: brak śledzenia, brak zbieranych danych, `UserDefaults` z powodem `CA92.1`.

---

## 4. Kategoria wiekowa (Age Rating) — odpowiedzi

Kwestionariusz ASC (wersja 2025+). Na wszystkie pytania o treści: **None / Brak**.

| Grupa pytań | Odpowiedź |
|---|---|
| Przemoc (kreskówkowa, realistyczna, długotrwała, krwawa) | None |
| Treści seksualne, nagość, wulgaryzmy, humor dla dorosłych | None |
| Alkohol, tytoń, narkotyki | None |
| Motywy grozy / strachu | None |
| Tematy medyczne / leczenie | None |
| Hazard symulowany / prawdziwy, konkursy | None / No |
| Nieograniczony dostęp do internetu (wbudowana przeglądarka) | **No** — linki otwierają się w Safari |
| Treści tworzone przez użytkowników, czat, komunikacja między użytkownikami | **No** |
| Reklamy | **No** |
| Kontrola rodzicielska / weryfikacja wieku w aplikacji | **No** |
| Lootboxy | No |

Wynik: **4+**.

---

## 5. Szyfrowanie (Export Compliance)

W `Info.plist` jest `ITSAppUsesNonExemptEncryption = NO`, więc ASC nie pyta przy każdym buildzie. Gdyby zapytał przy pierwszym zgłoszeniu:

1. *Does your app use encryption?* → **Yes** (HTTPS do API KSeF i Białej Listy; RSA-OAEP i AES-256-CBC wymagane przez KSeF przy uwierzytelnieniu i wysyłce faktur).
2. *What type of encryption algorithms does your app implement?* → **None of the algorithms mentioned above** — aplikacja nie ma własnej implementacji kryptografii, korzysta wyłącznie z szyfrowania wbudowanego w iOS (Security.framework, CommonCrypto, URLSession/TLS).
3. Dokumentacja eksportowa: niepotrzebna.

---

## 6. Napiwki (In-App Purchases)

### Zanim zaczniesz
- **Umowa Paid Apps**: ASC → Business (dawniej „Agreements, Tax, and Banking”). Umowy są przypisane do **konta dewelopera (zespołu)**, nie do aplikacji. Jeśli drugi projekt jest na tym samym koncie (zespół `X9AX9Q83H4`), umowa „Paid Apps” ze statusem **Active** obowiązuje też tutaj. Jeśli tamten projekt był na innym koncie (np. firmowym), trzeba ją podpisać tutaj. Sprawdź też, czy przy umowie są uzupełnione **dane bankowe i formularze podatkowe** (W-8BEN dla osoby z Polski) — bez nich zakupy nie przejdą recenzji.
- Zakupy dodaje się w ASC → aplikacja → **Monetization → In-App Purchases** → „+” → **Consumable**.
- Pierwsze zakupy muszą być zgłoszone **razem z wersją aplikacji**: w formularzu wersji, sekcja „In-App Purchases and Subscriptions” → wybierz wszystkie trzy.

### Produkty

| Reference Name (wewnętrzna) | Product ID | Typ | Cena (bazowo Polska) |
|---|---|---|---|
| Tip — coffee | `pl.ksefektywnie.tip.coffee` | Consumable | 4,99 zł |
| Tip — lunch | `pl.ksefektywnie.tip.lunch` | Consumable | 14,99 zł |
| Tip — big | `pl.ksefektywnie.tip.big` | Consumable | 49,99 zł |

Product ID muszą być dokładnie takie — aplikacja szuka ich po tych identyfikatorach. Ceny w innych krajach ASC przeliczy automatycznie.

### Nazwa (30) i opis (45) w każdym języku

| Produkt | Język | Display Name | Description |
|---|---|---|---|
| coffee | pl | Kawa dla autora | Mały napiwek. Niczego nie odblokowuje. |
| coffee | en | Coffee for the developer | A small tip. Unlocks nothing. |
| coffee | es | Un café para el desarrollador | Una pequeña propina. No desbloquea nada. |
| coffee | uk | Кава для розробника | Невеликі чайові. Нічого не відкривають. |
| lunch | pl | Obiad dla autora | Średni napiwek. Niczego nie odblokowuje. |
| lunch | en | Lunch for the developer | A medium tip. Unlocks nothing. |
| lunch | es | Almuerzo para el desarrollador | Una propina mediana. No desbloquea nada. |
| lunch | uk | Обід для розробника | Середні чайові. Нічого не відкривають. |
| big | pl | Wielkie dzięki | Duży napiwek. Niczego nie odblokowuje. |
| big | en | Huge thanks | A big tip. Unlocks nothing. |
| big | es | Muchísimas gracias | Una gran propina. No desbloquea nada. |
| big | uk | Величезна подяка | Великі чайові. Нічого не відкривають. |

### Informacje do recenzji każdego zakupu
- **Screenshot**: zrzut ekranu Ustawienia → „Tip for developer” (ten sam dla wszystkich trzech; min. 640×920, najprościej zrzut z iPhone'a).
- **Review Notes** (en):
  > Consumable tip for the developer. It unlocks no features or content; the app is fully functional without it. Available in Settings → “Tip for developer”.
- **Family Sharing**: wyłączone (dla consumable i tak niedostępne).
- Dostępność: wszystkie kraje, w których jest aplikacja.

Wytyczna 3.1.1 (napiwki jako IAP, bez obietnic funkcji) jest spełniona: ekran i opisy mówią wprost, że napiwek niczego nie odblokowuje.

---

## 7. Strona wersji (Version Information) — teksty lokalizowane

Adresy (pola lokalizowane):

| Pole | pl | en / es / uk |
|---|---|---|
| Support URL | `https://ksefektywnie.ikolek.pl/wsparcie.html` | `https://ksefektywnie.ikolek.pl/en/support.html` |
| Marketing URL | `https://ksefektywnie.ikolek.pl/` | `https://ksefektywnie.ikolek.pl/en/` |

Copyright: `2026 Bartosz Kołek`

### Tekst promocyjny (170, można zmieniać bez nowej wersji)

- **pl**: Faktury z KSeF, pliki przelewów dla banku, rozliczanie wyciągów i wystawianie faktur FA(3) — wszystko na iPhonie, bez konta i bez abonamentu.
- **en**: KSeF invoices, bank payment files, statement matching and FA(3) sales invoices — all on your iPhone, with no account and no subscription.
- **es**: Facturas de KSeF, archivos de pago para el banco, conciliación de extractos y facturas FA(3), todo en tu iPhone, sin cuenta ni suscripción.
- **uk**: Рахунки з KSeF, файли платежів для банку, звірка виписок і рахунки FA(3) — усе на iPhone, без облікового запису й підписки.

### Słowa kluczowe (100, po przecinku, bez spacji po przecinkach)

- **pl**: `ksef,faktury,faktura,vat,przelew,elixir,mt940,wyciąg,mpp,księgowość,fa3,upo,nip,biała lista,pdf`
- **en**: `ksef,invoice,poland,vat,bank transfer,elixir,mt940,statement,accounting,e-invoice,fa3,pdf`
- **es**: `ksef,factura,polonia,iva,transferencia,elixir,mt940,extracto,contabilidad,e-factura,pdf`
- **uk**: `ksef,рахунок,фактура,польща,пдв,переказ,mt940,виписка,бухгалтерія,e-фактура,pdf`

Nazwy aplikacji i kategorii nie powtarzamy w słowach kluczowych (Apple i tak je indeksuje).

### Opis — pl

KS-eFektywnie to faktury z Krajowego Systemu e-Faktur na Twoim iPhonie — bez konta, bez serwera, bez abonamentu.

FAKTURY KOSZTOWE
• Pobieranie faktur z KSeF z pełną treścią XML i wizualizacją PDF z kodem QR KSeF.
• Statusy płatności: nowa, sporna, do zapłaty, przelew przygotowany, opłacona — z notatkami i historią zmian.
• Szybkie gesty na liście, wyszukiwanie, filtry (ten miesiąc, poprzedni miesiąc, własny zakres dat, przeterminowane, MPP).
• Eksport listy do Excela (.xlsx) i PDF oraz podsumowanie kosztów.

PRZELEWY
• Plik dla banku z zatwierdzonych faktur: Erste Bank, mBank albo Elixir-0 dla pozostałych banków.
• Obsługa podzielonej płatności (MPP) i historia wygenerowanych paczek.

WYCIĄGI
• Import MT940 oraz CSV (Erste, VeloBank).
• Automatyczne dopasowanie przelewów do faktur; po zatwierdzeniu faktury oznaczają się jako opłacone.

FAKTURY SPRZEDAŻOWE
• Wystawianie faktur FA(3), wysyłka do KSeF i pobranie UPO.
• Dane nabywcy po NIP z Białej Listy podatników VAT.
• Katalog pozycji i nabywców — wpisujesz raz, wybierasz przy kolejnych fakturach.
• Własne szablony PDF: układ, kolor, logo, język etykiet (także dwujęzyczny), a układ strony ustawiasz, przeciągając sekcje.

BEZPIECZEŃSTWO I KOPIA
• Dane tylko na Twoim telefonie, token KSeF w pęku kluczy, blokada Face ID.
• Kopia w Twoim iCloud Drive jako zwykłe pliki (JSON, XML, pliki bankowe) — do odtworzenia na nowym telefonie.
• Przypomnienia o płatnościach w aplikacji Przypomnienia, odhaczane automatycznie po opłaceniu.

Przewodnik krok po kroku pokazuje, jak wygenerować token w KSeF i połączyć aplikację. Możesz też najpierw wypróbować wszystko na danych przykładowych.

Aplikacja jest bezpłatna i nie wyświetla reklam. Napiwek dla autora niczego nie odblokowuje.

KS-eFektywnie nie jest aplikacją Ministerstwa Finansów. KSeF to system Ministerstwa Finansów.

### Description — en

KS-eFektywnie brings invoices from Poland's National e-Invoice System (KSeF) to your iPhone — no account, no server, no subscription.

PURCHASE INVOICES
• Download invoices from KSeF with the full XML and a PDF view with the KSeF QR code.
• Payment statuses: new, disputed, to pay, transfer prepared, paid — with notes and history.
• Quick swipe actions, search and filters (this month, last month, custom date range, overdue, split payment).
• Export the list to Excel (.xlsx) and PDF, plus a cost summary.

BANK TRANSFERS
• Payment files from approved invoices: Erste Bank, mBank or Elixir-0 for other banks.
• Split payment (MPP) support and a history of generated batches.

STATEMENTS
• Import MT940 and CSV (Erste, VeloBank).
• Automatic matching of payments to invoices; confirmed invoices are marked as paid.

SALES INVOICES
• Issue FA(3) invoices, send them to KSeF and download the UPO receipt.
• Buyer details by tax ID from the Polish VAT White List.
• A catalog of items and buyers — enter them once, reuse them later.
• Custom PDF templates: layout, color, logo, label language (including bilingual); arrange the page by dragging sections.

SECURITY AND BACKUP
• Data stays on your phone, the KSeF token in the Keychain, Face ID lock.
• A copy in your own iCloud Drive as plain files (JSON, XML, bank files) to restore on a new phone.
• Payment reminders in the Reminders app, checked off automatically when paid.

A step-by-step guide shows how to generate a KSeF token and connect the app. You can also try everything with sample data first.

The app is free and has no ads. A tip for the developer unlocks nothing.

KS-eFektywnie is not an app of the Polish Ministry of Finance. KSeF is a system of the Polish Ministry of Finance.

### Descripción — es

KS-eFektywnie lleva a tu iPhone las facturas del Sistema Nacional de Facturas Electrónicas de Polonia (KSeF), sin cuenta, sin servidor y sin suscripción.

FACTURAS DE COMPRA
• Descarga de facturas de KSeF con el XML completo y vista en PDF con el código QR de KSeF.
• Estados de pago: nueva, en disputa, por pagar, transferencia preparada, pagada, con notas e historial.
• Gestos rápidos, búsqueda y filtros (este mes, mes anterior, rango de fechas, vencidas, pago dividido).
• Exportación de la lista a Excel (.xlsx) y PDF, y resumen de costes.

TRANSFERENCIAS
• Archivo de pagos de las facturas aprobadas: Erste Bank, mBank o Elixir-0 para otros bancos.
• Pago dividido (MPP) e historial de lotes generados.

EXTRACTOS
• Importación de MT940 y CSV (Erste, VeloBank).
• Conciliación automática de pagos con facturas; al confirmar, las facturas quedan pagadas.

FACTURAS DE VENTA
• Emisión de facturas FA(3), envío a KSeF y descarga del UPO.
• Datos del comprador por NIP desde la Lista Blanca de contribuyentes de IVA.
• Catálogo de productos y compradores: se introducen una vez y se reutilizan.
• Plantillas PDF propias: diseño, color, logotipo, idioma de las etiquetas (también bilingüe); la página se organiza arrastrando secciones.

SEGURIDAD Y COPIA
• Los datos se quedan en tu teléfono, el token de KSeF en el llavero y bloqueo con Face ID.
• Copia en tu iCloud Drive como archivos normales (JSON, XML, archivos bancarios) para restaurarla en un teléfono nuevo.
• Recordatorios de pago en la app Recordatorios, que se marcan solos al pagar.

Una guía paso a paso explica cómo generar el token de KSeF y conectar la app. También puedes probarlo todo con datos de ejemplo.

La app es gratuita y no tiene anuncios. La propina para el desarrollador no desbloquea nada.

KS-eFektywnie no es una aplicación del Ministerio de Finanzas de Polonia. KSeF es un sistema del Ministerio de Finanzas de Polonia.

### Опис — uk

KS-eFektywnie переносить на ваш iPhone рахунки-фактури з Національної системи електронних рахунків Польщі (KSeF) — без облікового запису, без сервера, без підписки.

ВХІДНІ РАХУНКИ
• Завантаження рахунків із KSeF з повним XML і переглядом у PDF з QR-кодом KSeF.
• Статуси оплати: новий, спірний, до оплати, переказ підготовлено, оплачено — з нотатками та історією.
• Швидкі жести, пошук і фільтри (цей місяць, попередній місяць, власний діапазон дат, прострочені, розділений платіж).
• Експорт списку в Excel (.xlsx) і PDF, підсумок витрат.

ПЕРЕКАЗИ
• Файл платежів із затверджених рахунків: Erste Bank, mBank або Elixir-0 для інших банків.
• Розділений платіж (MPP) та історія згенерованих пакетів.

ВИПИСКИ
• Імпорт MT940 і CSV (Erste, VeloBank).
• Автоматичне зіставлення платежів із рахунками; після підтвердження рахунки позначаються як оплачені.

РАХУНКИ НА ПРОДАЖ
• Виставлення рахунків FA(3), надсилання до KSeF і отримання UPO.
• Дані покупця за NIP з Білого списку платників ПДВ.
• Каталог позицій і покупців — вводите один раз, використовуєте знову.
• Власні шаблони PDF: макет, колір, логотип, мова підписів (зокрема двомовна); макет сторінки налаштовується перетягуванням розділів.

БЕЗПЕКА ТА КОПІЯ
• Дані лише на вашому телефоні, токен KSeF у в'язці ключів, блокування Face ID.
• Копія у вашому iCloud Drive як звичайні файли (JSON, XML, банківські файли) для відновлення на новому телефоні.
• Нагадування про оплату в застосунку «Нагадування», що позначаються автоматично після оплати.

Покроковий посібник показує, як згенерувати токен KSeF і підключити застосунок. Також можна спершу спробувати все на прикладових даних.

Застосунок безкоштовний і без реклами. Чайові для розробника нічого не відкривають.

KS-eFektywnie не є застосунком Міністерства фінансів Польщі. KSeF — система Міністерства фінансів Польщі.

---

## 8. Informacje dla recenzenta (App Review Information)

| Pole | Wartość |
|---|---|
| Sign-in required | **No** (aplikacja nie ma kont; tryb demo nie wymaga niczego) |
| Contact — imię i nazwisko | Bartosz Kołek |
| Contact — e-mail | bartosz@ikolek.pl |
| Contact — telefon | *(uzupełnij — wymagany, format międzynarodowy, np. +48 …)* |
| Attachment | niepotrzebny |

### Notes (en, do wklejenia)

> KS-eFektywnie works with KSeF, the Polish government e-invoicing system. Access to KSeF requires a Polish tax ID and a token issued by the Ministry of Finance, which reviewers do not have. The app has no user accounts and no backend; all data stays on the device and, optionally, in the user's own iCloud Drive.
>
> To review all features without KSeF:
> 1. On the first screen tap **“Try it with sample data”**. This creates a fictitious company with purchase invoices, sales invoice drafts, a bank statement and a catalog of items.
> 2. **Invoices** tab: use the date filter (This month / Last month / Date range), swipe an invoice right to approve it for payment, open an invoice to change its status, add a note and open the PDF view. The chart button shows a cost summary; the share button exports the list to Excel (.xlsx) or PDF.
> 3. **Transfers** tab: select invoices and tap “Generate transfer file”; the file can be shared. “History” lists generated batches.
> 4. **Statements** tab: open the sample statement, confirm the suggested match and tap “Confirm”.
> 5. **Sales** tab: open a draft, add an item from the catalog, preview the FA(3) XML or the PDF. Long-press an invoice in the list for “PDF preview”. In the buyer's tax ID field you can type 7740001454 — the buyer's name and address are fetched from the public Polish VAT White List (no login needed). Sending to KSeF requires a token and is not available in demo mode.
> 6. **Settings → Invoice templates**: open a template, then “Page layout” — touch and hold a section to drag it up or down, drag the QR code left or right. Changes are visible immediately.
> 7. **Settings → Help**: “Report a problem” opens a pre-filled email to the developer; links to the website and privacy policy.
> 8. **Settings → Tip for developer**: consumable tips that unlock nothing.
>
> “KSeF” is the name of the Ministry of Finance system the app connects to; the app states in its description that it is not a Ministry of Finance app.

---

## 9. Zrzuty ekranu (do zrobienia)

- Aplikacja jest tylko na iPhone'a → wymagany jeden zestaw **6,9″**: 1320 × 2868 px (pionowo), od 3 do 10 zrzutów. ASC przeskaluje je na mniejsze ekrany.
- Najprościej: symulator „iPhone 17 Pro Max”, tryb demo (`-demo`), ⌘S w symulatorze.
- Proponowana kolejność: 1) lista faktur z filtrem okresu, 2) szczegół faktury / PDF z kodem QR, 3) Przelewy z wygenerowanym plikiem, 4) przegląd wyciągu z dopasowaniami, 5) formularz faktury sprzedażowej (z Białą Listą), 6) edytor układu strony, 7) podsumowanie kosztów.
- Zrzuty mogą być wspólne dla wszystkich języków (ASC: „Use for all localizations”) albo osobne po przełączeniu języka symulatora.

---

## 10. Polityka prywatności

Pełny tekst jest opublikowany na stronie (`website/polityka-prywatnosci.html`, `website/en/privacy.html`) i dostępny w aplikacji: Ustawienia → Pomoc → Polityka prywatności. Obowiązuje od 15 października 2026. Najważniejsze punkty: brak zbierania danych, dane na urządzeniu i w iCloud użytkownika, token KSeF tylko w pęku kluczy, połączenia wyłącznie z API KSeF, Białą Listą MF (tylko NIP nabywcy, na żądanie) i App Store, zgłoszenia przez Mail na bartosz@ikolek.pl.

---

## 11. Lista kontrolna przed „Submit for Review”

- [ ] Strona `ksefektywnie.ikolek.pl` działa po HTTPS (polityka, wsparcie).
- [ ] Umowa Paid Apps aktywna, dane bankowe i podatkowe uzupełnione.
- [ ] 3 napiwki założone, ze zrzutem i notatką, dodane do wersji.
- [ ] App Privacy: „Data Not Collected” — opublikowane.
- [ ] Kategoria wiekowa wypełniona (4+).
- [ ] Teksty wersji w 4 językach, URL-e wsparcia i marketingu, copyright.
- [ ] Zrzuty 6,9″.
- [ ] Telefon kontaktowy dla recenzenta.
- [ ] Build z numerem wersji publicznej (np. 1.0.0) wybrany w wersji.
- [ ] Wysyłka faktury na `api-test` sprawdzona na żywo (UPO, kod QR).
