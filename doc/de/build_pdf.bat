set ADOC=VICUS-Handbuch.adoc
asciidoctor-pdf -a lang=de  -a pdf-theme=./manual-en-pdf-theme.yml  -r ../rouge_theme.rb -a pdf-fontsdir="../fonts;GEM_FONTS_DIR" %ADOC%
pause
