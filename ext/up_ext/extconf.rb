require 'mkmf'

$CFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL -Wc++17-extensions '
$CPPFLAGS << ' -O3 -Wall -DLIBUS_NO_SSL -Wc++17-extensions '

create_makefile('up_ext')
