require 'mkmf'

$CFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL '
$CPPFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL -Wc++17-extensions '

$LDFLAGS << ' -luv -lz ' if RUBY_PLATFORM =~ /mingw/

create_makefile('up_ext')
