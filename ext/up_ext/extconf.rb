require 'mkmf'

$CFLAGS << ' -flto -fPIC -O3 -Wall -DLIBUS_NO_SSL '

create_makefile('up_ext')
