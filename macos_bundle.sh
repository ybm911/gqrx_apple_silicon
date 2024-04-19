#!/bin/bash -e


if [ ! -e gqrx ]; then
	git clone https://github.com/gqrx-sdr/gqrx.git
fi

cd gqrx

(
	rm -rf build
	mkdir -p build
	cd build
	cmake ..
	make -j${CPU_COUNT}
)

GQRX_VERSION="$(<build/version.txt)"
BREW_PREFIX="$(brew --prefix)"
IDENTITY=Y3GC27WZ4S

rm -rf Gqrx.app
mkdir -p Gqrx.app/Contents/MacOS
mkdir -p Gqrx.app/Contents/Resources
mkdir -p Gqrx.app/Contents/soapy-modules

/bin/cat <<EOM >Gqrx.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleGetInfoString</key>
  <string>Gqrx</string>
  <key>CFBundleExecutable</key>
  <string>gqrx</string>
  <key>CFBundleIdentifier</key>
  <string>dk.gqrx.gqrx</string>
  <key>CFBundleName</key>
  <string>Gqrx</string>
  <key>CFBundleIconFile</key>
  <string>gqrx.icns</string>
  <key>CFBundleShortVersionString</key>
  <string>$GQRX_VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>IFMajorVersion</key>
  <integer>1</integer>
  <key>IFMinorVersion</key>
  <integer>0</integer>
</dict>
</plist>
EOM

/bin/cat <<EOM >/tmp/Entitlements.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
</dict>
</plist>
EOM

cp -p build/src/gqrx Gqrx.app/Contents/MacOS
cp -p resources/icons/gqrx.icns Gqrx.app/Contents/Resources
cp -p "${BREW_PREFIX}"/lib/SoapySDR/modules*/libPlutoSDRSupport.so Gqrx.app/Contents/soapy-modules
cp -p "${BREW_PREFIX}"/lib/SoapySDR/modules*/libremoteSupport.so Gqrx.app/Contents/soapy-modules
chmod 644 Gqrx.app/Contents/soapy-modules/*

dylibbundler \
	-s "${BREW_PREFIX}/opt/icu4c/lib/" \
	-od -b \
	-x Gqrx.app/Contents/MacOS/gqrx \
	-x Gqrx.app/Contents/soapy-modules/libPlutoSDRSupport.so \
	-x Gqrx.app/Contents/soapy-modules/libremoteSupport.so \
	-d Gqrx.app/Contents/libs/

macdeployqt Gqrx.app -no-strip -always-overwrite # TODO: Remove macdeployqt workaround
if [ "$1" = "true" ]; then
    macdeployqt Gqrx.app -no-strip -always-overwrite -sign-for-notarization=$IDENTITY
else
    macdeployqt Gqrx.app -no-strip -always-overwrite
fi
cp -p "${BREW_PREFIX}/lib/libbrotlicommon.1.dylib" Gqrx.app/Contents/Frameworks # TODO: Remove macdeployqt workaround


#install_name_tool -change @loader_path/../../../../opt/libpng/lib/libpng16.16.dylib @executable_path/../Frameworks/libpng16.16.dylib Gqrx.app/Contents/Frameworks/libfreetype.6.dylib


find Gqrx.app -name '*.framework' -or -name '*.dylib' -or -name '*.so' -or -name gqrx | {
	while read -r f; do
		codesign --sign - --force --preserve-metadata=entitlements,requirements,flags,runtime "${f}"
	done
}

codesign --sign - --force --preserve-metadata=entitlements,requirements,flags,runtime Gqrx.app

for f in Gqrx.app/Contents/libs/*.dylib Gqrx.app/Contents/soapy-modules/*.so Gqrx.app/Contents/Frameworks/*.framework Gqrx.app/Contents/Frameworks/libbrotlicommon.1.dylib Gqrx.app/Contents/Frameworks/libsharpyuv.0.dylib Gqrx.app/Contents/Frameworks/libfreetype.6.dylib Gqrx.app/Contents/MacOS/gqrx
do
    if [ "$1" = "true" ]; then
        codesign --force --verify --verbose --timestamp --options runtime --entitlements /tmp/Entitlements.plist --sign $IDENTITY $f
    else
        codesign --remove-signature $f
    fi
done
