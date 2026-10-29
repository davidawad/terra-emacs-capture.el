;;; terra-emacs-capture-core.el --- the declarative state of a live Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <davidawad@protonmail.com>
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Capture reads a live Emacs into a terra-emacs state (the format is the
;; engine's: terra-emacs-state.el):
;;
;;   `terra-emacs-capture-all'     every workspace of the backend, in
;;                                 order, with the levels and the one shown
;;   `terra-emacs-capture'         one workspace: name, id, level,
;;                                 saved parameters, layout
;;   `terra-emacs-capture-layout'  one workspace's split tree; a hidden one
;;                                 is read off its backend's window state,
;;                                 so capturing shows nothing
;;   `terra-emacs-capture-frame'   the split tree a frame shows
;;   `terra-emacs-capture-leaf'    one buffer's leaf record
;;
;; A leaf record comes from the first of
;; `terra-emacs-leaf-capture-functions' that answers (this package puts
;; eshell, eat, vterm and Claude Code there), else the buffer's own
;; bookmark record, else its name.

;;; Code:

(require 'cl-lib)
(require 'bookmark)
(require 'terra-emacs)

(defconst terra-emacs-capture-dropped-properties
  '(front-context-string rear-context-string front-context-region-string
    rear-context-region-string last-modified defaults annotation)
  "Bookmark properties a leaf record leaves out: they change with every edit.")

;;;; Leaves

(defun terra-emacs-capture--bookmark (buffer)
  "BUFFER's own bookmark record, trimmed, or nil when it has none."
  (with-current-buffer buffer
    (when (or buffer-file-name
              (bound-and-true-p dired-directory)
              (not (eq bookmark-make-record-function #'bookmark-make-record-default)))
      (let ((rec (ignore-errors (bookmark-make-record))))
        (when (consp rec)
          (cons (buffer-name)
                (append (cl-remove-if (lambda (c)
                                        (or (memq (car-safe c) terra-emacs-capture-dropped-properties)
                                            (eq (car-safe c) 'buffer-name)))
                                      (if (stringp (car rec)) (cdr rec) rec))
                        (list (cons 'buffer-name (buffer-name))))))))))

(defun terra-emacs-capture-leaf (buffer)
  "The leaf record that brings BUFFER back.
Marked stale (`terra-stale') when its process has ended."
  (terra-emacs-leaf-mark-stale
   (or (run-hook-with-args-until-success 'terra-emacs-leaf-capture-functions buffer)
       (terra-emacs-capture--bookmark buffer)
       (terra-emacs-leaf-make (buffer-name buffer)
                              'handler 'terra-emacs-leaf-buffer-handler
                              'buffer-name (buffer-name buffer)))
   buffer))

(defun terra-emacs-capture--leaf-fn (buffer _placed)
  "BUFFER's captured record: the leaf function given to the engine's readers."
  (terra-emacs-capture-leaf buffer))

;;;; Layouts

(defun terra-emacs-capture-frame (&optional frame)
  "The layout FRAME (default: the selected one) shows, side windows aside."
  (terra-emacs-layout-current frame #'terra-emacs-capture--leaf-fn))

(defun terra-emacs-capture-layout (backend name)
  "The layout of BACKEND's workspace NAME.
A hidden workspace is read off the window state BACKEND keeps for it,
so capturing shows nothing; else it is captured shown.  A hidden
window whose buffer is gone keeps the record it was last captured or
applied with; without one it is left out, as showing the workspace
leaves it out."
  (terra-emacs-layout-of backend name #'terra-emacs-capture--leaf-fn))

;;;; Workspaces

(defun terra-emacs-capture--ws-id (backend name)
  "The id of workspace NAME in BACKEND, assigning one when it has none."
  (or (terra-emacs-backend-id backend name)
      (let ((id (terra-emacs-new-id)))
        (terra-emacs-backend-set-id backend name id)
        id)))

;;;###autoload
(defun terra-emacs-capture (&optional workspace backend)
  "The state of WORKSPACE (default: the shown one) in BACKEND.
Interactively, show it in a buffer."
  (interactive)
  (let* ((backend (or backend (terra-emacs-current-backend)))
         (name (or workspace (terra-emacs-backend-current backend)))
         (layout (terra-emacs-capture-layout backend name))
         (level (terra-emacs-backend-level backend name))
         (params (terra-emacs-backend-parameters backend name))
         (ws (append (list :name name :id (terra-emacs-capture--ws-id backend name))
                     (and level (list :level level))
                     (and params (list :parameters params))
                     (list :layout layout))))
    (when (called-interactively-p 'any) (terra-emacs-show-state ws))
    ws))

(defun terra-emacs-capture--levels (declared workspaces)
  "DECLARED levels plus one for each level WORKSPACES use that none names."
  (let ((levels (copy-sequence declared)))
    (dolist (ws workspaces)
      (let ((level (plist-get ws :level)))
        (when (and level (not (cl-find level levels
                                       :key (lambda (l) (plist-get l :id)) :test #'equal)))
          (setq levels (append levels (list (list :id level :name (format "%s" level))))))))
    levels))

;;;###autoload
(defun terra-emacs-capture-all (&optional backend)
  "The full state: every workspace of BACKEND, in order, and the levels.
Interactively, show it in a buffer."
  (interactive)
  (let* ((backend (or backend (terra-emacs-current-backend)))
         (workspaces (mapcar (lambda (name) (terra-emacs-capture name backend))
                             (terra-emacs-backend-workspaces backend)))
         (state (list :terra-emacs terra-emacs-format-version
                      :backend backend
                      :levels (terra-emacs-capture--levels (terra-emacs-backend-levels backend)
                                                           workspaces)
                      :current (terra-emacs-backend-current backend)
                      :workspaces workspaces)))
    (when (called-interactively-p 'any) (terra-emacs-show-state state))
    state))

;;;###autoload
(defun terra-emacs-capture-write (file &optional backend)
  "Capture the full state of BACKEND and write it to FILE; FILE."
  (interactive (list (read-file-name "Write terra-emacs state to: ")))
  (terra-emacs-write-state (terra-emacs-capture-all backend) file))

;;;; Names from before the split

(define-obsolete-function-alias 'terra-emacs-leaf-capture #'terra-emacs-capture-leaf "0.2.0")
(define-obsolete-function-alias 'terra-emacs-layout-capture #'terra-emacs-capture-frame "0.2.0")

(provide 'terra-emacs-capture-core)
;;; terra-emacs-capture-core.el ends here
