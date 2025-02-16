#!/bin/bash

#python3 ../adoc_utils/adoc-link-check.py . &&

echo '*** Generating html ***' &&
python3 ../adoc_utils/adoc-image-prep.py html . &&
asciidoctor -a lang=de -a icons=font -a stylesdir=../css -a iconfont-remote!  main.adoc -o index.html &&

echo '*** Finished successfully ***'


