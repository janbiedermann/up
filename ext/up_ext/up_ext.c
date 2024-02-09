#include "libusockets.h"
#include "libuwebsockets.h"
#include <ruby.h>
#include <ruby/encoding.h>
#include <unistd.h>

#define USE_SSL 0
#define MAX_HEADER_KEY_BUF 256
#define MAX_HEADER_KEY_LEN 255

static VALUE mUp;
static VALUE mRuby;
static VALUE cServer;
static VALUE cCluster;
static VALUE cStringIO;
static VALUE cLogger;

static ID id_app;
static ID id_call;
static ID id_close;
static ID id_each;
static ID id_host;
static ID id_logger;
static ID id_port;

static rb_encoding *utf8_encoding;
static rb_encoding *binary_encoding;

static VALUE default_input;
static VALUE default_logger;

static VALUE rack_env_template;

static VALUE empty_string;
static VALUE http11;
static VALUE rack_input;
static VALUE rack_logger;

static VALUE HTTP_VERSION;
static VALUE PATH_INFO;
static VALUE QUERY_STRING;
static VALUE REQUEST_METHOD;
static VALUE SCRIPT_NAME;
static VALUE SERVER_NAME;
static VALUE SERVER_PORT;
static VALUE SERVER_PROTOCOL;

#define set_str_val(gl_name, str)                                              \
  rb_gc_register_address(&gl_name);                                            \
  (gl_name) = rb_enc_str_new((str), strlen((str)), binary_encoding);           \
  rb_obj_freeze(gl_name);

#define set_global(global_name) set_str_val((global_name), #global_name)

#define to_upper(c) (((c) >= 'a' && (c) <= 'z') ? ((c) & ~32) : (c))

static inline long ltoa(char *dest, long value) {
  char *ptr = dest, *ptr1 = dest, tmp_char;
  long tmp;

  do {
    tmp = value;
    value /= 10;
    *ptr++ = "0123456789"[(tmp - value * 10)];
  } while (value);

  tmp = ptr - ptr1;
  *ptr-- = '\0';

  while (ptr1 < ptr) {
    tmp_char = *ptr;
    *ptr-- = *ptr1;
    *ptr1++ = tmp_char;
  }
  return tmp;
}

VALUE up_internal_handle_part(RB_BLOCK_CALL_FUNC_ARGLIST(rpart, res)) {
  if (TYPE(rpart) == T_STRING)
    uws_res_write(USE_SSL, (uws_res_t *)res, RSTRING_PTR(rpart),
                  RSTRING_LEN(rpart));
  return Qnil;
}

typedef struct server_s {
  uws_app_t *app;
  VALUE rapp;
  VALUE host;
  VALUE port;
  VALUE logger;
  VALUE env_template;
} server_s;

static void up_internal_req_header_handler(const char *h, size_t h_len,
                                           const char *v, size_t v_len,
                                           void *renv) {
  char header_key[MAX_HEADER_KEY_BUF] = {'H', 'T', 'T', 'P', '_', '\0'};
  if ((h_len + 5) > MAX_HEADER_KEY_LEN)
    h_len = MAX_HEADER_KEY_LEN - 5;

  for (size_t i = 0; i < h_len; ++i) {
    header_key[i + 5] = (h[i] == '-') ? '_' : to_upper(h[i]);
  }

  header_key[h_len + 5] = '\0';
  rb_hash_aset((VALUE)renv,
               rb_enc_str_new(header_key, h_len + 5, binary_encoding),
               rb_enc_str_new(v, v_len, binary_encoding));
}

static void up_server_prepare_env(VALUE renv, uws_req_t *req) {
  // The HTTP request method, such as “GET” or “POST”. This cannot ever be an
  // empty string, and so is always required.
  const char *str;
  size_t len = uws_req_get_method(req, &str);
  char m[20];
  if (len > 19)
    len = 19;
  for (size_t i = 0; i < len; ++i) {
    m[i] = (str[i] == '-') ? '_' : to_upper(str[i]);
  }
  rb_hash_aset(renv, REQUEST_METHOD, rb_enc_str_new(m, len, binary_encoding));

  // The remainder of the request URL’s “path”, designating the virtual
  // “location” of the request’s target within the application.
  len = uws_req_get_url(req, &str);
  rb_hash_aset(renv, PATH_INFO, rb_enc_str_new(str, len, binary_encoding));

  // The portion of the request URL that follows the ?, if any. May be empty,
  // but is always required!
  len = uws_req_get_query(req, NULL, 0, &str);
  if (len > 0)
    rb_hash_aset(renv, QUERY_STRING, rb_enc_str_new(str, len, binary_encoding));

  uws_req_for_each_header(req, up_internal_req_header_handler, (void *)renv);
}

static int up_internal_res_header_handler(VALUE key, VALUE data, VALUE arg) {
  char header_key[MAX_HEADER_KEY_BUF];

  uws_res_t *res = (uws_res_t *)arg;
  int kt = TYPE(key), dt = TYPE(data);
  if (dt == T_NIL || kt == T_NIL)
    return ST_CONTINUE;
  if (dt == T_ARRAY) {
    for (long i = 0, end = RARRAY_LEN(data); i < end; ++i) {
      if (up_internal_res_header_handler(key, rb_ary_entry(data, i), arg) ==
          ST_CONTINUE)
        continue;
      return ST_STOP;
    }
    return ST_CONTINUE;
  }
  if (kt != T_STRING) {
    key = rb_obj_as_string(key);
    if (TYPE(key) != T_STRING)
      return ST_CONTINUE;
  }
  if (dt != T_STRING) {
    data = rb_obj_as_string(data);
    if (TYPE(data) != T_STRING)
      return ST_CONTINUE;
  }
  char *key_s = RSTRING_PTR(key);
  int key_len = RSTRING_LEN(key);
  char *data_s = RSTRING_PTR(data);
  int data_len = RSTRING_LEN(data);

  if (key_len > MAX_HEADER_KEY_LEN)
    key_len = MAX_HEADER_KEY_LEN;

  for (int i = 0; i < key_len; ++i) {
    header_key[i] = tolower(key_s[i]);
  }

  // scan the value for newline (\n) delimiters
  char *pos_s = data_s;
  char *pos_e = data_s + data_len;
  while (pos_s < pos_e) {
    // scanning for newline (\n) delimiters
    char *const start = pos_s;
    pos_s = memchr(pos_s, '\n', pos_e - pos_s);
    if (!pos_s)
      pos_s = pos_e;
    uws_res_write_header(USE_SSL, res, header_key, key_len, start,
                         pos_s - start);
    // move forward (skip the '\n' if exists)
    ++pos_s;
  }

  // no errors, return 0
  return ST_CONTINUE;
  RB_GC_GUARD(key);
  RB_GC_GUARD(data);
}

static void up_server_request_handler(uws_res_t *res, uws_req_t *req,
                                      void *arg) {
  int type;
  long a_long = 0;

  // prepare rack env
  server_s *s = (server_s *)arg;
  VALUE renv = rb_hash_dup(s->env_template);
  up_server_prepare_env(renv, req);

  // call app
  VALUE rres = rb_funcall(s->rapp, id_call, 1, renv);

  if (TYPE(rres) != T_ARRAY)
    goto response_error;

  // response status
  char status[10];
  VALUE rstatus = rb_ary_entry(rres, 0);
  type = TYPE(rstatus);
  if (type == T_FIXNUM) {
    a_long = FIX2INT(rstatus);
    if (a_long < 0 || a_long > 999)
      goto response_error;
    a_long = ltoa(status, a_long);
  } else if (type == T_STRING) {
    a_long = RSTRING_LEN(rstatus);
    if (a_long > 6)
      a_long = 6;
    memcpy(status, RSTRING_PTR(rstatus), a_long);
  } else {
    goto response_error;
  }
  memcpy(status + a_long, " OK", 4); // copy the '\0' too
  uws_res_write_status(USE_SSL, res, status, a_long + 3);

  // collect headers
  VALUE rheaders = rb_ary_entry(rres, 1);
  if (TYPE(rheaders) != T_HASH)
    goto response_error;
  rb_hash_foreach(rheaders, up_internal_res_header_handler, (VALUE)res);

  // collect response body
  VALUE rparts = rb_ary_entry(rres, 2);
  VALUE rpart;
  if (TYPE(rparts) == T_ARRAY) {
    long i, l = RARRAY_LEN(rparts);
    for (i = 0; i < l; i++) {
      rpart = rb_ary_entry(rparts, i);
      if (TYPE(rpart) != T_STRING)
        goto response_error;
      uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
    }
  } else if (rb_respond_to(rparts, id_each)) {
    rb_block_call(rparts, id_each, 0, NULL, up_internal_handle_part,
                  (VALUE)res);
  } else if (rb_respond_to(rparts, id_call)) {
    rpart = rb_funcall(rparts, id_call, 0);
    if (TYPE(rpart) != T_STRING)
      goto response_error;
    uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
  } else {
    goto response_error;
  }

  // end response
  uws_res_end_without_body(USE_SSL, res, false);

  // close resources if necessary
  if (rb_respond_to(rparts, id_close))
    rb_funcall(rparts, id_close, 0);

  return;

  RB_GC_GUARD(rstatus);
  RB_GC_GUARD(rheaders);
  RB_GC_GUARD(rres);
  RB_GC_GUARD(renv);
response_error:
  fprintf(stderr, "response error\n");
  uws_res_end_without_body(USE_SSL, res, false);
  return;
}

static void up_server_listen_handler(struct us_listen_socket_t *listen_socket,
                                     uws_app_listen_config_t config,
                                     void *user_data) {
  if (listen_socket)
    fprintf(stderr, "Server is running on http://%s:%d\n", config.host,
            config.port);
}

static void up_server_t_free(void *p) {
  server_s *s = (server_s *)p;
  rb_gc_unregister_address(&s->host);
  rb_gc_unregister_address(&s->port);
  rb_gc_unregister_address(&s->env_template);
  free(s);
}

const rb_data_type_t up_server_t = {.wrap_struct_name = "Up::Ruby::Server",
                                    .function = {.dmark = NULL,
                                                 .dfree = up_server_t_free,
                                                 .dsize = NULL,
                                                 .dcompact = NULL,
                                                 .reserved = {0}},
                                    .parent = NULL,
                                    .data = NULL,
                                    .flags = RUBY_TYPED_FREE_IMMEDIATELY};

static VALUE up_server_alloc(VALUE rclass) {
  server_s *s = calloc(1, sizeof(server_s));
  if (!s)
    rb_raise(rb_eNoMemError, "unable to allocate server");
  rb_gc_register_address(&s->host);
  rb_gc_register_address(&s->port);
  rb_gc_register_address(&s->env_template);
  return TypedData_Wrap_Struct(rclass, &up_server_t, s);
}

static void up_internal_check_arg_types(VALUE rapp, VALUE *rhost,
                                        VALUE *rport) {
  if (!rb_respond_to(rapp, id_call))
    rb_raise(rb_eArgError, "app does not respond to #call");
  if (*rhost == Qundef || *rhost == Qnil) {
    *rhost = rb_str_new("localhost", 9);
  }
  Check_Type(*rhost, T_STRING);
  if (*rport == Qundef || *rport == Qnil) {
    *rport = INT2FIX(3000);
  }
  Check_Type(*rport, T_FIXNUM);
}

static VALUE up_server_init(int argc, VALUE *argv, VALUE self) {
  if (!rb_keyword_given_p())
    rb_raise(rb_eArgError, "no args given, must at least provide app:");
  ID kwargs[] = {id_app, id_host, id_port, id_logger};
  VALUE rargs[4] = {Qnil, Qnil, Qnil, Qnil};
  VALUE options = Qnil;

  rb_scan_args_kw(1, argc, argv, ":", &options);
  rb_get_kwargs(options, kwargs, 1, 2, rargs);

  VALUE rapp = rargs[0];
  VALUE rhost = rargs[1];
  VALUE rport = rargs[2];

  up_internal_check_arg_types(rapp, &rhost, &rport);

  server_s *s = DATA_PTR(self);
  s->rapp = rapp;
  s->host = rb_obj_freeze(rhost);
  s->port = rport;
  s->logger = rargs[3];

  return self;
}

static void up_server_run(server_s *s) {
  s->env_template = rb_hash_dup(rack_env_template);
  // When combined with SCRIPT_NAME and PATH_INFO, these variables can be used
  // to complete the URL.
  rb_hash_aset(s->env_template, SERVER_NAME, s->host);
  // An optional Integer which is the port the server is running on.
  rb_hash_aset(s->env_template, SERVER_PORT, s->port);
  if (s->logger && s->logger != Qundef && s->logger != Qnil) {
    rb_hash_aset(s->env_template, rack_logger, s->logger);
  }
  struct us_socket_context_options_t options = {.key_file_name = NULL,
                                                .cert_file_name = NULL,
                                                .ca_file_name = NULL,
                                                .passphrase = NULL,
                                                .dh_params_file_name = NULL,
                                                .ssl_ciphers = NULL};
  s->app = uws_create_app(USE_SSL, options);
  if (!s->app)
    rb_raise(rb_eRuntimeError, "could not init uws app");
  uws_app_any(USE_SSL, s->app, "/*", up_server_request_handler, (void *)s);
  uws_app_listen_config_t config = {
      .port = FIX2INT(s->port), .host = RSTRING_PTR(s->host), .options = 0};
  uws_app_listen_with_config(USE_SSL, s->app, config, up_server_listen_handler,
                             NULL);
  uws_app_run(USE_SSL, s->app);
}

static VALUE up_server_listen(VALUE self) {
  server_s *s = DATA_PTR(self);

  up_server_run(s);

  return Qnil;
}

static VALUE up_server_stop(VALUE self) {
  server_s *s = DATA_PTR(self);
  if (!s->app)
    rb_raise(rb_eRuntimeError, "no uws, did initialize call super?");
  uws_app_close(USE_SSL, s->app);
  uws_app_destroy(USE_SSL, s->app);
  s->app = NULL;
  return Qnil;
}

static VALUE up_cluster_listen(VALUE self) {
  server_s *s = DATA_PTR(self);

  up_internal_check_arg_types(s->rapp, &s->host, &s->port);

  long i = sysconf(_SC_NPROCESSORS_ONLN);
  pid_t pid = 0;
  for (; i > 1; i--) {
    pid = fork();
    if (pid > 0) {
      // do nothing
    } else if (pid == 0) {
      up_server_run(s);
    }
  }
  if (pid > 0)
    up_server_run(s);

  return Qnil;
}

static VALUE up_cluster_stop(VALUE self) {
  // uws_app_t *app = DATA_PTR(self);
  // uws_app_close(USE_SSL, app);
  return Qnil;
}

void up_hash_set(VALUE rhash, const char *key, VALUE val) {
  rb_hash_aset(rhash, rb_enc_str_new(key, strlen(key), binary_encoding), val);
}

void up_setup_rack_env_template(void) {
  rb_gc_register_address(&rack_env_template);
  rack_env_template = rb_hash_new();

  // error stream
  up_hash_set(rack_env_template, "rack.errors", rb_stderr);

  // if present, an object responding to call that is used to perform a full
  // hijack. up_hash_set(rack_env_template, "rack.hijack", Qnil);

  // if present and true, indicates that the server supports partial hijacking
  // up_hash_set(rack_env_template, "rack.hijack?", Qfalse);

  // The input stream is an IO-like object which contains the raw HTTP POST data
  rb_hash_aset(rack_env_template, rack_input, default_input);

  // A common object interface for logging messages
  up_hash_set(rack_env_template, "rack.logger", default_logger);

  // An Integer hint to the multipart parser as to what chunk size to use for
  // reads and writes.
  up_hash_set(rack_env_template, "rack.multipart.buffer_size", INT2FIX(4096));

  // An object responding to #call with two arguments, the filename and
  // content_type given for the multipart form field, and returning an IO-like
  // object that responds to #<< and optionally #rewind.
  // up_hash_set(rack_env_template, "rack.multipart.tempfile_factory", Qnil);

  // An array of callables run by the server after the response has been
  // processed.
  // up_hash_set(rack_env_template, "rack.response_finished", Qnil);

  // A hash-like interface for storing request session data.
  // up_hash_set(rack_env_template, "rack.session", Qnil);

  // http or https, depending on the request URL.
  up_hash_set(rack_env_template, "rack.url_scheme",
              rb_enc_str_new_cstr("http", binary_encoding));

  // The portion of the request URL that follows the ?, if any. May be empty,
  // but is always required!
  rb_hash_aset(rack_env_template, QUERY_STRING, empty_string);

  // The initial portion of the request URL’s “path” that corresponds to the
  // application object, so that the application knows its virtual “location”.
  // This may be an empty string, if the application corresponds to the “root”
  // of the server.
  rb_hash_aset(rack_env_template, SCRIPT_NAME, empty_string);

  // A string representing the HTTP version used for the request.
  // Note: uws has no way to get that information from the request
  // so set it to a static value
  rb_hash_aset(rack_env_template, SERVER_PROTOCOL, http11);
  rb_hash_aset(rack_env_template, HTTP_VERSION, http11);
}

void Init_up_ext(void) {
  id_app = rb_intern("app");
  id_call = rb_intern("call");
  id_close = rb_intern("close");
  id_each = rb_intern("each");
  id_host = rb_intern("host");
  id_logger = rb_intern("logger");
  id_port = rb_intern("port");

  utf8_encoding = rb_enc_find("UTF-8");
  binary_encoding = rb_enc_find("binary");

  set_str_val(empty_string, "");
  set_str_val(http11, "HTTP/1.1");
  set_str_val(rack_input, "rack.input");
  set_str_val(rack_logger, "rack.logger");
  set_global(HTTP_VERSION);
  set_global(PATH_INFO);
  set_global(QUERY_STRING);
  set_global(REQUEST_METHOD);
  set_global(SCRIPT_NAME);
  set_global(SERVER_NAME);
  set_global(SERVER_PORT);
  set_global(SERVER_PROTOCOL);

  rb_require("logger");

  rb_gc_register_address(&cLogger);
  cLogger = rb_const_get(rb_cObject, rb_intern("Logger"));
  rb_gc_register_address(&default_logger);
  default_logger = rb_funcall(cLogger, rb_intern("new"), 1, rb_stderr);

  rb_require("stringio");

  rb_gc_register_address(&cStringIO);
  cStringIO = rb_const_get(rb_cObject, rb_intern("StringIO"));
  rb_gc_register_address(&default_input);
  default_input = rb_funcall(cStringIO, rb_intern("new"), 1, empty_string);

  up_setup_rack_env_template();

  mUp = rb_define_module("Up");
  mRuby = rb_define_module_under(mUp, "Ruby");

  cServer = rb_define_class_under(mRuby, "Server", rb_cObject);
  rb_define_alloc_func(cServer, up_server_alloc);
  rb_define_method(cServer, "initialize", up_server_init, -1);
  rb_define_method(cServer, "listen", up_server_listen, 0);
  rb_define_method(cServer, "stop", up_server_stop, 0);

  cCluster = rb_define_class_under(mRuby, "Cluster", cServer);
  rb_define_method(cCluster, "listen", up_cluster_listen, 0);
  rb_define_method(cCluster, "stop", up_cluster_stop, 0);
}
