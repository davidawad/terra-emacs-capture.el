# terra-emacs-capture: capture live Emacs workspaces as terra-emacs state.
#
#   make test      byte-compile (warnings as errors), then every ERT suite
#   make compile   byte-compile only
#   make clean     remove byte-compiled files
#
# The engine comes from TERRA_EMACS_DIR (default: ../terra-emacs.el).

EMACS ?= emacs
TERRA_EMACS_DIR ?= ../terra-emacs.el
export EMACS TERRA_EMACS_DIR

.PHONY: all test compile clean

all: test

test:
	bash test/test_terra_emacs_capture.sh

compile:
	$(EMACS) -Q --batch -L . -L $(TERRA_EMACS_DIR) --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile terra-emacs-capture*.el

clean:
	rm -f *.elc
