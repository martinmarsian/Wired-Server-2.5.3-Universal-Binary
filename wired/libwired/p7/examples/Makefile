# Makefile.in

abs_top_srcdir	= /Users/maertin/Documents/WiredServer/wired/libwired
rundir			= ../..//tmp/wsbuild_2151/arm64/run/wired/libwired

DEFS			= -DHAVE_CONFIG_H
CC				= /usr/bin/clang -arch arm64
CFLAGS			= -O0 -arch arm64 -W -Wall -Wno-unknown-pragmas -Wno-unused-parameter -Wsign-compare -Wstrict-prototypes -Wmissing-prototypes -Wmissing-declarations -Wredundant-decls -Wno-long-double
CPPFLAGS		= -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk -mmacosx-version-min=10.13 -I/Users/maertin/Documents/WiredServer/Pods/OpenSSL-Universal/include-macos -arch arm64 -I/tmp/wsbuild_2151/arm64/make/libwired -I/usr/local/include -DWI_CORESERVICES -DWI_CARBON -DWI_DIGESTS -DWI_CIPHERS -DWI_PTHREADS -DWI_LIBXML2 -DWI_PLIST -DWI_SQLITE3 -DWI_RSA -DWI_ZLIB -DWI_P7
LDFLAGS			= -L$(rundir)/lib -L/Users/maertin/Documents/WiredServer/Pods/OpenSSL-Universal/lib-macos -L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/usr/lib -L/usr/local/lib
LIBS			= -lwired -lcrypto -lssl -framework CoreServices -framework Carbon -lxml2 -lsqlite3 -lz
INCLUDES		= -I$(abs_top_srcdir) -I$(rundir)/include

COMPILEANDLINK	= $(CC) $(DEFS) $(INCLUDES) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@

wiredclient: wiredclient.c
	$(COMPILEANDLINK) $(LIBS) $<
