require 'mkmf'

$CFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL '
$CPPFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL -Wc++17-extensions '

if RUBY_PLATFORM =~ /mingw/
  $CFLAGS << '-IC:/ruby34-x64/msys64/usr/include '
  $CPPFLAGS << '-IC:/ruby34-x64/msys64/usr/include '
  $LDFLAGS << ' -luv -lz '
end

create_makefile('up_ext')
