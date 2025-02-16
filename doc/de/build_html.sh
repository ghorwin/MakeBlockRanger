#!/bin/bash

ADOC=VICUS-Handbuch

#python3 adoc_utils/adoc-link-check.py . &&

echo '*** Generating html ***' &&
#python3 adoc_utils/adoc-image-prep.py html . &&
asciidoctor -a lang=de -a icons=font -a stylesdir=../css -a iconfont-remote!  $ADOC.adoc &&

if [ ! -d ../webpage/de/images ]; then
  echo '*** Creating directory ../webpage/de/images' && 
  mkdir -p ../webpage/de/images
fi &&

echo '*** Copying files to webpage-directory ***' && 

cp -r images/* ../webpage/de/images &&
cp VICUS-Handbuch.html ../webpage/de/ && 

echo '*** Finished successfully ***'


