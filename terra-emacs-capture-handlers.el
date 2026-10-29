;;; terra-emacs-capture-handlers.el --- capturing eshell, eat and vterm leaves -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <davidawad@protonmail.com>
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The capture side of the engine's terminal handlers
;; (terra-emacs-handlers.el restores them):
;;
;;   eshell  its cwd and buffer name (eshell's own bookmark reopens
;;           *eshell* whatever the name was).
;;   eat     its cwd and the command it runs, read off the process
;;           (`eat-exec-hook'); eat has no bookmark support at all, so
;;           this also gives eat buffers a `bookmark-make-record-function'.
;;   vterm   its cwd and the command it runs (`vterm-shell').
;;
;; A captured leaf whose process has ended is marked stale, so a plan
;; restarts it.

;;; Code:

(require 'cl-lib)
(require 'terra-emacs)

(defvar vterm-shell)

;;;; eshell

(defun terra-emacs-capture-eshell (buffer)
  "The leaf record of BUFFER when it is an eshell."
  (with-current-buffer buffer
    (when (derived-mode-p 'eshell-mode)
      (terra-emacs-leaf-make (buffer-name) 'handler 'terra-emacs-eshell-bookmark-handler
                             'buffer-name (buffer-name) 'cwd default-directory))))

;;;; eat

(defun terra-emacs-capture-eat--note-argv (process)
  "Remember PROCESS's command line in its buffer (`eat-exec-hook')."
  (with-current-buffer (process-buffer process)
    (let ((cmd (process-command process)))
      ;; eat runs: env sh -c SCRIPT .. COMMAND SWITCHES...
      (setq terra-emacs-eat-argv
            (if (and (equal (car cmd) "/usr/bin/env") (equal (nth 4 cmd) ".."))
                (nthcdr 5 cmd)
              cmd)))))

(defun terra-emacs-capture-eat-argv (buffer)
  "The command line BUFFER's eat process runs, or ran."
  (or (buffer-local-value 'terra-emacs-eat-argv buffer)
      (let ((p (get-buffer-process buffer)))
        (and p (with-current-buffer buffer
                 (terra-emacs-capture-eat--note-argv p)
                 terra-emacs-eat-argv)))))

(defun terra-emacs-capture-eat-bookmark-make-record ()
  "The bookmark record of the current eat buffer: its cwd and command."
  (terra-emacs-leaf-mark-stale
   (terra-emacs-leaf-make (buffer-name)
                          'handler 'terra-emacs-eat-bookmark-handler
                          'buffer-name (buffer-name) 'cwd default-directory
                          'argv (terra-emacs-capture-eat-argv (current-buffer)))
   (current-buffer)))

(defun terra-emacs-capture-eat (buffer)
  "The leaf record of BUFFER when it is an eat terminal."
  (with-current-buffer buffer
    (when (derived-mode-p 'eat-mode)
      (terra-emacs-capture-eat-bookmark-make-record))))

(defun terra-emacs-capture-eat--bookmarkable ()
  "Give this eat buffer bookmark support (`eat-mode-hook')."
  (setq-local bookmark-make-record-function #'terra-emacs-capture-eat-bookmark-make-record))

;;;; vterm

(defun terra-emacs-capture-vterm-command (buffer)
  "The command BUFFER's vterm runs.
vterm wraps `vterm-shell' in a shell line of its own, so a vterm the
engine did not start reports `vterm-shell'."
  (or (buffer-local-value 'terra-emacs-vterm-command buffer)
      (bound-and-true-p vterm-shell)))

(defun terra-emacs-capture-vterm (buffer)
  "The leaf record of BUFFER when it is a vterm."
  (with-current-buffer buffer
    (when (derived-mode-p 'vterm-mode)
      (terra-emacs-leaf-make (buffer-name)
                             'handler 'terra-emacs-vterm-bookmark-handler
                             'buffer-name (buffer-name) 'cwd default-directory
                             'command (terra-emacs-capture-vterm-command buffer)))))

;;;; Installing

(defun terra-emacs-capture-handlers-install ()
  "Put the handlers on `terra-emacs-leaf-capture-functions'; give eat bookmarks."
  (add-hook 'terra-emacs-leaf-capture-functions #'terra-emacs-capture-eshell)
  (add-hook 'terra-emacs-leaf-capture-functions #'terra-emacs-capture-eat)
  (add-hook 'terra-emacs-leaf-capture-functions #'terra-emacs-capture-vterm)
  (add-hook 'eat-exec-hook #'terra-emacs-capture-eat--note-argv)
  (add-hook 'eat-mode-hook #'terra-emacs-capture-eat--bookmarkable))

(terra-emacs-capture-handlers-install)

(provide 'terra-emacs-capture-handlers)
;;; terra-emacs-capture-handlers.el ends here
