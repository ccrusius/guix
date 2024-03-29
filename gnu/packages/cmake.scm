;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013 Cyril Roelandt <tipecaml@gmail.com>
;;; Copyright © 2014 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2014 Eric Bavier <bavier@member.fsf.org>
;;; Copyright © 2014 Ian Denhardt <ian@zenhack.net>
;;; Copyright © 2015 Sou Bunnbu <iyzsong@gmail.com>
;;; Copyright © 2016 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2017, 2018 Marius Bakke <mbakke@fastmail.com>
;;; Copyright © 2018 Arun Isaac <arunisaac@systemreboot.net>
;;; Copyright © 2018 Tobias Geerinckx-Rice <me@tobias.gr>
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

(define-module (gnu packages cmake)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system emacs)
  #:use-module (gnu packages)
  #:use-module (gnu packages backup)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages crypto)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages file)
  #:use-module (gnu packages libevent)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages xml))

(define-public cmake
  (package
    (name "cmake")
    (version "3.13.1")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://www.cmake.org/files/v"
                                  (version-major+minor version)
                                  "/cmake-" version ".tar.gz"))
              (sha256
               (base32
                "04123d7fgnn1fs5p0nwyq397ss89r0y4wkg9a09qiwkjsvk1rzmy"))
              (modules '((guix build utils)))
              (snippet
               '(begin
                  ;; Drop bundled software.
                  (with-directory-excursion "Utilities"
                    (for-each delete-file-recursively
                              '("cmbzip2"
                                ;; "cmcompress"
                                "cmcurl"
                                "cmexpat"
                                ;; "cmjsoncpp"
                                ;; "cmlibarchive"
                                "cmliblzma"
                                ;; "cmlibuv"
                                "cmzlib"))
                    #t)))))
    (build-system gnu-build-system)
    (arguments
     `(#:test-target "test"
       #:make-flags
       (let ((skipped-tests
              (list "BundleUtilities" ; This test fails on Guix.
                    "CTestTestSubdir" ; This test fails to build 2 of the 3 tests.
                    ;; These tests requires network access.
                    "CTestCoverageCollectGCOV"
                    "CTestTestUpload")))
         (list
          (string-append
           ;; These arguments apply for the tests only.
           "ARGS=-j " (number->string (parallel-job-count))
           " --output-on-failure"
           " --exclude-regex ^\\(" (string-join skipped-tests "\\|") "\\)$")))
       #:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'split-package
           ;; Remove files that have been packaged in other package recipes.
           (lambda _
             (delete-file "Auxiliary/cmake-mode.el")
             (substitute* "Auxiliary/CMakeLists.txt"
               ((".*cmake-mode.el.*") ""))
             #t))
         (add-before 'configure 'patch-bin-sh
           (lambda _
             ;; Replace "/bin/sh" by the right path in... a lot of
             ;; files.
             (substitute*
                 '("Modules/CompilerId/Xcode-3.pbxproj.in"
                   "Modules/CPack.RuntimeScript.in"
                   "Source/cmakexbuild.cxx"
                   "Source/cmGlobalXCodeGenerator.cxx"
                   "Source/cmLocalUnixMakefileGenerator3.cxx"
                   "Source/cmExecProgramCommand.cxx"
                   "Utilities/Release/release_cmake.cmake"
                   "Utilities/cmlibarchive/libarchive/archive_write_set_format_shar.c"
                   "Tests/CMakeLists.txt"
                   "Tests/RunCMake/File_Generate/RunCMakeTest.cmake")
               (("/bin/sh") (which "sh")))
             #t))
         (add-before 'configure 'set-paths
           (lambda _
             ;; Help cmake's bootstrap process to find system libraries
             (begin
               (setenv "CMAKE_LIBRARY_PATH" (getenv "LIBRARY_PATH"))
               (setenv "CMAKE_INCLUDE_PATH" (getenv "C_INCLUDE_PATH"))
               #t)))
         (replace 'configure
           (lambda* (#:key outputs #:allow-other-keys)
             (let ((out (assoc-ref outputs "out")))
               (invoke
                "./configure" "--verbose"
                (string-append "--parallel=" (number->string (parallel-job-count)))
                (string-append "--prefix=" out)
                "--system-libs"
                "--no-system-jsoncpp" ; FIXME: Circular dependency.
                ;; By default, the man pages and other docs land
                ;; in PREFIX/man and PREFIX/doc, but we want them
                ;; in share/{man,doc}.  Note that unlike
                ;; autoconf-generated configure scripts, cmake's
                ;; configure prepends "PREFIX/" to what we pass
                ;; to --mandir and --docdir.
                "--mandir=share/man"
                ,(string-append
                  "--docdir=share/doc/cmake-"
                  (version-major+minor version)))))))))
    (inputs
     `(("bzip2" ,bzip2)
       ("curl" ,curl)
       ("expat" ,expat)
       ("file" ,file)
       ("libarchive" ,libarchive)
       ("libuv" ,libuv)
       ("ncurses" ,ncurses) ; required for ccmake
       ("rhash" ,rhash)
       ("zlib" ,zlib)))
    (native-search-paths
     (list (search-path-specification
            (variable "CMAKE_PREFIX_PATH")
            (files '("")))))
    (home-page "https://cmake.org/")
    (synopsis "Cross-platform build system")
    (description
     "CMake is a family of tools designed to build, test and package software.
CMake is used to control the software compilation process using simple platform
and compiler independent configuration files.  CMake generates native makefiles
and workspaces that can be used in the compiler environment of your choice.")
    (license (list license:bsd-3             ; cmake
                   license:bsd-4             ; cmcompress
                   license:bsd-2             ; cmlibarchive
                   license:expat             ; cmjsoncpp is dual MIT/public domain
                   license:public-domain)))) ; cmlibarchive/archive_getdate.c

(define-public cmake/fixed
  ;; This is a variant of CMake that fixes X.509 certificate lookup:
  ;; <https://issues.guix.gnu.org/issue/37371>.
  (package
    (inherit cmake)
    (version (string-append (package-version cmake) "-1"))
    (source (origin
              (inherit (package-source cmake))
              (patches
               (append (search-patches "cmake-curl-certificates.patch")
                       (origin-patches (package-source cmake))))))))

(define-public emacs-cmake-mode
  (package
    (inherit cmake)
    (name "emacs-cmake-mode")
    (build-system emacs-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'chdir-elisp
           ;; Elisp directory is not in root of the source.
           (lambda _
             (chdir "Auxiliary"))))))
    (synopsis "Emacs major mode for editing Cmake expressions")
    (description "@code{cmakeos-mode} provides an Emacs major mode for editing
Cmake files.  It supports syntax highlighting, indenting and refilling of
comments.")))
