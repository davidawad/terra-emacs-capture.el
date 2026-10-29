;;; test-terra-emacs-capture-handlers.el --- capturing eshell, eat, vterm -*- lexical-binding: t; -*-

;;; Commentary:
;; Each handler captures cwd and command into a record the engine
;; restores to the same key; eat gains bookmark support and its command
;; is read off the process even for a terminal started by hand; a leaf
;; whose process died captures stale.  vterm needs a compiled module, so
;; a stand-in defining the slice the handlers use runs here.

;;; Code:

(require 'terra-emacs-capture-test-helper
         (expand-file-name "terra-emacs-capture-test-helper"
                           (file-name-directory (or load-file-name buffer-file-name))))
(require 'terra-emacs-capture)

(defun terra-emacs-test--kill (buffer)
  "Kill BUFFER and its process quietly."
  (when (buffer-live-p buffer)
    (let ((p (get-buffer-process buffer)))
      (when p (set-process-query-on-exit-flag p nil) (delete-process p)))
    (let ((kill-buffer-query-functions nil)) (kill-buffer buffer))))

(ert-deftest terra-emacs-capture-handlers-eshell ()
  (require 'eshell)
  (let* ((dir (terra-emacs-test-tmpdir))
         (buf (let ((default-directory dir) (eshell-buffer-name "*eshell*<cap>"))
                (save-window-excursion (eshell)))))
    (unwind-protect
        (let ((cap (terra-emacs-capture-leaf buf)))
          (should (eq (terra-emacs-leaf-prop cap 'handler) 'terra-emacs-eshell-bookmark-handler))
          (should (equal (terra-emacs-leaf-prop cap 'cwd) dir))
          (should (equal (terra-emacs-leaf-key cap) '(eshell "*eshell*<cap>")))
          ;; The engine brings the same buffer back.
          (should (eq (terra-emacs-leaf-restore cap) buf)))
      (terra-emacs-test--kill buf))))

(ert-deftest terra-emacs-capture-handlers-eat ()
  (skip-unless (terra-emacs-test-have 'eat))
  (let* ((dir (terra-emacs-test-tmpdir))
         (buf (get-buffer-create "*by-hand*")))
    (unwind-protect
        (progn
          ;; Started by hand, not by the engine: argv comes off the process.
          (with-current-buffer buf
            (setq default-directory dir)
            (eat-mode)
            (eat-exec buf "by-hand" "/bin/sh" nil '("-c" "sleep 30")))
          (let ((cap (terra-emacs-capture-leaf buf))
                (pid (process-id (get-buffer-process buf))))
            (should (equal (terra-emacs-leaf-prop cap 'argv) '("/bin/sh" "-c" "sleep 30")))
            (should (equal (terra-emacs-leaf-prop cap 'cwd) dir))
            (should (equal (terra-emacs-leaf-key cap)
                           (list 'eat "*by-hand*" '("/bin/sh" "-c" "sleep 30"))))
            (should-not (terra-emacs-leaf-stale-p cap))
            ;; eat gains bookmark support.
            (should (equal (terra-emacs-leaf-prop (with-current-buffer buf (bookmark-make-record))
                                                  'argv)
                           '("/bin/sh" "-c" "sleep 30")))
            ;; The engine reuses the live process for the captured record.
            (should (eq (terra-emacs-leaf-restore cap) buf))
            (should (= pid (process-id (get-buffer-process buf))))
            ;; Its process gone, the capture is stale; a state file never says so.
            (delete-process (get-buffer-process buf))
            (let ((dead (terra-emacs-capture-leaf buf)))
              (should (terra-emacs-leaf-stale-p dead))
              (should-not (terra-emacs-leaf-stale-p (terra-emacs-leaf-clean dead))))))
      (terra-emacs-test--kill buf))))

;;;; A vterm stand-in: the slice of vterm the handlers use.

(defvar vterm-shell)
(unless (featurep 'vterm)
  (defvar vterm-shell "/bin/sh")
  (define-derived-mode vterm-mode fundamental-mode "VTerm"
    "Stand-in vterm: runs `vterm-shell' in the buffer, through sh as vterm does."
    (make-process :name "vterm" :buffer (current-buffer) :noquery t
                  :command (list "/bin/sh" "-c" (concat "exec " vterm-shell))))
  (provide 'vterm))

(ert-deftest terra-emacs-capture-handlers-vterm ()
  (let* ((dir (terra-emacs-test-tmpdir))
         (cmd "sh -c 'sleep 30'")
         (rec (terra-emacs-leaf-make "*vterm work*" 'handler 'terra-emacs-vterm-bookmark-handler
                                     'buffer-name "*vterm work*" 'cwd dir 'command cmd))
         (buf (terra-emacs-leaf-restore rec)))
    (unwind-protect
        (let ((cap (terra-emacs-capture-leaf buf)))
          (should (equal (terra-emacs-leaf-prop cap 'command) cmd))
          (should (equal (terra-emacs-leaf-prop cap 'cwd) dir))
          (should (equal (terra-emacs-leaf-key cap) (terra-emacs-leaf-key rec)))
          ;; A vterm the engine did not start reports `vterm-shell'.
          (let ((other (get-buffer-create "*vterm other*")))
            (unwind-protect
                (progn
                  (with-current-buffer other (vterm-mode))
                  (should (equal (terra-emacs-leaf-prop (terra-emacs-capture-leaf other) 'command)
                                 vterm-shell)))
              (terra-emacs-test--kill other))))
      (terra-emacs-test--kill buf))))

(provide 'test-terra-emacs-capture-handlers)
;;; test-terra-emacs-capture-handlers.el ends here
