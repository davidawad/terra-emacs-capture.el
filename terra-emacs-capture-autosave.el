;;; terra-emacs-capture-autosave.el --- named sets and autosave -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <davidawad@protonmail.com>
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A restart should change nothing.  `terra-emacs-capture-autosave-mode'
;; writes the full state (`terra-emacs-capture-all') to the set named
;; `terra-emacs-autosave-name' when Emacs exits (`kill-emacs-hook') and
;; every `terra-emacs-capture-autosave-interval' seconds on a plain
;; repeating timer (idle timers do not fire in every Emacs build,
;; neomacs among them), and has the engine apply that set when Emacs
;; starts (`terra-emacs-restore-at-start').  Until the start-up apply
;; has run, nothing is autosaved, so a fresh Emacs never writes its
;; empty state over the one it is about to restore.
;;
;; `terra-emacs-capture-save' NAME writes the named set NAME; the
;; engine's `terra-emacs-apply-set' converges on one.

;;; Code:

(require 'terra-emacs)
(require 'terra-emacs-capture-core)

(define-obsolete-variable-alias 'terra-emacs-autosave-interval
  'terra-emacs-capture-autosave-interval "0.2.0")

(defcustom terra-emacs-capture-autosave-interval 300
  "Seconds between autosaves while `terra-emacs-capture-autosave-mode' is on."
  :type 'integer :group 'terra-emacs)

(defvar terra-emacs-capture-autosave--timer nil "The autosave timer.")

;;;###autoload
(defun terra-emacs-capture-save (&optional name)
  "Write the full state as the set NAME (default: the autosave set); its file."
  (interactive (list (terra-emacs-read-set-name "Save set: ")))
  (let ((file (terra-emacs-capture-write
               (terra-emacs-set-file (or name terra-emacs-autosave-name)))))
    (when (called-interactively-p 'any) (message "terra-emacs: saved %s" file))
    file))

(defun terra-emacs-capture-autosave-save ()
  "Write the autosave set, unless a start-up apply is still pending.
Errors are reported, never raised: this runs on `kill-emacs-hook'."
  (when (or terra-emacs-autosave--restored (not terra-emacs-autosave-restore))
    (condition-case err
        (terra-emacs-capture-save terra-emacs-autosave-name)
      (error (message "terra-emacs: autosave failed: %s" (error-message-string err))))))

;;;###autoload
(define-minor-mode terra-emacs-capture-autosave-mode
  "Save the workspace state on exit and every few minutes; restore it at start."
  :global t :group 'terra-emacs
  (when terra-emacs-capture-autosave--timer
    (cancel-timer terra-emacs-capture-autosave--timer)
    (setq terra-emacs-capture-autosave--timer nil))
  (remove-hook 'kill-emacs-hook #'terra-emacs-capture-autosave-save)
  (when terra-emacs-capture-autosave-mode
    (add-hook 'kill-emacs-hook #'terra-emacs-capture-autosave-save)
    (setq terra-emacs-capture-autosave--timer
          (run-at-time terra-emacs-capture-autosave-interval terra-emacs-capture-autosave-interval
                       #'terra-emacs-capture-autosave-save))
    (terra-emacs-restore-at-start)))

;;;; Names from before the split

(define-obsolete-function-alias 'terra-emacs-save #'terra-emacs-capture-save "0.2.0")
(define-obsolete-function-alias 'terra-emacs-autosave-save
  #'terra-emacs-capture-autosave-save "0.2.0")
(define-obsolete-function-alias 'terra-emacs-autosave-mode
  #'terra-emacs-capture-autosave-mode "0.2.0")

(provide 'terra-emacs-capture-autosave)
;;; terra-emacs-capture-autosave.el ends here
