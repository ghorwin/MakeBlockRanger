#!/bin/bash

echo '*** copying images ***' &&
cp -r images/* ../docs/images/ &&

echo '*** copying css ***' &&
cp -r css/* ../docs/css/ &&

echo '*** copying downloadables ***' &&
cp -r downloads/* docs/downloads/ &&

echo '*** copying fonts ***' &&
cp -r fonts/* docs/fonts/ &&

echo '*** copying webpages ***' &&
cp -r de/index.html docs/de/index.html


