#!/bin/bash
# compose.sh SRC OUT "Headline line1\nline2" "sub"
SRC=$1; OUT=$2; HEAD=$3; SUB=$4
BG="#F3EEE7"; INK="#2B2420"; SUBC="#7A6E66"
W=1320; H=2868
# screenshot scaled to 80%, rounded corners
SW=1056; SH=$((2868*SW/1320))
magick "$SRC" -resize ${SW}x${SH} \( +clone -alpha extract -fill black -colorize 100 -fill white -draw "roundrectangle 0,0,$((SW-1)),$((SH-1)),70,70" \) -alpha off -compose CopyOpacity -composite /tmp/_shot.png
magick /tmp/_shot.png \( +clone -background "#3a2a20" -shadow 30x28+0+18 \) +swap -background none -layers merge +repage /tmp/_shadow.png
magick -size ${W}x${H} xc:"$BG" \
  -font /System/Library/Fonts/NewYork.ttf -fill "$INK" -pointsize 92 -gravity north -interline-spacing 6 -annotate +0+190 "$HEAD" \
  -font /System/Library/Fonts/SFNS.ttf -fill "$SUBC" -pointsize 44 -annotate +0+450 "$SUB" \
  /tmp/_shadow.png -gravity north -geometry +0+600 -composite \
  -flatten -alpha off "$OUT"
