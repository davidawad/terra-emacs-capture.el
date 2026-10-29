;;; terra-emacs-capture-claude.el --- capturing Claude Code sessions -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <davidawad@protonmail.com>
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A Claude Code session running in an eat buffer captures as:
;;
;;   session-id  from ~/.claude/sessions/<pid>.json of the claude
;;               process (the eat process or one of its descendants).
;;   cwd, argv   the claude command line minus --resume, --session-id
;;               and --continue (`terra-emacs-claude-resume-flags').
;;   env         the variables named by
;;               `terra-emacs-capture-claude-env-regexp' it was given,
;;               never one matching
;;               `terra-emacs-capture-claude-secret-regexp'.
;;
;; The engine's terra-emacs-claude.el resumes such a record, scrubbed
;; of inherited agent variables, and keeps to one writer per session.

;;; Code:

(require 'cl-lib)
(require 'terra-emacs)
(require 'terra-emacs-capture-handlers)

(define-obsolete-variable-alias 'terra-emacs-claude-env-regexp
  'terra-emacs-capture-claude-env-regexp "0.2.0")
(define-obsolete-variable-alias 'terra-emacs-claude-secret-regexp
  'terra-emacs-capture-claude-secret-regexp "0.2.0")

(defcustom terra-emacs-capture-claude-env-regexp
  "\\`\\(CLAUDE_CONFIG_DIR\\|ANTHROPIC_[A-Z0-9_]*\\|CLAUDE_CODE_[A-Z0-9_]*\\)\\'"
  "Names of the variables a capture records from a session's environment."
  :type 'regexp :group 'terra-emacs-claude)

(defcustom terra-emacs-capture-claude-secret-regexp "TOKEN\\|KEY\\|SECRET\\|PASSWORD"
  "Names matching this (any case) are never recorded."
  :type 'regexp :group 'terra-emacs-claude)

(defun terra-emacs-capture-claude--session-in (buffer)
  "The live session record whose claude runs in BUFFER, or nil."
  (let ((proc (get-buffer-process buffer)))
    (and proc (process-live-p proc)
         (cl-find-if (lambda (s) (and (terra-emacs-claude-pid-live-p (plist-get s :pid))
                                      (terra-emacs-claude-descends-p (plist-get s :pid)
                                                                     (process-id proc))))
                     (terra-emacs-claude-sessions)))))

(defun terra-emacs-capture-claude--argv (buffer session)
  "The claude command line of BUFFER (whose live SESSION record may be nil)."
  (let ((argv (terra-emacs-capture-eat-argv buffer)))
    (unless (and argv (string-match-p "claude" (file-name-nondirectory (car argv))))
      ;; eat runs a shell, or a wrapper: take claude's own arguments.
      (let* ((args (and session (alist-get 'args (process-attributes (plist-get session :pid)))))
             (words (and args (split-string args " " t))))
        (setq argv (or (cl-member-if (lambda (w) (string-match-p "claude" (file-name-nondirectory w)))
                                     words)
                       (list terra-emacs-claude-program)))))
    (terra-emacs-claude-strip-argv argv)))

(defun terra-emacs-capture-claude--proc-env (pid)
  "PID's environment as (NAME . VALUE) pairs, where /proc shows it."
  (let ((file (format "/proc/%d/environ" pid)))
    (when (file-readable-p file)
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (ignore-errors (insert-file-contents-literally file))
        (delq nil (mapcar (lambda (e) (when (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" e)
                                        (cons (match-string 1 e) (match-string 2 e))))
                          (split-string (buffer-string) "\0" t)))))))

(defun terra-emacs-capture-claude-recordable-env (pairs)
  "PAIRS ((NAME . VALUE) ...) a capture may record: needed, never secret."
  (let ((case-fold-search t))
    (cl-remove-if (lambda (p) (or (string-match-p terra-emacs-capture-claude-secret-regexp (car p))
                                  (let ((case-fold-search nil))
                                    (not (string-match-p terra-emacs-capture-claude-env-regexp
                                                         (car p))))))
                  (cl-remove-duplicates pairs :key #'car :test #'equal :from-end t))))

(defun terra-emacs-capture-claude (buffer)
  "The leaf record of BUFFER when it is an eat buffer running Claude Code."
  (when (eq (buffer-local-value 'major-mode buffer) 'eat-mode)
    (let* ((session (terra-emacs-capture-claude--session-in buffer))
           (id (or (plist-get session :sessionId)
                   (buffer-local-value 'terra-emacs-claude-session buffer))))
      (when id
        (with-current-buffer buffer
          (terra-emacs-leaf-make
           (buffer-name)
           'handler 'terra-emacs-claude-bookmark-handler
           'buffer-name (buffer-name) 'session-id id
           'cwd (or (plist-get session :cwd) default-directory)
           'argv (terra-emacs-capture-claude--argv buffer session)
           'env (terra-emacs-capture-claude-recordable-env
                 (append terra-emacs-claude-env
                         (and session (terra-emacs-capture-claude--proc-env
                                       (plist-get session :pid)))))))))))

;; Before the generic eat handler: a Claude buffer is an eat buffer too.
(add-hook 'terra-emacs-leaf-capture-functions #'terra-emacs-capture-claude -50)

(provide 'terra-emacs-capture-claude)
;;; terra-emacs-capture-claude.el ends here
