;;; terra-emacs-capture.el --- Capture live Emacs workspaces as terra-emacs state -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <davidawad@protonmail.com>
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1") (terra-emacs "0.2.0"))
;; Keywords: frames, convenience
;; URL: https://github.com/davidawad/terra-emacs-capture.el
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; terra-emacs (https://github.com/davidawad/terra-emacs.el) reads a
;; declarative state file and converges Emacs on it.  This package is
;; its exporter: it captures any live workspace, or the whole set, and
;; writes it out as a state file the engine applies.
;;
;;   `terra-emacs-capture-all'    the full state: levels, every workspace
;;   `terra-emacs-capture'        one workspace's state
;;   `terra-emacs-capture-write'  capture the full state into a file
;;   `terra-emacs-capture-save'   ... as a named set
;;   `terra-emacs-capture-autosave-mode'   save on exit and every few
;;                                minutes; the engine applies it at start
;;
;; Leaves capture through `terra-emacs-leaf-capture-functions': files,
;; dired and anything with bookmark support for free; eshell, eat and
;; vterm with their cwd and command; Claude Code sessions by session id,
;; argv and the env they need (never a secret).

;;; Code:

(require 'terra-emacs)
(require 'terra-emacs-capture-core)
(require 'terra-emacs-capture-handlers)
(require 'terra-emacs-capture-claude)
(require 'terra-emacs-capture-autosave)

(provide 'terra-emacs-capture)
;;; terra-emacs-capture.el ends here
