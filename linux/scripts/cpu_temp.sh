#!/bin/bash

TEMP=$(sensors | awk '
/k10temp/ {found=1}
/Tctl:/ && found {gsub(/\+/,""); gsub(/°C/,""); print $2; exit}
/CPU Package:/ {gsub(/\+/,""); gsub(/°C/,""); print $3; exit}
')

echo "$TEMP"