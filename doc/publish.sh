#!/bin/bash

echo '*** Generating docs ***' &&
(cd de;./build_html.sh) &&


echo '*** Copying images ***' &&
cp -r images/* ../docs/images/ &&

echo '*** Copying css ***' &&
cp -r css/* ../docs/css/ &&

echo '*** Copying downloadables ***' &&
cp -r downloads/* ../docs/downloads/ &&

echo '*** Copying fonts ***' &&
cp -r fonts/* ../docs/fonts/ &&

echo '*** Copying webpages ***' &&
cp de/index.html ../docs/de/


