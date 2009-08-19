#!/bin/sh

[ -f Makefile ] && make distclean
perl Makefile.PL
make manifest
make distcheck
git status
