# KS-eFektywnie (iOS)

Natywna aplikacja iOS 26+ (Swift 6, SwiftUI). Działa lokalnie na telefonie, bez kont i bez backendu.
Plan wydania: [`docs/ios-release-plan.md`](../docs/ios-release-plan.md).

## Struktura

```
ios/
  project.yml                  # specyfikacja XcodeGen (projekt .xcodeproj jest generowany, nie commitujemy go)
  KSeFektywnie/                # aplikacja SwiftUI: ekrany, Keychain, Face ID, StoreKit, zasoby
  Packages/KSeFektywnieKit/    # logika w pakiecie Swift, testowana na macOS bez symulatora
    Sources/Domain             # port logiki Django: parser FA, generatory przelewów, wyciągi, matcher, statusy
    Sources/KSeFClient         # klient API KSeF 2.0
    Sources/Persistence        # SQLite (GRDB): schemat, repozytoria
    Sources/AppServices        # synchronizacja KSeF, dane demo
    Tests/DomainTests/Fixtures # golden files z Django (input/ ręcznie, expected/ generowane)
  scripts/translations.py      # tłumaczenia pl/en/es/uk → String Catalogs (z odmianą przez liczbę)
  scripts/generate_icon.swift  # tymczasowa ikona aplikacji
```

## Praca na co dzień

```bash
brew install xcodegen
cd ios && xcodegen generate && open KSeFektywnie.xcodeproj

# testy logiki (szybkie, bez symulatora)
cd ios/Packages/KSeFektywnieKit && swift test

# build aplikacji
xcodebuild -project ios/KSeFektywnie.xcodeproj -scheme KSeFektywnie \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# zrzuty ekranu na danych demo (tylko Debug), argumenty uruchomienia:
#   -demo                       dane demo w pamięci (bez lustra iCloud)
#   -demo-cloud                 jak wyżej, z lustrem (na symulatorze: katalog lokalny)
#   -tab sales|payments|statements|settings
#   -open-sale 2  -open-statement YES  -open-dashboard YES
```

## Golden files z Django

Kod Django jest wyrocznią dla portu. Po zmianie parserów, generatorów lub matchera w Django:

```bash
docker compose exec web python manage.py export_ios_fixtures
cd ios/Packages/KSeFektywnieKit && swift test --filter DomainTests
```

Każda rozbieżność to błąd portu albo błąd w Django — poprawiamy go po obu stronach.

## Tłumaczenia

Teksty UI pisane są po polsku (język źródłowy). Po dodaniu nowego tekstu:

1. zbuduj aplikację (kompilator wyciąga klucze do `.stringsdata`),
2. dopisz tłumaczenia w `scripts/translations.py`,
3. uruchom `python3 scripts/translations.py` — skrypt zgłasza brakujące klucze i generuje `Localizable.xcstrings`.

Tłumaczenia hiszpańskie i ukraińskie wymagają przeglądu przez native speakera przed publikacją.
