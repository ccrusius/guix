;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015, 2018 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2016 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2017, 2018 Nicolas Goaziou <mail@nicolasgoaziou.fr>
;;; Copyright © 2018 Clément Lassieur <clement@lassieur.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages scribus)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix build-system cmake)
  #:use-module (gnu packages)
  #:use-module (gnu packages boost)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cups)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages ghostscript)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages icu4c)
  #:use-module (gnu packages image)
  #:use-module (gnu packages imagemagick)
  #:use-module (gnu packages libreoffice)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pdf)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages xml))

(define-public scribus
  (package
    (name "scribus")
    (version "1.5.5")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://sourceforge/scribus/scribus-devel/"
                           version "/scribus-" version ".tar.xz"))
       (sha256
        (base32
         "0w9zzsiaq3f7vpxybk01c9z2b4qqg67mzpyfb2gjchz8dhdb423r"))))
    (build-system cmake-build-system)
    (arguments
     `(#:tests? #f                      ;no test target
       #:configure-flags
       '("-DWANT_GRAPHICSMAGICK=1")
       #:phases
       (modify-phases %standard-phases
         (add-after 'install 'wrap-program
           (lambda* (#:key inputs outputs #:allow-other-keys)
             ;; Fix "ImportError: No module named _sysconfigdata_nd"
             ;; runtime error where Scribus checks PATH and eventually
             ;; runs system's Python instead of package's.
             (let* ((out (assoc-ref outputs "out"))
                    (py2 (assoc-ref inputs "python")))
               (wrap-program (string-append out "/bin/scribus")
                 `("PATH" ":" prefix (,(string-append py2 "/bin")))))
             #t)))))
    (inputs
     `(("boost" ,boost)
       ("cairo" ,cairo)
       ("cups" ,cups)
       ("fontconfig" ,fontconfig)
       ("freetype" ,freetype)
       ("graphicsmagick" ,graphicsmagick)
       ("harfbuzz" ,harfbuzz)
       ("hunspell" ,hunspell)
       ("icu4c" ,icu4c)
       ("lcms" ,lcms)
       ("libcdr" ,libcdr)
       ("libfreehand" ,libfreehand)
       ("libjpeg" ,libjpeg)
       ("libmspub" ,libmspub)
       ("libpagemaker" ,libpagemaker)
       ("librevenge" ,librevenge)
       ("libtiff" ,libtiff)
       ("libvisio" ,libvisio)
       ("libxml2" ,libxml2)
       ("libzmf" ,libzmf)
       ("openssl" ,openssl)
       ("podofo" ,podofo)
       ("poppler" ,poppler)
       ("python" ,python-2)             ;need Python library
       ("qtbase" ,qtbase)
       ("qtdeclarative" ,qtdeclarative)
       ("zlib" ,zlib)))
    (native-inputs
     `(("pkg-config" ,pkg-config)
       ("qttools" ,qttools)
       ("util-linux" ,util-linux)))
    (home-page "https://www.scribus.net")
    (synopsis "Desktop publishing and page layout program")
    (description
     "Scribus is a @dfn{desktop publishing} (DTP) application and can
be used for many tasks; from brochure design to newspapers, magazines,
newsletters and posters to technical documentation.  Scribus supports
professional DTP features, such as CMYK color and a color management
system to soft proof images for high quality color printing, flexible
PDF creation options, Encapsulated PostScript import/export and
creation of four color separations, import of EPS/PS and SVG as native
vector graphics, Unicode text including right to left scripts such as
Arabic and Hebrew via FreeType.")
    (license license:gpl2+)))
