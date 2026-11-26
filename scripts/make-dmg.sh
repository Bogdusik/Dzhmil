#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
dist=$root/dist
build=$dist/build.noindex
archive=$build/Dzhmil.xcarchive
volume=Dzhmil
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ -e /Volumes/$volume ]]; then
  print "error: eject /Volumes/$volume first"
  exit 1
fi

cd $root/app
xcodegen generate --quiet
rm -rf $archive
xcodebuild -project Dzhmil.xcodeproj -scheme Dzhmil -configuration Release \
  -derivedDataPath $build/derived -archivePath $archive \
  -destination generic/platform=macOS ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_ENTITLEMENTS=$root/app/Dzhmil/Dzhmil-AdHoc.entitlements \
  -quiet archive

app=$archive/Products/Applications/Dzhmil.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $app/Contents/Info.plist)
codesign --verify --deep --strict $app
if [[ $(codesign -dv $app 2>&1) != *runtime* ]]; then
  print "error: $app is not signed with the hardened runtime"
  exit 1
fi
if grep -rqa "$HOME" $app; then
  print "error: $app still contains $HOME paths"
  exit 1
fi

work=$(mktemp -d -t dzhmil-dmg)
cleanup() {
  [[ -e /Volumes/$volume ]] && hdiutil detach -quiet -force /Volumes/$volume
  $lsregister -u $app 2>/dev/null || true
  rm -rf $work $archive
}
trap cleanup EXIT

stage=$work/stage
mkdir -p $stage/.background
ditto $app $stage/Dzhmil.app
ln -s /Applications $stage/Applications
tiffutil -cathidpicheck $root/scripts/dmg/background.png $root/scripts/dmg/background@2x.png -out $stage/.background/background.tiff >/dev/null

hdiutil create -quiet -volname $volume -srcfolder $stage -fs HFS+ -format UDRW $work/layout.dmg
hdiutil attach -quiet -readwrite -noverify -noautoopen $work/layout.dmg
osascript $root/scripts/dmg/layout.applescript $volume
cp $app/Contents/Resources/AppIcon.icns /Volumes/$volume/.VolumeIcon.icns
xcrun SetFile -a C /Volumes/$volume
sync
if [[ ! -s /Volumes/$volume/.DS_Store ]]; then
  print "error: Finder did not save the window layout"
  exit 1
fi
rm -rf /Volumes/$volume/.fseventsd
for attempt in 1 2 3 4 5; do
  hdiutil detach -quiet /Volumes/$volume && break
  sleep 2
done

dmg=$dist/Dzhmil-$version.dmg
hdiutil convert -quiet -ov $work/layout.dmg -format ULFO -o $dmg
hdiutil verify -quiet $dmg

ls -lh $dmg
shasum -a 256 $dmg
