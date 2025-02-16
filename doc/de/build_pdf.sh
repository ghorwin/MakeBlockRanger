#!/bin/bash

export ADOC=VICUS-Handbuch.adoc
python3 ../adoc_utils/adoc-image-prep.py pdf . &&
asciidoctor-pdf -a lang=de  -a pdf-theme=./manual-en-pdf-theme.yml  -r ../rouge_theme.rb -a pdf-fontsdir="../fonts;GEM_FONTS_DIR" $ADOC

