# terra-emacs-capture

The exporter for [terra-emacs](https://github.com/davidawad/terra-emacs.el).
terra-emacs reads a declarative state file and converges Emacs on it.
terra-emacs-capture goes the other way: it captures any live workspace,
or the whole set, and writes it out as a state file the engine applies.
With `terra-emacs-capture-autosave-mode` on, the state is written on exit
and every few minutes and applied again at start, so a restart changes
nothing.

Pure Emacs Lisp, Emacs 29.1 or later. It depends on terra-emacs and
nothing else. eat, vterm and persp-mode are used when present.

## Install

Emacs 30 and later, with `package-vc` (install the engine first):

```elisp
(package-vc-install "https://github.com/davidawad/terra-emacs.el")
(package-vc-install "https://github.com/davidawad/terra-emacs-capture.el")
(require 'terra-emacs-capture)
(terra-emacs-capture-autosave-mode 1)   ; optional: save on exit, restore at start
```

Emacs 29.1, or by hand: clone both repositories and put them on
`load-path`.

```elisp
(add-to-list 'load-path "~/src/terra-emacs.el")
(add-to-list 'load-path "~/src/terra-emacs-capture.el")
(require 'terra-emacs-capture)
```

## Commands

| Command | Does |
|---|---|
| `terra-emacs-capture-all` | the full state: levels, every workspace in order, each layout (shown in `*terra-emacs-state*` when called interactively) |
| `terra-emacs-capture` | one workspace's state |
| `terra-emacs-capture-write FILE` | capture the full state and write it to FILE |
| `terra-emacs-capture-save NAME` | write it as the named set `NAME.eld` in `terra-emacs-directory`; the engine's `terra-emacs-apply-set NAME` converges on it |
| `terra-emacs-capture-autosave-mode` | save on `kill-emacs-hook` and every `terra-emacs-capture-autosave-interval` seconds; the engine applies the autosave at start |

```elisp
(terra-emacs-capture-write "~/layouts/work.eld")   ; capture
(terra-emacs-apply "~/layouts/work.eld")           ; the engine: nil, nothing to do
```

Capturing shows nothing. A hidden workspace (another tab, another
perspective) is read off the window state its backend keeps for it, so
each workspace is captured with its own windows and buffers, never the
shown one's. A hidden window whose buffer was killed keeps the record
it was last captured or applied with; without one it is left out, as
showing the workspace leaves it out.

The format is the engine's; see its
[README](https://github.com/davidawad/terra-emacs.el#the-format).

## What a leaf captures

| Buffer | Captured |
|---|---|
| files, dired, Info, help, ... | `bookmark-make-record`, minus the context strings that change with every edit |
| eshell | cwd, buffer name |
| eat | cwd, argv, read off the process (`eat-exec-hook`), also for a terminal started by hand. eat has no bookmark support of its own; this adds a `bookmark-make-record-function` |
| vterm | cwd, the command it was started with (else `vterm-shell`) |
| Claude Code in eat | the session id from `~/.claude/sessions/<pid>.json` of the claude process (the eat process or a descendant), cwd, argv minus `--resume`/`--session-id`/`--continue`, and env: only names matching `terra-emacs-capture-claude-env-regexp`, never one matching `terra-emacs-capture-claude-secret-regexp` (TOKEN, KEY, SECRET, PASSWORD, any case) |
| anything else | the buffer name |

A leaf whose process has ended is captured stale, so a plan restarts it;
a state file never records that mark.

Handlers are the functions on `terra-emacs-leaf-capture-functions` (the
engine's hook). Add one with `(add-hook 'terra-emacs-leaf-capture-functions
FN)`: FN takes a buffer and returns a record whose `handler` restores it,
or nil to pass. The engine also asks these handlers when it plans, so a
plan compares like with like.

## Names from before the split

terra-emacs 0.1.0 shipped capture and apply in one package. These old
names are obsolete aliases here: `terra-emacs-save`,
`terra-emacs-autosave-mode`, `terra-emacs-autosave-save`,
`terra-emacs-autosave-interval`, `terra-emacs-leaf-capture`,
`terra-emacs-layout-capture` (now `terra-emacs-capture-frame`),
`terra-emacs-claude-env-regexp` and `terra-emacs-claude-secret-regexp`.

## Tests

`make test` byte-compiles every file with warnings as errors, then runs
each `test/test-*.el` ERT suite in its own batch Emacs. The engine comes
from `TERRA_EMACS_DIR` (default: a sibling checkout, `../terra-emacs.el`).
eat and persp-mode come from `TERRA_EMACS_TEST_PACKAGES` or the
colon-separated directories in `TERRA_EMACS_TEST_LOAD_PATH`; tests
needing one skip without it. The suites include the round trip through
the engine: capture, write the state file, apply it to an emptied Emacs,
capture again (equal), and plan again (empty), for tab-bar and
persp-mode.

```sh
git clone https://github.com/davidawad/terra-emacs.el ../terra-emacs.el
make test
```

## License

MIT. See [LICENSE](LICENSE).
