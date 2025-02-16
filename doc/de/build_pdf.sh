#!/bin/bash

#python3 ../adoc_utils/adoc-image-prep.py pdf . &&
asciidoctor-pdf -a lang=de  -a pdf-theme=./manual-de-pdf-theme.yml  -r ../rouge_theme.rb -a pdf-fontsdir="../fonts;GEM_FONTS_DIR" main.adoc -o ../MakeBlockRanger-Tutorial.pdf


