# Wrapper to ensure the repo Makefile is used when running plain `make`.
# Ignore MAKEFILES from the environment to avoid pulling in other makefiles.
override MAKEFILES :=
unexport MAKEFILES
include $(CURDIR)/Makefile
