# KS-eFektywnie — materiały do App Store

Stan: 2026-10-12. Teksty do wklejenia w App Store Connect. Tłumaczenia es/uk do przeglądu przez native speakera.

## Dane aplikacji

| Pole | Wartość |
|---|---|
| Nazwa | KS-eFektywnie |
| Bundle ID | `pl.ksefektywnie.app` |
| Kategoria | Finanse (dodatkowa: Biznes) |
| Wiek | 4+ |
| Cena | Bezpłatna; zakupy w aplikacji: 3 napiwki konsumowalne (`pl.ksefektywnie.tip.coffee`, `.lunch`, `.big`) |
| iCloud | kontener `iCloud.pl.ksefektywnie.app` (iCloud Documents) |
| Prywatność | „Dane nie są zbierane” — patrz polityka prywatności niżej |
| Szyfrowanie (eksport) | `ITSAppUsesNonExemptEncryption = NO`; aplikacja używa wyłącznie standardowych algorytmów systemu (HTTPS, RSA-OAEP, AES-256-CBC przez Security/CommonCrypto) do komunikacji z KSeF. **Do potwierdzenia przy pierwszym zgłoszeniu** — App Store Connect zada pytania o szyfrowanie. |

## Podtytuł (30 znaków)

- pl: Faktury z KSeF i przelewy
- en: KSeF invoices & bank transfers
- es: Facturas KSeF y transferencias
- uk: Рахунки KSeF і перекази

## Słowa kluczowe (100 znaków)

- pl: ksef,faktury,faktura,vat,przelew,elixir,mt940,wyciąg,mpp,księgowość,fa3,upo,nip,firma
- en: ksef,invoice,poland,vat,bank transfer,elixir,mt940,statement,accounting,e-invoice,fa3
- es: ksef,factura,polonia,iva,transferencia,elixir,mt940,extracto,contabilidad,e-factura
- uk: ksef,рахунок,фактура,польща,пдв,переказ,mt940,виписка,бухгалтерія,e-фактура

## Opis — pl

KS-eFektywnie to faktury z Krajowego Systemu e-Faktur na Twoim iPhonie — bez kont, bez serwera, bez abonamentu.

• Faktury kosztowe z KSeF: pobieranie listy i treści faktur, statusy (nowa, sporna, zaakceptowana, przekazana do opłacenia, opłacona), notatki i historia zmian.
• Przelewy: wybierz zaakceptowane faktury i wygeneruj plik dla banku — Erste Bank, mBank albo Elixir-0 dla pozostałych banków, także z podzieloną płatnością (MPP).
• Wyciągi: zaimportuj MT940 lub CSV, a aplikacja dopasuje przelewy do faktur i po zatwierdzeniu oznaczy je jako opłacone.
• Faktury sprzedażowe: wystaw fakturę FA(3), wyślij ją do KSeF i pobierz UPO. Pozycje i nabywców zapamiętujesz raz.
• Kopia w iCloud Drive: faktury (JSON i XML), pliki przelewów i wyciągi jako zwykłe pliki w Twoim iCloud.
• Bezpieczeństwo: dane tylko na telefonie, token KSeF w pęku kluczy, blokada Face ID.
• Przypomnienia: przypomnienie o płatności faktury lub o imporcie paczki przelewów trafia do aplikacji Przypomnienia i odhacza się samo po opłaceniu.
• Przewodnik krok po kroku: jak wygenerować token w KSeF i połączyć aplikację.

KS-eFektywnie nie jest aplikacją Ministerstwa Finansów.

## Description — en

KS-eFektywnie brings invoices from Poland's National e-Invoice System (KSeF) to your iPhone — no accounts, no server, no subscription.

• Purchase invoices from KSeF with statuses, notes and history.
• Bank transfers: generate a payment file for Erste Bank, mBank or Elixir-0, including split payment (MPP).
• Statements: import MT940 or CSV and match payments to invoices.
• Sales invoices: issue FA(3), send to KSeF and get the UPO receipt. Items and buyers are remembered.
• iCloud Drive copy: invoices (JSON and XML), payment files and statements as plain files in your iCloud.
• Security: data stays on your phone, KSeF token in the Keychain, Face ID lock.

KS-eFektywnie is not an app of the Polish Ministry of Finance.

## Descripción — es

KS-eFektywnie lleva a tu iPhone las facturas del Sistema Nacional de Facturas Electrónicas de Polonia (KSeF), sin cuentas, sin servidor y sin suscripción.

• Facturas de compra de KSeF con estados, notas e historial.
• Transferencias: genera el archivo de pagos para Erste Bank, mBank o Elixir-0, incluido el pago dividido (MPP).
• Extractos: importa MT940 o CSV y concilia los pagos con las facturas.
• Facturas de venta: emite FA(3), envíala a KSeF y descarga el UPO. Los productos y compradores se recuerdan.
• Copia en iCloud Drive: facturas (JSON y XML), archivos de pagos y extractos como archivos normales.
• Seguridad: los datos se quedan en tu teléfono, el token de KSeF en el llavero y bloqueo con Face ID.

KS-eFektywnie no es una aplicación del Ministerio de Finanzas de Polonia.

## Опис — uk

KS-eFektywnie переносить на ваш iPhone рахунки-фактури з Національної системи електронних рахунків Польщі (KSeF) — без облікових записів, без сервера, без підписки.

• Вхідні рахунки-фактури з KSeF зі статусами, нотатками та історією.
• Перекази: файл платежів для Erste Bank, mBank або Elixir-0, зокрема з розділеним платежем (MPP).
• Виписки: імпорт MT940 або CSV і зіставлення платежів із рахунками-фактурами.
• Рахунки-фактури на продаж: виставлення FA(3), надсилання до KSeF і отримання UPO. Позиції та покупці запам'ятовуються.
• Копія в iCloud Drive: рахунки-фактури (JSON і XML), файли платежів і виписки як звичайні файли.
• Безпека: дані лише на телефоні, токен KSeF у в'язці ключів, блокування Face ID.

KS-eFektywnie не є застосунком Міністерства фінансів Польщі.

## Notatka dla recenzenta (App Review Notes, en)

KS-eFektywnie works with KSeF, the Polish government e-invoicing system. Access to KSeF requires a Polish tax ID and a token issued by the Ministry of Finance, which reviewers do not have.

To review all features without KSeF:
1. On the first screen tap **“Try it with sample data”**. This creates a fictitious company with purchase invoices, two sales invoice drafts, a bank statement and a catalog of items.
2. Invoices tab: open an invoice, change its status, add a note. Use the chart button for the cost summary and the share button for CSV export.
3. Transfers tab: select invoices and tap “Generate transfer file”; the file can be shared.
4. Statements tab: open the sample statement, confirm the suggested match and tap “Confirm”.
5. Sales tab: open a draft, add an item from the catalog, preview the FA(3) XML. Sending to KSeF requires a token and is not available in demo mode.
6. Settings → “Tip for developer”: consumable tips that unlock nothing.

The app has no user accounts and no backend; all data is stored on the device and optionally in the user's own iCloud Drive.

## Polityka prywatności (do opublikowania pod stałym adresem URL)

**KS-eFektywnie — polityka prywatności**

1. Aplikacja nie zbiera danych osobowych i nie wysyła ich do autora. Nie ma kont użytkowników ani serwera autora.
2. Dane (faktury, pliki przelewów, wyciągi, ustawienia) są przechowywane na urządzeniu użytkownika. Baza danych jest chroniona szyfrowaniem plików iOS.
3. Token KSeF jest przechowywany wyłącznie w pęku kluczy urządzenia i nie trafia do kopii zapasowych ani do iCloud.
4. Jeśli użytkownik ma włączony iCloud Drive, aplikacja zapisuje kopię danych w prywatnym iCloud użytkownika. Autor nie ma do niej dostępu.
5. Jeśli użytkownik doda przypomnienie, aplikacja zapisuje je w aplikacji Przypomnienia iOS (na urządzeniu i w iCloud użytkownika, zgodnie z jego ustawieniami). Dostęp do Przypomnień służy wyłącznie do tworzenia, edycji i odhaczania przypomnień utworzonych przez aplikację.
6. Aplikacja łączy się wyłącznie z: API Krajowego Systemu e-Faktur (Ministerstwo Finansów) — w celu pobierania i wysyłania faktur na żądanie użytkownika; App Store (zakupy napiwków) — obsługiwane przez Apple.
7. Aplikacja nie używa reklam, analityki ani śledzenia.
8. Kontakt: [adres e-mail autora — do uzupełnienia].
