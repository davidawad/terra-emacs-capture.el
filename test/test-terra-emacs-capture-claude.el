;;; test-terra-emacs-capture-claude.el --- capturing Claude Code sessions -*- lexical-binding: t; -*-

;;; Commentary:
;; A fake claude that writes its own ~/.claude/sessions/<pid>.json
;; record, as the real one does, resumed by the engine and then
;; captured: the session id off the session file, argv without resume
;; flags, only the env it needs.  No secrets: the only secret-shaped
;; names are made up and must never be recorded.

;;; Code:

(require 'terra-emacs-capture-test-helper
         (expand-file-name "terra-emacs-capture-test-helper"
                           (file-name-directory (or load-file-name buffer-file-name))))
(require 'terra-emacs-capture)

(defvar terra-emacs-test--sessions nil "The fake sessions directory.")
(defvar terra-emacs-test--out nil "Where the fake claude writes argv and env.")

(defun terra-emacs-test--fake-claude ()
  "A fake claude in a fresh dir; its path."
  (let* ((dir (terra-emacs-test-tmpdir))
         (bin (expand-file-name "claude" dir)))
    (with-temp-file bin
      (insert "#!/bin/sh\n"
              "out=\"$TERRA_FAKE_OUT\"; sid=none; prev=\n"
              "for a in \"$@\"; do echo \"$a\" >> \"$out/argv.tmp\";"
              " [ \"$prev\" = --resume ] && sid=\"$a\"; prev=\"$a\"; done\n"
              "env > \"$out/env\"\n"
              "printf '{\"pid\":%d,\"sessionId\":\"%s\",\"cwd\":\"%s\",\"status\":\"idle\"}'"
              " $$ \"$sid\" \"$PWD\" > \"$TERRA_FAKE_SESSIONS/$$.json\"\n"
              "mv \"$out/argv.tmp\" \"$out/argv\"\n"
              "sleep 30\n"))
    (set-file-modes bin #o755)
    bin))

(defun terra-emacs-test--lines (file)
  "FILE's lines, after waiting up to 5s for it."
  (cl-loop repeat 100 until (file-exists-p file) do (accept-process-output nil 0.05))
  (with-temp-buffer (insert-file-contents file) (split-string (buffer-string) "\n" t)))

(defmacro terra-emacs-test--with-claude (&rest body)
  "Run BODY with fake sessions, a fake claude and an inherited agent env."
  (declare (indent 0))
  `(let* ((terra-emacs-test--sessions (terra-emacs-test-tmpdir))
          (terra-emacs-test--out (terra-emacs-test-tmpdir))
          (terra-emacs-claude-sessions-directory terra-emacs-test--sessions)
          (process-environment
           (append (list (concat "TERRA_FAKE_OUT=" terra-emacs-test--out)
                         (concat "TERRA_FAKE_SESSIONS=" terra-emacs-test--sessions)
                         "CLAUDECODE=1" "CLAUDE_CODE_ENTRYPOINT=cli" "AGENT_NAME=pm"
                         "AWAD_ROLE=x" "LOADOUT_ID=y" "BD_ACTOR=z")
                   process-environment))
          (fake (terra-emacs-test--fake-claude))
          (buffers nil))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (string-prefix-p "*claude" (buffer-name b))
           (let ((p (get-buffer-process b)))
             (when p (set-process-query-on-exit-flag p nil) (delete-process p)))
           (let ((kill-buffer-query-functions nil)) (kill-buffer b)))))))

(defun terra-emacs-test--record (fake id)
  "A captured Claude leaf running FAKE for session ID."
  (terra-emacs-leaf-make (format "*claude %s*" id)
                         'handler 'terra-emacs-claude-bookmark-handler
                         'buffer-name (format "*claude %s*" id)
                         'session-id id 'cwd temporary-file-directory
                         'argv (list fake "--model" "opus" "--resume" "older" "--continue")
                         'env '(("CLAUDE_CONFIG_DIR" . "/tmp/claude-config"))))

(ert-deftest terra-emacs-capture-claude-session ()
  (skip-unless (terra-emacs-test-have 'eat))
  (terra-emacs-test--with-claude
    (let* ((rec (terra-emacs-test--record fake "sess-1"))
           (buf (terra-emacs-leaf-restore rec)))
      (terra-emacs-test--lines (expand-file-name "argv" terra-emacs-test--out))
      (let ((pid (process-id (get-buffer-process buf))))
        ;; The fake wrote ~/.claude/sessions/<pid>.json: live, in Emacs.
        (should (equal (plist-get (terra-emacs-claude-live-session "sess-1") :pid) pid))
        (should (eq (terra-emacs-leaf-restore rec) buf))
        (should (= pid (process-id (get-buffer-process buf))))
        ;; Captured: the session, argv without resume flags, no secrets.
        (with-current-buffer buf
          (setq terra-emacs-claude-env '(("CLAUDE_CONFIG_DIR" . "/tmp/claude-config")
                                         ("FAKE_API_TOKEN" . "made-up")
                                         ("MY_PASSWORD_HINT" . "made-up"))))
        (let ((cap (terra-emacs-capture-leaf buf)))
          (should (equal (terra-emacs-leaf-prop cap 'session-id) "sess-1"))
          (should (equal (terra-emacs-leaf-key cap) '(claude "sess-1")))
          (should (equal (terra-emacs-leaf-prop cap 'argv) (list fake "--model" "opus")))
          (should (equal (terra-emacs-leaf-prop cap 'env)
                         '(("CLAUDE_CONFIG_DIR" . "/tmp/claude-config"))))
          (should-not (terra-emacs-leaf-stale-p cap))
          ;; Restoring the capture reuses the live session: one writer.
          (should (eq (terra-emacs-leaf-restore cap) buf))
          (should (= pid (process-id (get-buffer-process buf)))))))))

(ert-deftest terra-emacs-capture-claude-strips-and-filters ()
  (should (equal (terra-emacs-claude-strip-argv
                  '("claude" "--resume" "a" "--model" "opus" "--session-id=b" "-c" "-r" "x"))
                 '("claude" "--model" "opus")))
  (should (equal (terra-emacs-capture-claude-recordable-env
                  '(("CLAUDE_CONFIG_DIR" . "/c") ("ANTHROPIC_BASE_URL" . "u")
                    ("ANTHROPIC_API_KEY" . "made-up") ("CLAUDE_CODE_OAUTH_TOKEN" . "made-up")
                    ("CLAUDE_CODE_ENTRYPOINT" . "cli") ("HOME" . "/h") ("my_secret_x" . "made-up")
                    ("CLAUDE_CONFIG_DIR" . "/later")))
                 '(("CLAUDE_CONFIG_DIR" . "/c") ("ANTHROPIC_BASE_URL" . "u")
                   ("CLAUDE_CODE_ENTRYPOINT" . "cli")))))

(ert-deftest terra-emacs-capture-claude-not-a-session ()
  ;; An eat buffer with no session is the eat handler's, not Claude's.
  (with-temp-buffer
    (should-not (terra-emacs-capture-claude (current-buffer)))))

(provide 'test-terra-emacs-capture-claude)
;;; test-terra-emacs-capture-claude.el ends here
