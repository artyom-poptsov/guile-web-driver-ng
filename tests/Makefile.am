## Makefile.am -- Config file for GNU Automake.
##
## Copyright (C) 2024 Artyom V. Poptsov <poptsov.artyom@gmail.com>
##
## This file is part of Guile-Web-Driver-NG.
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## The program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with the program.  If not, see <http://www.gnu.org/licenses/>.


SCM_TESTS = \
	web/driver/common.scm		\
	web/driver/element.scm		\
	web/driver/javascript.scm	\
	web/driver/rect.scm		\
	web/driver/cookie.scm		\
	web/proxy/common.scm		\
	web/proxy/connection.scm	\
	web/proxy/interceptor/chain.scm	\
	web/proxy/interceptor.scm	\
	web/proxy.scm

TESTS = ${SCM_TESTS}

TEST_EXTENSIONS = .scm

AM_TESTS_ENVIRONMENT = \
	abs_top_srcdir="$(abs_top_srcdir)"; export abs_top_srcdir; \
	abs_top_builddir="$(abs_top_builddir)"; export abs_top_builddir; \
	ORIGTERM=${TERM}; export ORIGTERM; \
	TERM=xterm; export TERM; \
	GUILE_AUTO_COMPILE=0; export GUILE_AUTO_COMPILE; \
	GUILE_LOAD_COMPILED_PATH="$(abs_top_srcdir)/modules/"; export GUILE_LOAD_COMPILED_PATH;

# LOG_COMPILER was introduced in Automake 1.12; don't expect "make
# check" or "make distcheck" to work with earlier versions.
SCM_LOG_COMPILER = \
	$(GUILE)

AM_SCM_LOG_FLAGS = \
	-L "$(abs_top_srcdir)/modules/" \
	-s

EXTRA_DIST = \
	${SCM_TESTS}

CLEANFILES = \
	web/*.log \
	web/driver/*.log \
	web/proxy/*.log \
	web/proxy/interceptor/*.log

