#!/bin/zsh
# Buduje archiwum Release i wysyła je do App Store Connect (TestFlight).
# Wymaga: Xcode zalogowany na konto zespołu X9AX9Q83H4 i rekord aplikacji
# pl.ksefektywnie.app w App Store Connect.
#
#   ./scripts/testflight.sh            # numer kompilacji = data i godzina (rosnący)
#   BUILD_NUMBER=42 ./scripts/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHIVE=".build/KSeFektywnie-${BUILD_NUMBER}.xcarchive"

echo "▸ Generowanie projektu"
xcodegen generate --quiet

echo "▸ Testy logiki"
(cd Packages/KSeFektywnieKit && swift test 2>&1 | grep -E "Test run|✘" )

echo "▸ Archiwum Release (build ${BUILD_NUMBER})"
xcodebuild -project KSeFektywnie.xcodeproj -scheme KSeFektywnie -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -allowProvisioningUpdates -quiet archive

cat > .build/ExportOptions-upload.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>X9AX9Q83H4</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▸ Wysyłka do App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath ".build/upload-${BUILD_NUMBER}" \
  -exportOptionsPlist .build/ExportOptions-upload.plist -allowProvisioningUpdates

echo "✓ Build ${BUILD_NUMBER} wysłany. Po przetworzeniu (zwykle 5–30 min) pojawi się w TestFlight."
