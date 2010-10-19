
#
#
# New 
#
#

#config
WANT_OPENSSL=1
PREFIX=/usr

platform := $(shell python -c 'import sys; print sys.platform')

# fix me
arch = x86


ifdef WANT_OPENSSL
	HAVE_OPENSSL = 1
	HAVE_CRYPTO = 1
	ifdef OPENSSL_DIR
		OPENSSL_LINKFLAGS += -L$(OPENSSL_DIR)/lib
		OPENSSL_CPPFLAGS += -I$(OPENSSL_DIR)/include
	endif
	OPENSSL_LINKFLAGS += -lssl -lcrypto
endif

cflags += -pedantic




# PROFILES
# Default profile is debug 'make PROFILE=release' for a release.
PROFILE ?= debug

debug_CFLAGS = -Wall -O0 -ggdb
debug_CPPDEFINES = -DDEBUG
debug_builddir = build/debug

release_CFLAGS = -Wall -O2
release_CPPDEFINES = -DNODEBUG
release_builddir = build/release

CPPFLAGS  += $($(PROFILE)_CPPFLAGS)
CFLAGS    += $($(PROFILE)_CFLAGS)
LINKFLAGS += $($(PROFILE)_LINKFLAGS)
builddir   = $($(PROFILE)_builddir)




libev_sources = deps/libev/ev.c
libev_objects = $(builddir)/deps/libev/ev.o
libev_CPPFLAGS = -Ideps/libev -Ideps/libev/$(platform)/

libeio_sources = deps/libeio/eio.c
libeio_objects = $(builddir)/deps/libeio/eio.o
libeio_CPPFLAGS = -Ideps/libeio -Ideps/libeio/$(platform)/

http_parser_sources = deps/http_parser/ev.c
http_parser_objects = $(builddir)/deps/http_parser/ev.o
http_parser_CPPFLAGS = -Ideps/http_parser

cares_sources = $(wildcard deps/c-ares/*.c)
cares_objects = $(addprefix $(builddir)/,$(cares_sources:.c=.o))
cares_CPPFLAGS = -Ideps/c-ares -Ideps/c-ares/$(platform)-$(arch)/

node_sources = src/node.cc \
	src/platform_$(platform).cc \
	src/node_buffer.cc \
	src/node_cares.cc \
	src/node_child_process.cc \
	src/node_constants.cc \
	src/node_crypto.cc \
	src/node_events.cc \
	src/node_extensions.cc \
	src/node_file.cc \
	src/node_http_parser.cc \
	src/node_idle_watcher.cc \
	src/node_io_watcher.cc \
	src/node_main.cc \
	src/node_net.cc \
	src/node_script.cc \
	src/node_signal_watcher.cc \
	src/node_stat_watcher.cc \
	src/node_stdio.cc \
	src/node_timer.cc
node_objects = $(addprefix $(builddir)/,$(node_sources:.cc=.o))
node_CPPFLAGS = -Isrc/ -Ideps/libeio/ -Ideps/libev/ -Ideps/http_parser/ \
	-Ideps/libev/include/ -Ideps/v8/include -DPLATFORM=\"$(platform)\" \
	$(cares_CPPFLAGS)

dirs = $(builddir)/src \
	$(builddir)/deps/libev \
	$(builddir)/deps/libeio \
	$(builddir)/deps/c-ares \
	$(builddir)/deps/http_parser \
	$(builddir)/deps/v8


# Rules

all: $(builddir)/node $(dirs)

$(dirs):
	mkdir -p $@

$(builddir)/deps/libev/%.o: deps/libev/%.c 
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(libev_CFLAGS) $(libev_CPPFLAGS) $< -o $@

$(builddir)/deps/libeio/%.o: deps/libeio/%.c 
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(libeio_CFLAGS) $(libeio_CPPFLAGS) $< -o $@

$(builddir)/deps/http_parser/%.o: deps/http_parser/%.c 
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(http_parser_CFLAGS) \
		$(http_parser_CPPFLAGS) $< -o $@

$(builddir)/deps/c-ares/%.o: deps/c-ares/%.c 
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(cares_CFLAGS) $(cares_CPPFLAGS) $< -o $@

$(builddir)/src/%.o: src/%.cc
	$(CXX) -c $(CXXFLAGS) $(CPPFLAGS) $(node_CFLAGS) $(node_CPPFLAGS) \
		$(OPENSSL_CPPFLAGS) $< -o $@

$(builddir)/src/node.o: src/node.cc $(builddir)/src/node_natives.h
	$(CXX) -c $(CXXFLAGS) $(CPPFLAGS) $(node_CFLAGS) $(node_CPPFLAGS) \
		$(OPENSSL_CPPFLAGS) -I$(builddir)/src/ $< -o $@

$(builddir)/node: $(node_objects) $(libev_objects) $(libeio_objects) \
		$(http_parser_objects) $(cares_objects)
	$(CXX) -o $@ $^ $(LINKFLAGS) $(node_LINKFLAGS) $(OPENSSL_LINKFLAGS)

$(builddir)/src/node_natives.h: src/node.js lib/*.js
	python tools/js2c.py $^ > $@
	# TODO a debug flag for the macros ?

$(builddir)/src/node_config.h: src/node_config.h.in
	sed -e "s#@PREFIX@#$(PREFIX)#" \
		-e "s#@CCFLAGS@#$(CFLAGS)#" \
		-e "s#@CPPFLAGS@#$(CPPFLAGS)#" $< > $@ || rm $@

# header deps
src/node_version.h: $(builddir)/src/node_config.h
src/node.cc: $(builddir)/src/node_config.h


#
#
# OLD
#
#



WAF=python tools/waf-light

all-progress:
	@$(WAF) -p build

install:
	@$(WAF) install

uninstall:
	@$(WAF) uninstall

test: all
	python tools/test.py --mode=release simple message

test-all: all
	python tools/test.py --mode=debug,release

test-release: all
	python tools/test.py --mode=release

test-debug: all
	python tools/test.py --mode=debug

test-message: all
	python tools/test.py message

test-simple: all
	python tools/test.py simple
     
test-pummel: all
	python tools/test.py pummel
	
test-internet: all
	python tools/test.py internet

# http://rtomayko.github.com/ronn
# gem install ronn
doc: doc/node.1 doc/api.html doc/index.html doc/changelog.html

## HACK to give the ronn-generated page a TOC
doc/api.html: all doc/api.markdown doc/api_header.html doc/api_footer.html
	build/default/node tools/ronnjs/bin/ronn.js --fragment doc/api.markdown \
	| sed "s/<h2>\(.*\)<\/h2>/<h2 id=\"\1\">\1<\/h2>/g" \
	| cat doc/api_header.html - doc/api_footer.html > doc/api.html

doc/changelog.html: ChangeLog doc/changelog_header.html doc/changelog_footer.html
	cat doc/changelog_header.html ChangeLog doc/changelog_footer.html > doc/changelog.html

doc/node.1: doc/api.markdown all
	build/default/node tools/ronnjs/bin/ronn.js --roff doc/api.markdown > doc/node.1

website-upload: doc
	scp doc/* ryan@nodejs.org:~/web/nodejs.org/

docclean:
	@-rm -f doc/node.1 doc/api.html doc/changelog.html

clean:
	@$(WAF) clean
	@-find tools -name "*.pyc" | xargs rm -f

distclean: docclean
	@-find tools -name "*.pyc" | xargs rm -f
	@-rm -rf build/ node node_g

check:
	@tools/waf-light check

VERSION=$(shell git describe)
TARNAME=node-$(VERSION)

dist: doc/node.1 doc/api.html
	git archive --format=tar --prefix=$(TARNAME)/ HEAD | tar xf -
	mkdir -p $(TARNAME)/doc
	cp doc/node.1 $(TARNAME)/doc/node.1
	cp doc/api.html $(TARNAME)/doc/api.html
	rm -rf $(TARNAME)/deps/v8/test # too big
	tar -cf $(TARNAME).tar $(TARNAME)
	rm -rf $(TARNAME)
	gzip -f -9 $(TARNAME).tar

bench:
	 benchmark/http_simple_bench.sh

bench-idle:
	./node benchmark/idle_server.js &
	sleep 1
	./node benchmark/idle_clients.js &


.PHONY: bench clean docclean dist distclean check uninstall install all test test-all website-upload
