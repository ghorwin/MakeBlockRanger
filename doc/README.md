In diesem Verzeichnis liegt die Dokumentation. Diese wird mittels github-actions automatisch als HTML Seite erstellt
und via githab pages veröffentlicht.

Im de/en-Verzeichnis einfach das Script build_html.sh starten.
Das Script linkcheck.sh hilft, Verweise in den verschiedenen AsciiDoc-Dateien zu finden und falsche Verknüpfungen
zu finden.


## AsciiDoctor Installation

### Linux/Ubuntu

```bash

# install asciidoctor

> sudo apt install asciidoctor 

# install ruby

> sudo apt install ruby

# install GraphicsMagick (for additional image support)

> sudo apt install graphicsmagick graphicsmagick-imagemagick-compat graphicsmagick-libmagick-dev-compat

# install gems (ruby modules)

> sudo gem install asciidoctor-pdf --pre

# GraphicsMagick support
> sudo gem install prawn-gmagick

# rouge syntax highlighter extension
> sudo gem install rouge
> sudo gem install asciidoctor-rouge

# math extensions - may not work, so try to avoid!
> sudo apt install ruby-dev
> sudo gem install asciidoctor-mathematical

```
