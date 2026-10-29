;;; test-terra-emacs-capture-core.el --- capture, and the round trip through the engine -*- lexical-binding: t; -*-

;;; Commentary:
;; Capturing a workspace (split tree plus leaf records) and the whole
;; set (levels, every workspace with name, level, order); hidden
;; workspaces, tab-bar and persp-mode, captured without being shown and
;; still showing their own windows after switching away and back; and
;; the round trip: capture -> state file -> the engine's apply ->
;; capture again: equal, and a second plan is empty.

;;; Code:

(require 'terra-emacs-capture-test-helper
         (expand-file-name "terra-emacs-capture-test-helper"
                           (file-name-directory (or load-file-name buffer-file-name))))
(require 'terra-emacs-capture)

(defvar terra-emacs-test--dir nil)

(defun terra-emacs-test--file (name)
  "A file NAME in a fresh temp dir, created with some text."
  (let ((f (expand-file-name name (or terra-emacs-test--dir
                                      (setq terra-emacs-test--dir (terra-emacs-test-tmpdir))))))
    ;; A buffer still visiting it would make `find-file' ask about the change.
    (when (get-file-buffer f) (kill-buffer (get-file-buffer f)))
    (with-temp-file f (insert "line one\nline two\nline three\n"))
    f))

(defun terra-emacs-test--split-layout (a b)
  "Lay out the selected frame by hand: file A left, file B and *scratch* right."
  (delete-other-windows)
  (find-file a)
  (let ((right (split-window-right)))
    (with-selected-window right
      (find-file b)
      (goto-char (point-min)) (forward-line 1)
      (split-window-below)
      (other-window 1)
      (switch-to-buffer "*scratch*"))))

(defun terra-emacs-test--keys (tree)
  "TREE's leaf keys."
  (mapcar #'terra-emacs-leaf-key (terra-emacs-layout-leaves tree)))

(defun terra-emacs-test--shown ()
  "The buffer names the selected frame shows, in window order."
  (mapcar (lambda (w) (buffer-name (window-buffer w)))
          (window-list nil 'nomini (frame-first-window))))

(ert-deftest terra-emacs-capture-workspace-tree ()
  (terra-emacs-test-reset-tabs)
  (let ((a (terra-emacs-test--file "a.txt"))
        (b (terra-emacs-test--file "b.txt")))
    (terra-emacs-test--split-layout a b)
    (let* ((ws (terra-emacs-capture "*reset*" 'tab-bar))
           (tree (plist-get ws :layout)))
      (should (equal (plist-get ws :name) "*reset*"))
      (should (stringp (plist-get ws :id)))
      (should (eq (plist-get tree :split) 'right))
      (should (equal (plist-get tree :sizes) '(0.5 0.5)))
      (let ((left (nth 0 (plist-get tree :children)))
            (right (nth 1 (plist-get tree :children))))
        (should (equal (terra-emacs-leaf-key (plist-get left :leaf)) (list 'file a)))
        (should (plist-get left :selected))
        (should (eq (plist-get right :split) 'below))
        ;; A file leaf is its bookmark record: position and all.
        (should (terra-emacs-leaf-prop (plist-get (car (plist-get right :children)) :leaf) 'position))
        (should (equal (terra-emacs-test--keys right) (list (list 'file b) '(buffer "*scratch*")))))
      ;; Laying the tree out again (the engine) in a bare frame gives the same tree.
      (delete-other-windows)
      (switch-to-buffer "*Messages*")
      (kill-buffer (get-file-buffer b))
      (terra-emacs-layout-apply tree)
      (should (= 3 (length (window-list nil 'nomini))))
      (should (equal (buffer-file-name (window-buffer (selected-window))) a))
      (should (terra-emacs-layout-same-p tree (terra-emacs-capture-frame))))))

(ert-deftest terra-emacs-capture-all-set ()
  (terra-emacs-test-reset-tabs)
  (let ((terra-emacs-levels '((:id "ops" :name "Operations"))))
    (tab-bar-rename-tab "main")
    (terra-emacs-backend-create 'tab-bar "mail")
    (terra-emacs-backend-create 'tab-bar "notes")
    (terra-emacs-backend-set-level 'tab-bar "mail" "ops")
    (terra-emacs-backend-set-level 'tab-bar "notes" "home")
    (let ((state (terra-emacs-capture-all 'tab-bar)))
      (should (equal (plist-get state :terra-emacs) terra-emacs-format-version))
      (should (eq (plist-get state :backend) 'tab-bar))
      (should (equal (plist-get state :current) "main"))
      (should (equal (mapcar (lambda (w) (plist-get w :name)) (plist-get state :workspaces))
                     '("main" "mail" "notes")))
      (should (equal (mapcar (lambda (w) (plist-get w :level)) (plist-get state :workspaces))
                     '(nil "ops" "home")))
      ;; A level a workspace uses but no declaration names is declared.
      (should (equal (plist-get state :levels)
                     '((:id "ops" :name "Operations") (:id "home" :name "home"))))
      ;; Capturing did not change what is shown.
      (should (equal (terra-emacs-backend-current 'tab-bar) "main"))
      ;; Ids are stable: a second capture reports the same ones.
      (should (equal (mapcar (lambda (w) (plist-get w :id)) (plist-get state :workspaces))
                     (mapcar (lambda (w) (plist-get w :id))
                             (plist-get (terra-emacs-capture-all 'tab-bar) :workspaces)))))))

(ert-deftest terra-emacs-capture-reads-hidden-workspaces-without-showing-them ()
  (terra-emacs-test-reset-tabs)
  (let ((a (terra-emacs-test--file "a.txt"))
        (b (terra-emacs-test--file "b.txt"))
        (switches 0))
    (tab-bar-rename-tab "main")
    (find-file a)
    (terra-emacs-backend-create 'tab-bar "other")
    (terra-emacs-backend-with-workspace 'tab-bar "other"
                                        (lambda () (terra-emacs-test--split-layout a b)))
    (let ((count (lambda (&rest _) (cl-incf switches))))
      (advice-add 'tab-bar-select-tab :before count)
      (unwind-protect
          (let ((other (terra-emacs-capture "other" 'tab-bar)))
            (should (= switches 0))
            (should (equal (terra-emacs-test--keys (plist-get other :layout))
                           (list (list 'file a) (list 'file b) '(buffer "*scratch*")))))
        (advice-remove 'tab-bar-select-tab count)))))

(defun terra-emacs-test--persp-two-windows (name left right)
  "Make perspective NAME show buffers LEFT | RIGHT, by hand."
  (persp-add-new name)
  (persp-switch name)
  (delete-other-windows)
  (switch-to-buffer left)
  (select-window (split-window-right))
  (switch-to-buffer right))

(ert-deftest terra-emacs-capture-persp-hidden-workspace-keeps-its-own-windows ()
  ;; A perspective that is not current captures its own windows and
  ;; buffers, before and after switching away and back, and switching
  ;; back still shows both of them (never one buffer in both windows).
  (skip-unless (terra-emacs-test-have 'persp-mode))
  (terra-emacs-test-persp-on)
  (unwind-protect
      (let* ((a (terra-emacs-test--file "a.txt"))
             (b (terra-emacs-test--file "b.txt"))
             (c (terra-emacs-test--file "c.txt"))
             (d (terra-emacs-test--file "d.txt"))
             (one (list (list 'file a) (list 'file b)))
             (two (list (list 'file c) (list 'file d)))
             (switches 0)
             (count (lambda (&rest _) (cl-incf switches))))
        (terra-emacs-test--persp-two-windows "one" (find-file-noselect a) (find-file-noselect b))
        (terra-emacs-test--persp-two-windows "two" (find-file-noselect c) (find-file-noselect d))
        (dotimes (_ 2)
          ;; "two" is shown: "one" is hidden.
          (advice-add 'persp-switch :before count)
          (unwind-protect
              (progn
                (should (equal (terra-emacs-test--keys (terra-emacs-capture-layout 'persp-mode "one"))
                               one))
                (should (equal (terra-emacs-test--keys (terra-emacs-capture-layout 'persp-mode "two"))
                               two))
                (should (equal (mapcar (lambda (w) (terra-emacs-test--keys (plist-get w :layout)))
                                       (plist-get (terra-emacs-capture-all 'persp-mode) :workspaces))
                               (list one two))))
            (advice-remove 'persp-switch count))
          (should (= switches 0))
          (should (equal (terra-emacs-backend-current 'persp-mode) "two"))
          ;; Away and back: each still shows its own two buffers.
          (persp-switch "one")
          (should (equal (terra-emacs-test--shown) '("a.txt" "b.txt")))
          (should (equal (terra-emacs-test--keys (terra-emacs-capture-layout 'persp-mode "two")) two))
          (persp-switch "two")
          (should (equal (terra-emacs-test--shown) '("c.txt" "d.txt")))))
    (terra-emacs-test-persp-off)))

(ert-deftest terra-emacs-capture-persp-hidden-window-whose-buffer-died ()
  ;; The one way a hidden workspace comes back showing fewer (or, with
  ;; `window-restore-killed-buffer-windows' set, repeated) buffers: a
  ;; buffer it showed was killed while it was hidden.  The window state
  ;; names buffers by name, so `window-state-put' has nothing to show.
  ;; Capture never writes a nil leaf for it: it keeps the record the
  ;; window was captured with, else leaves the window out.
  (skip-unless (terra-emacs-test-have 'persp-mode))
  (terra-emacs-test-persp-on)
  (unwind-protect
      (let ((a (terra-emacs-test--file "a.txt")))
        (terra-emacs-test--persp-two-windows "plain" (get-buffer-create "*left*")
                                             (get-buffer-create "*right*"))
        (terra-emacs-test--persp-two-windows "files" (find-file-noselect a)
                                             (get-buffer-create "*doomed*"))
        ;; Captured once while shown: the windows remember their records.
        (terra-emacs-capture "files" 'persp-mode)
        (persp-add-new "third")
        (persp-switch "third")
        ;; Both hidden now; a buffer of each dies.
        (kill-buffer "*right*")
        (kill-buffer "*doomed*")
        (let ((files (terra-emacs-capture-layout 'persp-mode "files")))
          (should (equal (terra-emacs-test--keys files) (list (list 'file a) '(buffer "*doomed*")))))
        ;; Never captured with a record: left out, as showing it leaves it out.
        (let ((plain (terra-emacs-capture-layout 'persp-mode "plain")))
          (should (equal (terra-emacs-test--keys plain) '((buffer "*left*"))))
          (should-not (memq nil (terra-emacs-layout-leaves plain))))
        (persp-switch "plain")
        (should (equal (terra-emacs-test--shown) '("*left*"))))
    (terra-emacs-test-persp-off)))

(ert-deftest terra-emacs-capture-generic-leaves ()
  (let ((dir (terra-emacs-test-tmpdir)))
    ;; Dired restores through bookmark.el's default record (its directory).
    (let* ((buf (dired-noselect dir))
           (rec (terra-emacs-capture-leaf buf)))
      (should (equal (terra-emacs-leaf-key rec) (list 'file dir)))
      (kill-buffer buf)
      (should (eq (with-current-buffer (terra-emacs-leaf-restore rec) major-mode) 'dired-mode)))
    ;; A plain buffer comes back by name.
    (let ((rec (terra-emacs-capture-leaf (get-buffer-create "*plain*"))))
      (kill-buffer "*plain*")
      (should (equal (buffer-name (terra-emacs-leaf-restore rec)) "*plain*")))
    ;; The names from before the split still work.
    (should (equal (terra-emacs-leaf-capture (get-buffer-create "*plain*"))
                   (terra-emacs-capture-leaf (get-buffer "*plain*"))))))

;;;; Capture -> state file -> apply -> capture

(defun terra-emacs-test--files (&rest names)
  "Fresh files NAMES in one temp dir, as absolute paths."
  (let ((dir (terra-emacs-test-tmpdir)))
    (mapcar (lambda (n)
              (let ((f (expand-file-name n dir)))
                (with-temp-file f (insert n "\nsecond line\n"))
                f))
            names)))

(defun terra-emacs-test--build-by-hand (backend a b c)
  "Lay out three workspaces in BACKEND by hand over files A, B and C."
  (let ((ws (lambda (name)
              (if (eq backend 'tab-bar)
                  (progn (tab-bar-new-tab) (tab-bar-rename-tab name))
                (persp-add-new name) (persp-switch name)))))
    (funcall ws "code")
    (terra-emacs-test--split-layout a b)
    (terra-emacs-backend-set-level backend "code" "ops")
    (funcall ws "notes")
    (delete-other-windows)
    (find-file c)
    (terra-emacs-backend-set-level backend "notes" "home")
    (funcall ws "mail")
    (delete-other-windows)
    (switch-to-buffer "*scratch*")
    (terra-emacs-backend-select backend "code")
    (when (eq backend 'tab-bar) (terra-emacs-backend-kill 'tab-bar "*reset*"))))

(defun terra-emacs-test--round-trip (backend reset)
  "Capture BACKEND into a file, RESET, apply the file, capture: equal."
  (let* ((files (terra-emacs-test--files "a.txt" "b.txt" "c.txt"))
         (file (expand-file-name "state.eld" (terra-emacs-test-tmpdir))))
    (apply #'terra-emacs-test--build-by-hand backend files)
    (terra-emacs-capture-write file backend)
    (let ((before (terra-emacs-read-state file)))
      ;; Each workspace's own windows were captured, not the shown one's.
      (should (equal (mapcar (lambda (w) (length (terra-emacs-layout-leaves (plist-get w :layout))))
                             (plist-get before :workspaces))
                     '(3 1 1)))
      (funcall reset)
      (setq terra-emacs-levels nil)
      (should-not (member "code" (terra-emacs-backend-workspaces backend)))
      (should (terra-emacs-apply file nil backend))
      (should (equal (terra-emacs-state-clean (terra-emacs-capture-all backend)) before))
      ;; A second plan is empty, from the file and from a fresh capture.
      (should-not (terra-emacs-plan file backend))
      (should-not (terra-emacs-plan (terra-emacs-capture-all backend) backend))
      (should-not (terra-emacs-apply file nil backend)))))

(ert-deftest terra-emacs-capture-round-trip-tab-bar ()
  (terra-emacs-test-reset-tabs)
  (let ((terra-emacs-levels nil))
    (terra-emacs-test--round-trip 'tab-bar #'terra-emacs-test-reset-tabs)))

(ert-deftest terra-emacs-capture-round-trip-persp-mode ()
  (skip-unless (terra-emacs-test-have 'persp-mode))
  (terra-emacs-test-persp-on)
  (unwind-protect
      (let ((terra-emacs-levels nil))
        (terra-emacs-test--round-trip 'persp-mode #'terra-emacs-test-persp-on))
    (terra-emacs-test-persp-off)))

(provide 'test-terra-emacs-capture-core)
;;; test-terra-emacs-capture-core.el ends here
