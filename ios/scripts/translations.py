"""
Tłumaczenia UI aplikacji KS-eFektywnie (źródło: polski).

Generuje KSeFektywnie/Resources/Localizable.xcstrings i InfoPlist.xcstrings.
Sprawdza też, czy każdy klucz wyciągnięty przez kompilator (.stringsdata) ma
tłumaczenie — uruchamiaj po buildzie:

    python3 scripts/translations.py [--derived-data .build/DerivedData]

Tłumaczenia es/uk wymagają przeglądu przez native speakera przed publikacją.
"""
import argparse, glob, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAME = object()  # klucz niezmienny we wszystkich językach

T = {
 "%@ %@ × %@ · VAT %@": SAME,
 "%@ → %@": SAME,
 "%@.xml": SAME,
 "%lld": SAME,
 "KS-eFektywnie": SAME,
 "KSeF": SAME,
 "MPP": SAME,
 "NIP": SAME,
 "VAT": SAME,
 "OK": SAME,
 "ksef.podatki.gov.pl": SAME,
 "Adres": ("Address", "Dirección", "Адреса"),
 "Adres (do plików bankowych)": ("Address (for bank files)", "Dirección (para archivos bancarios)", "Адреса (для банківських файлів)"),
 "Anuluj": ("Cancel", "Cancelar", "Скасувати"),
 "Aplikacja działa w całości na Twoim telefonie, bez kont i reklam. Jeśli oszczędza Ci czas, możesz postawić autorowi kawę.":
   ("The app runs entirely on your phone, with no accounts and no ads. If it saves you time, you can buy the developer a coffee.",
    "La aplicación funciona por completo en tu teléfono, sin cuentas ni anuncios. Si te ahorra tiempo, puedes invitar al desarrollador a un café.",
    "Застосунок повністю працює на вашому телефоні, без облікових записів і реклами. Якщо він заощаджує вам час, можете пригостити розробника кавою."),
 "Aplikacja jest bezpłatna i nie wyświetla reklam. Napiwek wspiera jej dalszy rozwój i niczego nie odblokowuje.":
   ("The app is free and shows no ads. A tip supports further development and does not unlock anything.",
    "La aplicación es gratuita y no muestra anuncios. La propina apoya su desarrollo y no desbloquea nada.",
    "Застосунок безкоштовний і не показує реклами. Чайові підтримують його розвиток і нічого не відкривають."),
 "Bezpieczeństwo": ("Security", "Seguridad", "Безпека"),
 "Blokada %@": ("%@ lock", "Bloqueo con %@", "Блокування %@"),
 "Brak faktur": ("No invoices", "No hay facturas", "Немає рахунків-фактур"),
 "Brak numeru rachunku — faktury nie można dodać do przelewu.":
   ("No bank account number — this invoice cannot be added to a transfer.",
    "Sin número de cuenta: la factura no se puede añadir a una transferencia.",
    "Немає номера рахунку — цей рахунок-фактуру не можна додати до переказу."),
 "Brutto": ("Gross", "Bruto", "Брутто"),
 "Błąd 401": ("Error 401", "Error 401", "Помилка 401"),
 "Błąd 403": ("Error 403", "Error 403", "Помилка 403"),
 "Czego potrzebujesz": ("What you need", "Qué necesitas", "Що вам потрібно"),
 "Dalej": ("Continue", "Continuar", "Далі"),
 "Data wystawienia": ("Issue date", "Fecha de emisión", "Дата виставлення"),
 "Dodaj": ("Add", "Añadir", "Додати"),
 "Dodaj notatkę": ("Add a note", "Añadir una nota", "Додати нотатку"),
 "Dodaj rachunek": ("Add account", "Añadir cuenta", "Додати рахунок"),
 "Dziękuję!": ("Thank you!", "¡Gracias!", "Дякую!"),
 "Dziękuję, że korzystasz z KS-eFektywnie!": ("Thank you for using KS-eFektywnie!", "¡Gracias por usar KS-eFektywnie!", "Дякую, що користуєтеся KS-eFektywnie!"),
 "Faktury": ("Invoices", "Facturas", "Фактури"),
 "Faktury czekające na pobranie treści: %lld": ("Invoices waiting for content download: %lld", "Facturas pendientes de descargar contenido: %lld", "Рахунки-фактури, що очікують завантаження вмісту: %lld"),
 "Faktury kosztowe z KSeF, pliki przelewów i rozliczanie wyciągów — wszystko na Twoim telefonie, bez zakładania konta.":
   ("Purchase invoices from KSeF, bank transfer files and statement reconciliation — all on your phone, no account needed.",
    "Facturas de compra desde KSeF, archivos de transferencias y conciliación de extractos: todo en tu teléfono, sin crear una cuenta.",
    "Вхідні рахунки-фактури з KSeF, файли переказів і звірка виписок — усе на вашому телефоні, без створення облікового запису."),
 "Faktury, pliki przelewów, wyciągi i token KSeF zostaną usunięte z telefonu. Faktury można ponownie pobrać z KSeF.":
   ("Invoices, transfer files, statements and the KSeF token will be removed from this phone. Invoices can be downloaded from KSeF again.",
    "Las facturas, los archivos de transferencias, los extractos y el token de KSeF se eliminarán del teléfono. Las facturas se pueden volver a descargar de KSeF.",
    "Рахунки-фактури, файли переказів, виписки й токен KSeF буде видалено з телефону. Рахунки-фактури можна знову завантажити з KSeF."),
 "Filtry": ("Filters", "Filtros", "Фільтри"),
 "Firma": ("Company", "Empresa", "Компанія"),
 "Forma płatności": ("Payment method", "Forma de pago", "Спосіб оплати"),
 "Format pliku: %@": ("File format: %@", "Formato de archivo: %@", "Формат файлу: %@"),
 "Gdy coś nie działa": ("Troubleshooting", "Si algo no funciona", "Якщо щось не працює"),
 "Historia": ("History", "Historial", "Історія"),
 "Instrukcja krok po kroku": ("Step-by-step guide", "Guía paso a paso", "Покрокова інструкція"),
 "Jak połączyć się z KSeF": ("How to connect to KSeF", "Cómo conectarse a KSeF", "Як підключитися до KSeF"),
 "KS-eFektywnie nie jest aplikacją Ministerstwa Finansów.": ("KS-eFektywnie is not an app of the Polish Ministry of Finance.", "KS-eFektywnie no es una aplicación del Ministerio de Finanzas de Polonia.", "KS-eFektywnie не є застосунком Міністерства фінансів Польщі."),
 "KSeF czasowo ogranicza liczbę zapytań. Aplikacja poda, kiedy można spróbować ponownie.":
   ("KSeF temporarily limits the number of requests. The app will tell you when you can try again.",
    "KSeF limita temporalmente el número de solicitudes. La aplicación te indicará cuándo volver a intentarlo.",
    "KSeF тимчасово обмежує кількість запитів. Застосунок підкаже, коли можна спробувати знову."),
 "KSeF pokazuje token tylko raz. Skopiuj go do schowka. Jeśli go zgubisz, unieważnij stary token i wygeneruj nowy.":
   ("KSeF shows the token only once. Copy it to the clipboard. If you lose it, revoke the old token and generate a new one.",
    "KSeF muestra el token solo una vez. Cópialo al portapapeles. Si lo pierdes, revoca el token anterior y genera uno nuevo.",
    "KSeF показує токен лише один раз. Скопіюйте його в буфер обміну. Якщо ви його втратите, анулюйте старий токен і згенеруйте новий."),
 "Konfiguracja": ("Setup", "Configuración", "Налаштування"),
 "Kwoty": ("Amounts", "Importes", "Суми"),
 "Limit zapytań": ("Request limit", "Límite de solicitudes", "Ліміт запитів"),
 "Mechanizm podzielonej płatności": ("Split payment mechanism (MPP)", "Mecanismo de pago dividido (MPP)", "Механізм розділеного платежу (MPP)"),
 "NIP firmy i możliwość zalogowania się do KSeF: Profil Zaufany, e-dowód, podpis kwalifikowany albo pieczęć firmy. W spółkach osoba logująca się musi mieć nadane uprawnienia w KSeF, np. przez zawiadomienie ZAW-FA złożone w urzędzie skarbowym.":
   ("Your company's NIP (tax ID) and a way to sign in to KSeF: Profil Zaufany, Polish e-ID, a qualified signature or a company seal. In companies, the person signing in must have KSeF permissions granted, e.g. via the ZAW-FA notification filed with the tax office.",
    "El NIP (número fiscal) de la empresa y una forma de iniciar sesión en KSeF: Profil Zaufany, DNI electrónico polaco, firma cualificada o sello de empresa. En las sociedades, la persona que inicia sesión debe tener permisos en KSeF, p. ej. mediante la notificación ZAW-FA presentada en la oficina tributaria.",
    "NIP (податковий номер) компанії та спосіб увійти до KSeF: Profil Zaufany, польський e-ID, кваліфікований підпис або печатка компанії. У товариствах особа, яка входить, повинна мати надані повноваження в KSeF, напр. через повідомлення ZAW-FA, подане до податкової."),
 "Na komputerze lub w przeglądarce telefonu wejdź na stronę ksef.podatki.gov.pl, otwórz Aplikację Podatnika KSeF i zaloguj się w kontekście NIP swojej firmy.":
   ("On a computer or in your phone's browser, go to ksef.podatki.gov.pl, open the KSeF Taxpayer Application (Aplikacja Podatnika KSeF) and sign in for your company's NIP.",
    "En un ordenador o en el navegador del teléfono, entra en ksef.podatki.gov.pl, abre la Aplicación del Contribuyente KSeF (Aplikacja Podatnika KSeF) e inicia sesión con el NIP de tu empresa.",
    "На комп'ютері або в браузері телефона перейдіть на ksef.podatki.gov.pl, відкрийте Застосунок платника KSeF (Aplikacja Podatnika KSeF) і увійдіть у контексті NIP вашої компанії."),
 "Naciśnij „Synchronizuj teraz” albo przeciągnij listę faktur w dół. Aplikacja najpierw pobierze listę faktur z ostatnich 30 dni, a potem ich treść. KSeF pozwala pobrać około 64 faktur na godzinę, więc przy dużej liczbie faktur treść będzie uzupełniana przy kolejnych synchronizacjach.":
   ("Tap “Sync now” or pull down the invoice list. The app first downloads the list of invoices from the last 30 days and then their content. KSeF allows about 64 invoices per hour, so with many invoices the content is filled in during later syncs.",
    "Pulsa «Sincronizar ahora» o desliza hacia abajo la lista de facturas. La aplicación descarga primero la lista de facturas de los últimos 30 días y después su contenido. KSeF permite unas 64 facturas por hora, así que con muchas facturas el contenido se completará en sincronizaciones posteriores.",
    "Натисніть «Синхронізувати зараз» або потягніть список рахунків-фактур донизу. Застосунок спершу завантажить список рахунків-фактур за останні 30 днів, а потім їхній вміст. KSeF дозволяє завантажити близько 64 рахунків-фактур на годину, тож за великої кількості вміст буде доповнюватися під час наступних синхронізацій."),
 "Nazwa": ("Name", "Nombre", "Назва"),
 "Nazwa firmy": ("Company name", "Nombre de la empresa", "Назва компанії"),
 "Netto": ("Net", "Neto", "Нетто"),
 "Nie skonfigurowano": ("Not set up", "Sin configurar", "Не налаштовано"),
 "Nieprawidłowy NIP — sprawdź 10 cyfr.": ("Invalid NIP — check the 10 digits.", "NIP no válido: comprueba los 10 dígitos.", "Невірний NIP — перевірте 10 цифр."),
 "Nieprawidłowy numer rachunku — sprawdź cyfry kontrolne.": ("Invalid account number — check the check digits.", "Número de cuenta no válido: comprueba los dígitos de control.", "Невірний номер рахунку — перевірте контрольні цифри."),
 "Notatki": ("Notes", "Notas", "Нотатки"),
 "Nowa": ("New", "Nueva", "Новий"),
 "Nowy telefon": ("New phone", "Teléfono nuevo", "Новий телефон"),
 "Numer KSeF": ("KSeF number", "Número KSeF", "Номер KSeF"),
 "Numer rachunku (26 cyfr)": ("Account number (26 digits)", "Número de cuenta (26 dígitos)", "Номер рахунку (26 цифр)"),
 "Numer, sprzedawca, NIP": ("Number, seller, NIP", "Número, vendedor, NIP", "Номер, продавець, NIP"),
 "Odblokuj": ("Unlock", "Desbloquear", "Розблокувати"),
 "Odblokuj dostęp do faktur": ("Unlock access to your invoices", "Desbloquea el acceso a tus facturas", "Розблокуйте доступ до рахунків-фактур"),
 "Opis (opcjonalnie)": ("Description (optional)", "Descripción (opcional)", "Опис (необов'язково)"),
 "Opłacona": ("Paid", "Pagada", "Оплачений"),
 "Ostatnia synchronizacja: %@": ("Last sync: %@", "Última sincronización: %@", "Остання синхронізація: %@"),
 "Otwórz Ustawienia → Połączenie z KSeF. Wybierz środowisko Produkcyjne, sprawdź NIP, wklej token, naciśnij „Zapisz token”, a potem „Testuj połączenie”. Token zostaje tylko w pęku kluczy tego iPhone'a.":
   ("Open Settings → KSeF connection. Choose the Production environment, check the NIP, paste the token, tap “Save token” and then “Test connection”. The token stays only in this iPhone's keychain.",
    "Abre Ajustes → Conexión con KSeF. Elige el entorno de Producción, comprueba el NIP, pega el token, pulsa «Guardar token» y después «Probar conexión». El token se guarda solo en el llavero de este iPhone.",
    "Відкрийте Налаштування → Підключення до KSeF. Виберіть виробниче середовище, перевірте NIP, вставте токен, натисніть «Зберегти токен», а потім «Перевірити з'єднання». Токен зберігається лише у в'язці ключів цього iPhone."),
 "Pierwsza synchronizacja": ("First sync", "Primera sincronización", "Перша синхронізація"),
 "Po włączeniu aplikacja wymaga uwierzytelnienia przy uruchomieniu i po powrocie z tła.": ("When enabled, the app requires authentication at launch and when returning from the background.", "Si se activa, la aplicación pedirá autenticación al abrirse y al volver del segundo plano.", "Після ввімкнення застосунок вимагатиме автентифікації під час запуску та після повернення з фону."),
 "Pobrano %lld faktur, nowych: %lld.": ("Downloaded %lld invoices, new: %lld.", "Descargadas %lld facturas, nuevas: %lld.", "Завантажено рахунків-фактур: %lld, нових: %lld."),
 "Pomoc": ("Help", "Ayuda", "Допомога"),
 "Potwierdź włączenie blokady": ("Confirm turning on the lock", "Confirma la activación del bloqueo", "Підтвердьте ввімкнення блокування"),
 "Pozycje": ("Line items", "Líneas", "Позиції"),
 "Połącz aplikację z KSeF w Ustawieniach, aby pobrać faktury kosztowe.": ("Connect the app to KSeF in Settings to download purchase invoices.", "Conecta la aplicación con KSeF en Ajustes para descargar las facturas de compra.", "Підключіть застосунок до KSeF у Налаштуваннях, щоб завантажити вхідні рахунки-фактури."),
 "Połączenie działa.": ("The connection works.", "La conexión funciona.", "З'єднання працює."),
 "Połączenie z KSeF": ("KSeF connection", "Conexión con KSeF", "Підключення до KSeF"),
 "Produkcyjne": ("Production", "Producción", "Виробниче"),
 "Przeciągnij w dół, aby zsynchronizować z KSeF.": ("Pull down to sync with KSeF.", "Desliza hacia abajo para sincronizar con KSeF.", "Потягніть донизу, щоб синхронізувати з KSeF."),
 "Przekazano do opłacenia": ("Sent for payment", "Enviada para pago", "Передано до оплати"),
 "Przelewy": ("Transfers", "Transferencias", "Перекази"),
 "Płatność": ("Payment", "Pago", "Оплата"),
 "Rachunek": ("Account", "Cuenta", "Рахунок"),
 "Rachunek obciążany przy przelewach. Format pliku dla banku jest dobierany automatycznie: Erste i mBank mają własne formaty, pozostałe banki Elixir-0.":
   ("The account debited for transfers. The bank file format is chosen automatically: Erste and mBank have their own formats, other banks use Elixir-0.",
    "La cuenta que se carga en las transferencias. El formato del archivo bancario se elige automáticamente: Erste y mBank tienen formatos propios; los demás bancos usan Elixir-0.",
    "Рахунок, з якого списуються перекази. Формат банківського файлу вибирається автоматично: Erste і mBank мають власні формати, інші банки — Elixir-0."),
 "Rachunki bankowe": ("Bank accounts", "Cuentas bancarias", "Банківські рахунки"),
 "Skopiuj token od razu": ("Copy the token right away", "Copia el token enseguida", "Одразу скопіюйте токен"),
 "Sporna": ("Disputed", "En disputa", "Спірний"),
 "Sprzedawca": ("Seller", "Vendedor", "Продавець"),
 "Sprzedaż": ("Sales", "Ventas", "Продажі"),
 "Status": ("Status", "Estado", "Статус"),
 "Synchronizuj teraz": ("Sync now", "Sincronizar ahora", "Синхронізувати зараз"),
 "Ta część aplikacji pojawi się w kolejnej wersji roboczej.": ("This part of the app will arrive in the next development build.", "Esta parte de la aplicación llegará en la próxima versión de desarrollo.", "Ця частина застосунку з'явиться в наступній робочій версії."),
 "Termin płatności": ("Due date", "Fecha de vencimiento", "Термін оплати"),
 "Termin: %@": ("Due: %@", "Vence: %@", "Термін: %@"),
 "Testowe": ("Test", "Pruebas", "Тестове"),
 "Testuj połączenie": ("Test connection", "Probar conexión", "Перевірити з'єднання"),
 "Tip for developer": ("Tip for developer", "Propina para el desarrollador", "Чайові для розробника"),
 "Token": ("Token", "Token", "Токен"),
 "Token jest nieprawidłowy, wygasł albo został wygenerowany dla innego NIP. Wygeneruj nowy token.": ("The token is invalid, has expired or was generated for a different NIP. Generate a new token.", "El token no es válido, ha caducado o se generó para otro NIP. Genera un token nuevo.", "Токен недійсний, прострочений або згенерований для іншого NIP. Згенеруйте новий токен."),
 "Token jest przechowywany wyłącznie w pęku kluczy tego iPhone'a. Nie trafia do kopii zapasowej ani do iCloud.": ("The token is stored only in this iPhone's keychain. It is not included in backups or iCloud.", "El token se guarda solo en el llavero de este iPhone. No se incluye en copias de seguridad ni en iCloud.", "Токен зберігається лише у в'язці ключів цього iPhone. Він не потрапляє до резервних копій чи iCloud."),
 "Token nie jest przenoszony na inne urządzenia. Na nowym iPhonie wklej token ponownie albo wygeneruj nowy.": ("The token is not transferred to other devices. On a new iPhone, paste the token again or generate a new one.", "El token no se transfiere a otros dispositivos. En un iPhone nuevo, pega el token de nuevo o genera uno nuevo.", "Токен не переноситься на інші пристрої. На новому iPhone вставте токен знову або згенеруйте новий."),
 "Token nie ma potrzebnych uprawnień. Wygeneruj token z uprawnieniem do przeglądania faktur.": ("The token lacks the required permissions. Generate a token with permission to view invoices.", "El token no tiene los permisos necesarios. Genera un token con permiso para consultar facturas.", "Токен не має потрібних повноважень. Згенеруйте токен із повноваженням на перегляд рахунків-фактур."),
 "Token zapisany": ("Token saved", "Token guardado", "Токен збережено"),
 "Treść %lld faktur zostanie pobrana po %@ (limit KSeF).": ("Content of %lld invoices will be downloaded after %@ (KSeF limit).", "El contenido de %lld facturas se descargará después de las %@ (límite de KSeF).", "Вміст рахунків-фактур (%lld) буде завантажено після %@ (ліміт KSeF)."),
 "Treść %lld faktur zostanie pobrana przy kolejnej synchronizacji.": ("Content of %lld invoices will be downloaded during the next sync.", "El contenido de %lld facturas se descargará en la próxima sincronización.", "Вміст рахунків-фактур (%lld) буде завантажено під час наступної синхронізації."),
 "Treść faktury zostanie pobrana z KSeF przy kolejnej synchronizacji.": ("The invoice content will be downloaded from KSeF during the next sync.", "El contenido de la factura se descargará de KSeF en la próxima sincronización.", "Вміст рахунку-фактури буде завантажено з KSeF під час наступної синхронізації."),
 "Twoja firma": ("Your company", "Tu empresa", "Ваша компанія"),
 "Twoje wsparcie bardzo pomaga w dalszym rozwoju aplikacji.": ("Your support really helps the app keep improving.", "Tu apoyo ayuda mucho a seguir mejorando la aplicación.", "Ваша підтримка дуже допомагає розвитку застосунку."),
 "Tylko podzielona płatność": ("Split payment only", "Solo pago dividido", "Лише розділений платіж"),
 "Tylko przeterminowane": ("Overdue only", "Solo vencidas", "Лише прострочені"),
 "Udostępnij XML": ("Share XML", "Compartir XML", "Поділитися XML"),
 "Ustawienia": ("Settings", "Ajustes", "Налаштування"),
 "Usunąć wszystkie dane z tego iPhone'a?": ("Delete all data from this iPhone?", "¿Eliminar todos los datos de este iPhone?", "Видалити всі дані з цього iPhone?"),
 "Usuń": ("Delete", "Eliminar", "Видалити"),
 "Usuń token": ("Remove token", "Eliminar token", "Видалити токен"),
 "Usuń wszystkie dane": ("Delete all data", "Eliminar todos los datos", "Видалити всі дані"),
 "W plikach Elixir-0 nazwa i adres są skracane do 35 znaków każde.": ("In Elixir-0 files the name and address are each shortened to 35 characters.", "En los archivos Elixir-0, el nombre y la dirección se acortan a 35 caracteres cada uno.", "У файлах Elixir-0 назва та адреса скорочуються до 35 символів кожна."),
 "W sekcji tokenów utwórz nowy token. Zaznacz uprawnienie do przeglądania (odczytu) faktur. Jeśli chcesz wystawiać w aplikacji faktury sprzedażowe, zaznacz też uprawnienie do wystawiania faktur. Nadaj tokenowi opis, np. „KS-eFektywnie iPhone”.":
   ("In the tokens section, create a new token. Select the permission to view (read) invoices. If you want to issue sales invoices in the app, also select the permission to issue invoices. Give the token a description, e.g. “KS-eFektywnie iPhone”.",
    "En la sección de tokens, crea un token nuevo. Marca el permiso para consultar (leer) facturas. Si quieres emitir facturas de venta en la aplicación, marca también el permiso para emitir facturas. Pon al token una descripción, p. ej. «KS-eFektywnie iPhone».",
    "У розділі токенів створіть новий токен. Позначте повноваження на перегляд (читання) рахунків-фактур. Якщо хочете виставляти в застосунку рахунки-фактури на продаж, позначте також повноваження на виставлення рахунків-фактур. Додайте опис токена, напр. «KS-eFektywnie iPhone»."),
 "Wypróbuj na przykładowych danych": ("Try it with sample data", "Pruébala con datos de ejemplo", "Спробувати на прикладових даних"),
 "Fikcyjna firma i faktury, bez łączenia z KSeF. Dane demo usuniesz w Ustawieniach.": ("A fictitious company and invoices, without connecting to KSeF. You can delete the demo data in Settings.", "Una empresa y facturas ficticias, sin conectarse a KSeF. Puedes eliminar los datos de demostración en Ajustes.", "Вигадана компанія та рахунки-фактури, без підключення до KSeF. Демо-дані можна видалити в Налаштуваннях."),
 "Tryb demo — dane przykładowe": ("Demo mode — sample data", "Modo demo: datos de ejemplo", "Демо-режим — прикладові дані"),
 "%@ %@ × %@ · %@": SAME,
 "%@ · %@ netto · %@": ("%@ · %@ net · %@", "%@ · %@ neto · %@", "%@ · %@ нетто · %@"),
 "%lld×": SAME,
 "XML FA(3)": SAME,
 "NIP %@": SAME,
 "Adres nabywcy": ("Buyer address", "Dirección del comprador", "Адреса покупця"),
 "Brak faktur sprzedażowych": ("No sales invoices", "No hay facturas de venta", "Немає рахунків-фактур на продаж"),
 "Brak zapisanych nabywców": ("No saved buyers", "No hay compradores guardados", "Немає збережених покупців"),
 "Cena jednostkowa netto": ("Net unit price", "Precio unitario neto", "Ціна за одиницю нетто"),
 "Dane faktury": ("Invoice details", "Datos de la factura", "Дані рахунку-фактури"),
 "Data dostawy": ("Delivery date", "Fecha de entrega", "Дата поставки"),
 "Data dostawy inna niż wystawienia": ("Delivery date differs from issue date", "Fecha de entrega distinta de la de emisión", "Дата поставки відрізняється від дати виставлення"),
 "Dodaj co najmniej jedną pozycję.": ("Add at least one line item.", "Añade al menos una línea.", "Додайте щонайменше одну позицію."),
 "Dodaj pozycję": ("Add item", "Añadir línea", "Додати позицію"),
 "Dodaj rachunek w Ustawieniach": ("Add an account in Settings", "Añade una cuenta en Ajustes", "Додайте рахунок у Налаштуваннях"),
 "Gotowe": ("Done", "Listo", "Готово"),
 "Gotówka": ("Cash", "Efectivo", "Готівка"),
 "Ilość": ("Quantity", "Cantidad", "Кількість"),
 "Jednostka": ("Unit", "Unidad", "Одиниця"),
 "Katalog jest pusty": ("The catalog is empty", "El catálogo está vacío", "Каталог порожній"),
 "Katalog pozycji": ("Item catalog", "Catálogo de productos", "Каталог позицій"),
 "Każda pozycja musi mieć nazwę.": ("Every item needs a name.", "Cada línea necesita un nombre.", "Кожна позиція повинна мати назву."),
 "NIP nabywcy": ("Buyer NIP", "NIP del comprador", "NIP покупця"),
 "Nabywca": ("Buyer", "Comprador", "Покупець"),
 "Nabywcy": ("Buyers", "Compradores", "Покупці"),
 "Nabywcy są zapamiętywani przy zapisie faktury.": ("Buyers are remembered when you save an invoice.", "Los compradores se guardan al guardar una factura.", "Покупці запам'ятовуються під час збереження рахунку-фактури."),
 "Nazwa lub NIP": ("Name or NIP", "Nombre o NIP", "Назва або NIP"),
 "Nazwa nabywcy": ("Buyer name", "Nombre del comprador", "Назва покупця"),
 "Nazwa towaru lub usługi": ("Product or service name", "Nombre del producto o servicio", "Назва товару чи послуги"),
 "Nie można wygenerować XML": ("Cannot generate XML", "No se puede generar el XML", "Не вдається згенерувати XML"),
 "Nieprawidłowy NIP nabywcy.": ("Invalid buyer NIP.", "NIP del comprador no válido.", "Невірний NIP покупця."),
 "Nowa faktura": ("New invoice", "Nueva factura", "Новий рахунок-фактура"),
 "Nowa pozycja": ("New item", "Nueva línea", "Нова позиція"),
 "Nowa pozycja „%@”": ("New item “%@”", "Nueva línea «%@»", "Нова позиція «%@»"),
 "Numer faktury": ("Invoice number", "Número de factura", "Номер рахунку-фактури"),
 "Oczekuje na wysyłkę": ("Waiting to be sent", "Pendiente de envío", "Очікує на надсилання"),
 "Odrzucona przez KSeF": ("Rejected by KSeF", "Rechazada por KSeF", "Відхилено KSeF"),
 "Podaj nazwę nabywcy.": ("Enter the buyer name.", "Indica el nombre del comprador.", "Вкажіть назву покупця."),
 "Podaj numer faktury.": ("Enter the invoice number.", "Indica el número de factura.", "Вкажіть номер рахунку-фактури."),
 "Podgląd XML FA(3)": ("FA(3) XML preview", "Vista previa del XML FA(3)", "Перегляд XML FA(3)"),
 "Podsumowanie": ("Summary", "Resumen", "Підсумок"),
 "Pozycja": ("Item", "Línea", "Позиція"),
 "Pozycja katalogu": ("Catalog item", "Producto del catálogo", "Позиція каталогу"),
 "Pozycje trafiają tu automatycznie po zapisaniu faktury sprzedażowej.": ("Items are added here automatically when you save a sales invoice.", "Las líneas se añaden aquí automáticamente al guardar una factura de venta.", "Позиції потрапляють сюди автоматично після збереження рахунку-фактури на продаж."),
 "Pozycje ze stawką ZW wymagają podania podstawy prawnej zwolnienia z VAT.": ("VAT-exempt (ZW) items require the legal basis for the exemption.", "Las líneas exentas (ZW) requieren la base legal de la exención de IVA.", "Позиції зі ставкою ZW потребують правової підстави звільнення від ПДВ."),
 "Przelew": ("Bank transfer", "Transferencia", "Переказ"),
 "Przyjęta przez KSeF": ("Accepted by KSeF", "Aceptada por KSeF", "Прийнято KSeF"),
 "Rodzaj podstawy": ("Type of basis", "Tipo de base", "Тип підстави"),
 "Stawka VAT": ("VAT rate", "Tipo de IVA", "Ставка ПДВ"),
 "Szkic": ("Draft", "Borrador", "Чернетка"),
 "Szukaj w katalogu": ("Search the catalog", "Buscar en el catálogo", "Пошук у каталозі"),
 "Uwagi": ("Notes", "Observaciones", "Примітки"),
 "Wybierz pozycję z katalogu albo dodaj nową. Nowe pozycje trafiają do katalogu po zapisaniu faktury.": ("Pick an item from the catalog or add a new one. New items are added to the catalog when you save the invoice.", "Elige una línea del catálogo o añade una nueva. Las nuevas se añaden al catálogo al guardar la factura.", "Виберіть позицію з каталогу або додайте нову. Нові позиції потрапляють до каталогу після збереження рахунку-фактури."),
 "Wybierz rachunek do przelewu albo dodaj go w Ustawieniach.": ("Choose an account for the transfer or add one in Settings.", "Elige una cuenta para la transferencia o añádela en Ajustes.", "Виберіть рахунок для переказу або додайте його в Налаштуваннях."),
 "Wybierz z podpowiedzi": ("Pick a suggestion", "Elegir una sugerencia", "Вибрати з підказок"),
 "Wybierz zapisanego nabywcę": ("Choose a saved buyer", "Elegir un comprador guardado", "Вибрати збереженого покупця"),
 "Wystaw pierwszą fakturę. Wpisane pozycje i nabywcy zostaną zapamiętani do kolejnych faktur.": ("Issue your first invoice. Items and buyers you enter will be remembered for future invoices.", "Emite tu primera factura. Las líneas y compradores que introduzcas se recordarán para próximas facturas.", "Виставте перший рахунок-фактуру. Введені позиції та покупці запам'ятаються для наступних рахунків."),
 "Wystawiona: %@": ("Issued: %@", "Emitida: %@", "Виставлено: %@"),
 "Wysyłanie": ("Sending", "Enviando", "Надсилання"),
 "Wysyłka do KSeF pojawi się w kolejnej wersji roboczej. Szkic możesz już zapisać i wyeksportować jako XML FA(3).": ("Sending to KSeF will arrive in the next development build. You can already save the draft and export it as FA(3) XML.", "El envío a KSeF llegará en la próxima versión de desarrollo. Ya puedes guardar el borrador y exportarlo como XML FA(3).", "Надсилання до KSeF з'явиться в наступній робочій версії. Чернетку вже можна зберегти та експортувати як XML FA(3)."),
 "Z katalogu": ("From the catalog", "Del catálogo", "З каталогу"),
 "Zamknij": ("Close", "Cerrar", "Закрити"),
 "Zapamiętaj nabywcę": ("Remember buyer", "Recordar comprador", "Запам'ятати покупця"),
 "Zapisz": ("Save", "Guardar", "Зберегти"),
 "Zmiany dotyczą tylko przyszłych faktur.": ("Changes apply only to future invoices.", "Los cambios solo afectan a facturas futuras.", "Зміни стосуються лише майбутніх рахунків-фактур."),
 "Zwolnienie z VAT": ("VAT exemption", "Exención de IVA", "Звільнення від ПДВ"),
 "Ustawa o VAT": ("Polish VAT Act", "Ley polaca del IVA", "Закон про ПДВ"),
 "Dyrektywa UE": ("EU Directive", "Directiva de la UE", "Директива ЄС"),
 "Inna podstawa": ("Other basis", "Otra base", "Інша підстава"),
 "Podstawa": ("Basis", "Base", "Підстава"),
 "np. art. 113 ust. 1 ustawy o VAT": ("e.g. art. 113 sec. 1 of the VAT Act", "p. ej. art. 113 apdo. 1 de la ley del IVA", "напр. ст. 113 п. 1 закону про ПДВ"),
 "Faktura zawiera pozycje ze stawką ZW. KSeF wymaga wskazania podstawy prawnej zwolnienia: przepisu ustawy o VAT (lub aktu wykonawczego), dyrektywy 2006/112/WE albo innej podstawy. Wcześniej użyte podstawy są zapamiętywane.":
   ("The invoice has VAT-exempt (ZW) items. KSeF requires the legal basis for the exemption: a provision of the Polish VAT Act (or its regulations), of Directive 2006/112/EC, or another basis. Previously used bases are remembered.",
    "La factura tiene líneas exentas de IVA (ZW). KSeF exige la base legal de la exención: una disposición de la ley polaca del IVA (o su reglamento), de la Directiva 2006/112/CE u otra base. Las bases usadas antes se recuerdan.",
    "Рахунок-фактура містить позиції зі ставкою ZW. KSeF вимагає вказати правову підставу звільнення: положення польського закону про ПДВ (або підзаконного акта), Директиви 2006/112/ЄС чи іншу підставу. Раніше використані підстави запам'ятовуються."),
 "Wersja": ("Version", "Versión", "Версія"),
 "Witaj w KS-eFektywnie": ("Welcome to KS-eFektywnie", "Bienvenido a KS-eFektywnie", "Вітаємо в KS-eFektywnie"),
 "Wklej token KSeF": ("Paste KSeF token", "Pega el token de KSeF", "Вставте токен KSeF"),
 "Wklej token w aplikacji": ("Paste the token in the app", "Pega el token en la aplicación", "Вставте токен у застосунку"),
 "Wyciągi": ("Statements", "Extractos", "Виписки"),
 "Wygeneruj token": ("Generate a token", "Genera un token", "Згенеруйте токен"),
 "Zaakceptowana": ("Accepted", "Aceptada", "Прийнятий"),
 "Zaloguj się do Aplikacji Podatnika KSeF": ("Sign in to the KSeF Taxpayer Application", "Inicia sesión en la Aplicación del Contribuyente KSeF", "Увійдіть до Застосунку платника KSeF"),
 "Zapisz notatkę": ("Save note", "Guardar nota", "Зберегти нотатку"),
 "Zapisz token": ("Save token", "Guardar token", "Зберегти токен"),
 "Zmień status": ("Change status", "Cambiar estado", "Змінити статус"),
 "kod urządzenia": ("device passcode", "código del dispositivo", "код пристрою"),
 "Środowisko": ("Environment", "Entorno", "Середовище"),
 "Środowisko KSeF": ("KSeF environment", "Entorno de KSeF", "Середовище KSeF"),
 "Środowisko testowe": ("Test environment", "Entorno de pruebas", "Тестове середовище"),
 "Środowisko testowe ma osobne dane i osobne tokeny. Token z produkcji nie działa na teście i odwrotnie.": ("The test environment has separate data and separate tokens. A production token does not work in test, and vice versa.", "El entorno de pruebas tiene datos y tokens propios. Un token de producción no funciona en pruebas, y viceversa.", "Тестове середовище має окремі дані й окремі токени. Токен із виробничого не працює в тестовому, і навпаки."),
 "Środowisko testowe służy do prób i ma osobne dane oraz tokeny. Do pracy na prawdziwych fakturach wybierz produkcyjne.": ("The test environment is for trying things out and has separate data and tokens. Choose production to work with real invoices.", "El entorno de pruebas sirve para hacer pruebas y tiene datos y tokens propios. Para trabajar con facturas reales, elige producción.", "Тестове середовище призначене для спроб і має окремі дані та токени. Для роботи зі справжніми рахунками-фактурами виберіть виробниче."),
}

INFO_PLIST = {
 "NSFaceIDUsageDescription": {
   "pl": "Face ID chroni dostęp do Twoich faktur i danych bankowych.",
   "en": "Face ID protects access to your invoices and bank data.",
   "es": "Face ID protege el acceso a tus facturas y datos bancarios.",
   "uk": "Face ID захищає доступ до ваших рахунків-фактур і банківських даних.",
 },
 "CFBundleDisplayName": {lang: "KS-eFektywnie" for lang in ("pl", "en", "es", "uk")},
}

LANGS = ("en", "es", "uk")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog():
    strings = {}
    for key in sorted(T):
        value = T[key]
        if value is SAME:
            strings[key] = {"shouldTranslate": False}
        else:
            strings[key] = {"localizations": {lang: unit(v) for lang, v in zip(LANGS, value)}}
    return {"sourceLanguage": "pl", "strings": strings, "version": "1.0"}


def info_catalog():
    return {"sourceLanguage": "pl", "version": "1.0", "strings": {
        key: {"localizations": {lang: unit(v) for lang, v in values.items()}} for key, values in INFO_PLIST.items()}}


def check(derived_data):
    keys = set()
    for f in glob.glob(f"{derived_data}/**/KSeFektywnie.build/**/*.stringsdata", recursive=True):
        for entries in json.load(open(f)).get("tables", {}).values():
            keys.update(e["key"] for e in entries)
    missing = sorted(keys - set(T))
    unused = sorted(set(T) - keys)
    for k in missing:
        print(f"BRAK TŁUMACZENIA: {k!r}")
    for k in unused:
        print(f"nieużywany klucz: {k!r}")
    return not missing


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--derived-data", default=str(ROOT / ".build" / "DerivedData"))
    args = ap.parse_args()
    res = ROOT / "KSeFektywnie" / "Resources"
    (res / "Localizable.xcstrings").write_text(json.dumps(catalog(), ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    (res / "InfoPlist.xcstrings").write_text(json.dumps(info_catalog(), ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"Zapisano {len(T)} kluczy dla pl/{'/'.join(LANGS)}.")
    sys.exit(0 if check(args.derived_data) else 1)
