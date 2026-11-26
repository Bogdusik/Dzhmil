on run argv
	set volumeName to item 1 of argv
	tell application "Finder"
		tell disk volumeName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 112
			set text size of viewOptions to 13
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item "Dzhmil.app" of container window to {170, 200}
			set position of item "Applications" of container window to {490, 200}
			set the bounds of container window to {200, 120, 860, 552}
			update without registering applications
			delay 1
			close
			open
			delay 1
			set the bounds of container window to {200, 120, 859, 552}
			delay 1
			set the bounds of container window to {200, 120, 860, 552}
			delay 2
			close
		end tell
	end tell
end run
