;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2018 Ricardo Wurmus <rekado@elephly.net>
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

(define-module (test-channels)
  #:use-module (guix channels)
  #:use-module (guix profiles)
  #:use-module ((guix build syscalls) #:select (mkdtemp!))
  #:use-module (guix tests)
  #:use-module (guix store)
  #:use-module ((guix grafts) #:select (%graft?))
  #:use-module (guix derivations)
  #:use-module (guix sets)
  #:use-module (guix gexp)
  #:use-module ((guix utils)
                #:select (error-location? error-location location-line))
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-35)
  #:use-module (srfi srfi-64)
  #:use-module (ice-9 match))

(test-begin "channels")

(define* (make-instance #:key
                        (name 'fake)
                        (commit "cafebabe")
                        (spec #f))
  (define instance-dir (mkdtemp! "/tmp/checkout.XXXXXX"))
  (when spec
    (call-with-output-file (string-append instance-dir "/.guix-channel")
      (lambda (port) (write spec port))))
  (checkout->channel-instance instance-dir
                              #:commit commit
                              #:name name))

(define instance--boring (make-instance))
(define instance--unsupported-version
  (make-instance #:spec
                 '(channel (version 42) (dependencies whatever))))
(define instance--no-deps
  (make-instance #:spec
                 '(channel (version 0))))
(define instance--sub-directory
  (make-instance #:spec
                 '(channel (version 0) (directory "modules"))))
(define instance--simple
  (make-instance #:spec
                 '(channel
                   (version 0)
                   (dependencies
                    (channel
                     (name test-channel)
                     (url "https://example.com/test-channel"))))))
(define instance--with-dupes
  (make-instance #:spec
                 '(channel
                   (version 0)
                   (dependencies
                    (channel
                     (name test-channel)
                     (url "https://example.com/test-channel"))
                    (channel
                     (name test-channel)
                     (url "https://example.com/test-channel")
                     (commit "abc1234"))
                    (channel
                     (name test-channel)
                     (url "https://example.com/test-channel-elsewhere"))))))

(define channel-instance-metadata
  (@@ (guix channels) channel-instance-metadata))
(define channel-metadata-directory
  (@@ (guix channels) channel-metadata-directory))
(define channel-metadata-dependencies
  (@@ (guix channels) channel-metadata-dependencies))


(test-equal "channel-instance-metadata returns default if .guix-channel does not exist"
  '("/" ())
  (let ((metadata (channel-instance-metadata instance--boring)))
    (list (channel-metadata-directory metadata)
          (channel-metadata-dependencies metadata))))

(test-equal "channel-instance-metadata and default dependencies"
  '()
  (channel-metadata-dependencies (channel-instance-metadata instance--no-deps)))

(test-equal "channel-instance-metadata and directory"
  "/modules"
  (channel-metadata-directory
   (channel-instance-metadata instance--sub-directory)))

(test-equal "channel-instance-metadata rejects unsupported version"
  1                              ;line number in the generated '.guix-channel'
  (guard (c ((and (message-condition? c) (error-location? c))
             (location-line (error-location c))))
    (channel-instance-metadata instance--unsupported-version)))

(test-assert "channel-instance-metadata returns <channel-metadata>"
  (every (@@ (guix channels) channel-metadata?)
         (map channel-instance-metadata
              (list instance--no-deps
                    instance--simple
                    instance--with-dupes))))

(test-assert "channel-instance-metadata dependencies are channels"
  (let ((deps ((@@ (guix channels) channel-metadata-dependencies)
               (channel-instance-metadata instance--simple))))
    (match deps
      (((? channel? dep)) #t)
      (_ #f))))

(test-assert "latest-channel-instances includes channel dependencies"
  (let* ((channel (channel
                   (name 'test)
                   (url "test")))
         (test-dir (channel-instance-checkout instance--simple)))
    (mock ((guix git) latest-repository-commit
           (lambda* (store url #:key ref)
             (match url
               ("test" (values test-dir 'whatever))
               (_ (values "/not-important" 'not-important)))))
          (let ((instances (latest-channel-instances #f (list channel))))
            (and (eq? 2 (length instances))
                 (lset= eq?
                        '(test test-channel)
                        (map (compose channel-name channel-instance-channel)
                             instances)))))))

(test-assert "latest-channel-instances excludes duplicate channel dependencies"
  (let* ((channel (channel
                   (name 'test)
                   (url "test")))
         (test-dir (channel-instance-checkout instance--with-dupes)))
    (mock ((guix git) latest-repository-commit
           (lambda* (store url #:key ref)
             (match url
               ("test" (values test-dir 'whatever))
               (_ (values "/not-important" 'not-important)))))
          (let ((instances (latest-channel-instances #f (list channel))))
            (and (= 2 (length instances))
                 (lset= eq?
                        '(test test-channel)
                        (map (compose channel-name channel-instance-channel)
                             instances))
                 ;; only the most specific channel dependency should remain,
                 ;; i.e. the one with a specified commit.
                 (find (lambda (instance)
                         (and (eq? (channel-name
                                    (channel-instance-channel instance))
                                   'test-channel)
                              (string=? (channel-commit
                                         (channel-instance-channel instance))
                                        "abc1234")))
                       instances))))))

(test-assert "channel-instances->manifest"
  ;; Compute the manifest for a graph of instances and make sure we get a
  ;; derivation graph that mirrors the instance graph.  This test also ensures
  ;; we don't try to access Git repositores at all at this stage.
  (let* ((spec      (lambda deps
                      `(channel (version 0)
                                (dependencies
                                 ,@(map (lambda (dep)
                                          `(channel
                                            (name ,dep)
                                            (url "http://example.org")))
                                        deps)))))
         (guix      (make-instance #:name 'guix))
         (instance0 (make-instance #:name 'a))
         (instance1 (make-instance #:name 'b #:spec (spec 'a)))
         (instance2 (make-instance #:name 'c #:spec (spec 'b)))
         (instance3 (make-instance #:name 'd #:spec (spec 'c 'a))))
    (%graft? #f)                                    ;don't try to build stuff

    ;; Create 'build-self.scm' so that GUIX is recognized as the 'guix' channel.
    (let ((source (channel-instance-checkout guix)))
      (mkdir (string-append source "/build-aux"))
      (call-with-output-file (string-append source
                                            "/build-aux/build-self.scm")
        (lambda (port)
          (write '(begin
                    (use-modules (guix) (gnu packages bootstrap))

                    (lambda _
                      (package->derivation %bootstrap-guile)))
                 port))))

    (with-store store
      (let ()
        (define manifest
          (run-with-store store
            (channel-instances->manifest (list guix
                                               instance0 instance1
                                               instance2 instance3))))

        (define entries
          (manifest-entries manifest))

        (define (depends? drv in out)
          ;; Return true if DRV depends (directly or indirectly) on all of IN
          ;; and none of OUT.
          (let ((set (list->set
                      (requisites store
                                  (list (derivation-file-name drv)))))
                (in  (map derivation-file-name in))
                (out (map derivation-file-name out)))
            (and (every (cut set-contains? set <>) in)
                 (not (any (cut set-contains? set <>) out)))))

        (define (lookup name)
          (run-with-store store
            (lower-object
             (manifest-entry-item
              (manifest-lookup manifest
                               (manifest-pattern (name name)))))))

        (let ((drv-guix (lookup "guix"))
              (drv0     (lookup "a"))
              (drv1     (lookup "b"))
              (drv2     (lookup "c"))
              (drv3     (lookup "d")))
          (and (depends? drv-guix '() (list drv0 drv1 drv2 drv3))
               (depends? drv0
                         (list) (list drv1 drv2 drv3))
               (depends? drv1
                         (list drv0) (list drv2 drv3))
               (depends? drv2
                         (list drv1) (list drv3))
               (depends? drv3
                         (list drv2 drv0) (list))))))))

(test-end "channels")
