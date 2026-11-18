#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
dist=$root/dist
archive=$dist/build/Dzhmil.xcarchive

cd $root/app
xcodegen generate --quiet
rm -rf $archive
xcodebuild -project Dzhmil.xcodeproj -scheme Dzhmil -configuration Release \
  -derivedDataPath $dist/build/derived -archivePath $archive \
  -destination generic/platform=macOS ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=NO \
  -quiet archive

app=$archive/Products/Applications/Dzhmil.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $app/Contents/Info.plist)
codesign --verify --deep --strict $app
if grep -rqa "$HOME" $app; then
  print "error: $app still contains $HOME paths"
  exit 1
fi

stage=$(mktemp -d -t dzhmil-dmg)
trap 'rm -rf $stage' EXIT
ditto $app $stage/Dzhmil.app
ln -s /Applications $stage/Applications

dmg=$dist/Dzhmil-$version.dmg
hdiutil create -quiet -ov -volname "Dzhmil $version" -srcfolder $stage -format ULFO $dmg
hdiutil verify -quiet $dmg

ls -lh $dmg
shasum -a 256 $dmg
