#include "libusockets.h"
#include "libuwebsockets.h"
#include <arpa/inet.h>
#include <ruby.h>
#include <ruby/encoding.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define USE_SSL 0
#define MAX_HEADER_KEY_BUF 256
#define MAX_HEADER_KEY_LEN 255
#define INTERNAL_PUBLISH_PATH "/__up__cluster__publish__"

static VALUE mUp;
static VALUE mRuby;
static VALUE cServer;
static VALUE cClient;
static VALUE cStringIO;
static VALUE cLogger;

static ID at_env;
static ID at_handler;
static ID at_instance;
static ID at_member_id;
static ID at_members;
static ID at_open;
static ID at_port;
static ID at_protocol;
static ID at_secret;
static ID at_server;
static ID at_timeout;
static ID at_workers;
static ID id_app;
static ID id_call;
static ID id_close;
static ID id_each;
static ID id_host;
static ID id_logger;
static ID id_new;
static ID id_on_close;
static ID id_on_drained;
static ID id_on_message;
static ID id_on_open;
static ID id_port;
static ID id_publish;

static rb_encoding *utf8_encoding;
static rb_encoding *binary_encoding;

static VALUE default_input;
static VALUE default_logger;

static VALUE rack_env_template;

static VALUE empty_string;
static VALUE http11;
static VALUE rack_input;
static VALUE rack_logger;
static VALUE rack_upgrade_q;
static VALUE rack_upgrade;
static VALUE sym_websocket;

static VALUE HTTP_VERSION;
static VALUE PATH_INFO;
static VALUE QUERY_STRING;
static VALUE REQUEST_METHOD;
static VALUE SCRIPT_NAME;
static VALUE SERVER_NAME;
static VALUE SERVER_PORT;
static VALUE SERVER_PROTOCOL;

// both used when worker of a cluster
uws_app_t *cluster_app;
struct us_listen_socket_t *cluster_socket;

#define set_str_val(gl_name, str)                                              \
  rb_gc_register_address(&gl_name);                                            \
  (gl_name) = rb_enc_str_new((str), strlen((str)), binary_encoding);           \
  rb_obj_freeze(gl_name);

#define set_sym_val(gl_name, str)                                              \
  rb_gc_register_address(&gl_name);                                            \
  (gl_name) = ID2SYM(rb_intern(str));

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
  VALUE self;
  uws_app_t *app;
  VALUE rapp;
  VALUE host;
  VALUE port;
  VALUE logger;
  VALUE env_template;
  VALUE body;
  VALUE env;
  int workers;
  int member_id;
  char secret[37];
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
  if (header_key[5] == 'C' &&
      ((strncmp(header_key + 5, "CONTENT_TYPE", 12) == 0) ||
       (strncmp(header_key + 5, "CONTENT_LENGTH", 14) == 0))) {
    rb_hash_aset((VALUE)renv,
                 rb_enc_str_new(header_key + 5, h_len, binary_encoding),
                 rb_enc_str_new(v, v_len, binary_encoding));
  } else {
    rb_hash_aset((VALUE)renv,
                 rb_enc_str_new(header_key, h_len + 5, binary_encoding),
                 rb_enc_str_new(v, v_len, binary_encoding));
  }
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

static bool up_internal_set_response_status(uws_res_t *res, VALUE rstatus) {
  char status[10];
  int type = TYPE(rstatus);
  long a_long;
  if (type == T_FIXNUM) {
    a_long = FIX2INT(rstatus);
    if (a_long < 0 || a_long > 999)
      return false;
    a_long = ltoa(status, a_long);
  } else if (type == T_STRING) {
    a_long = RSTRING_LEN(rstatus);
    if (a_long > 6)
      a_long = 6;
    memcpy(status, RSTRING_PTR(rstatus), a_long);
  } else {
    return false;
  }
  memcpy(status + a_long, " OK", 4); // copy the '\0' too
  uws_res_write_status(USE_SSL, res, status, a_long + 3);
  return true;
}

static bool up_internal_collect_response_body(uws_res_t *res, VALUE rparts) {
  VALUE rpart;
  if (TYPE(rparts) == T_ARRAY) {
    long i, l = RARRAY_LEN(rparts);
    for (i = 0; i < l; i++) {
      rpart = rb_ary_entry(rparts, i);
      if (TYPE(rpart) != T_STRING)
        return false;
      uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
    }
  } else if (rb_respond_to(rparts, id_each)) {
    rb_block_call(rparts, id_each, 0, NULL, up_internal_handle_part,
                  (VALUE)res);
  } else if (rb_respond_to(rparts, id_call)) {
    rpart = rb_funcall(rparts, id_call, 0);
    if (TYPE(rpart) != T_STRING)
      return false;
    uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
  } else {
    return false;
  }
  return true;
}

typedef struct publish_data_s {
  int pos;
  const char *data[2];
  size_t lengths[2];
  server_s *s;
} publish_data_s;

static void up_internal_call_app(server_s *s, uws_res_t *res, VALUE env) {
  // call app
  VALUE rres = rb_funcall(s->rapp, id_call, 1, env);

  if (TYPE(rres) != T_ARRAY)
    goto response_error;

  // response status
  VALUE rstatus = rb_ary_entry(rres, 0);
  if (!up_internal_set_response_status(res, rstatus))
    goto response_error;

  // collect headers
  VALUE rheaders = rb_ary_entry(rres, 1);
  if (TYPE(rheaders) != T_HASH)
    goto response_error;
  rb_hash_foreach(rheaders, up_internal_res_header_handler, (VALUE)res);

  // collect response body
  VALUE rparts = rb_ary_entry(rres, 2);
  up_internal_collect_response_body(res, rparts);

  // end response
  uws_res_end_without_body(USE_SSL, res, false);

  // close resources if necessary
  if (rb_respond_to(rparts, id_close))
    rb_funcall(rparts, id_close, 0);

  return;
response_error:
  fprintf(stderr, "response error\n");
  uws_res_end_without_body(USE_SSL, res, false);
}

static void up_internal_abort_data(uws_res_t *res, void *arg) {}

static void up_internal_process_publish_post_data(uws_res_t *res,
                                                  const char *chunk,
                                                  size_t chunk_length,
                                                  bool is_end, void *arg) {
  server_s *s = (server_s *)arg;
  const char *channel_start = chunk, *chunk_ptr = chunk,
             *chunk_end = chunk + chunk_length, *message_start = NULL;
  size_t channel_length = 0, message_length = 0;
  for (; chunk_ptr < chunk_end; chunk_ptr++) {
    if (*chunk_ptr == '\r') {
      channel_length = chunk_ptr - chunk;
      message_start = chunk + channel_length + 2;
      message_length = chunk_length - 2 - channel_length;
      break;
    }
  }
  if (channel_length > 0 && message_length > 0)
    uws_publish(USE_SSL, s->app, channel_start, channel_length, message_start,
                message_length, TEXT, false);
}

static void up_internal_process_post_data(uws_res_t *res, const char *chunk,
                                          size_t chunk_length, bool is_end,
                                          void *arg) {
  server_s *s = (server_s *)arg;
  rb_str_cat(s->body, chunk, chunk_length);
  if (is_end) {
    // set rack.input
    rb_hash_aset(s->env, rack_input, rb_funcall(cStringIO, id_new, 1, s->body));
    up_internal_call_app(s, res, s->env);
    s->body = Qnil;
    s->env = Qnil;
  }
}

static void up_internal_publish_handler(uws_res_t *res, uws_req_t *req,
                                        void *arg) {
  server_s *s = (server_s *)arg;
  // check for header
  const char *secret;
  uws_req_get_header(req, "secret", 6, &secret);
  if (secret && (strncmp(s->secret, secret, 36) == 0)) {
    // ok, requests origin knows the secret, continue processing
    uws_res_on_data(false, res, up_internal_process_publish_post_data, arg);
    uws_res_write_status(false, res, "200 OK", 6);
    uws_res_end_without_body(false, res, true);
  } else {
    // don't know the secret? bugger off!
    uws_res_end_without_body(false, res, true);
  }
}

static void up_server_any_handler(uws_res_t *res, uws_req_t *req, void *arg) {
  // prepare rack env
  server_s *s = (server_s *)arg;
  VALUE env = rb_hash_dup(s->env_template);
  up_server_prepare_env(env, req);
  up_internal_call_app(s, res, env);
  RB_GC_GUARD(env);
}

static void up_server_post_handler(uws_res_t *res, uws_req_t *req, void *arg) {
  // prepare rack env
  server_s *s = (server_s *)arg;
  s->env = rb_hash_dup(s->env_template);
  up_server_prepare_env(s->env, req);

  // receive POST data
  s->body = rb_enc_str_new("", 0, utf8_encoding);
  uws_res_on_data(USE_SSL, res, up_internal_process_post_data, (void *)s);
  uws_res_on_aborted(USE_SSL, res, up_internal_abort_data, NULL);
}

static void
up_server_cluster_listen_handler(struct us_listen_socket_t *listen_socket,
                                 uws_app_listen_config_t config, void *arg) {
  if (listen_socket) {
    cluster_socket = listen_socket;
    fprintf(stderr, "Internal Cluster communication on http://localhost:%d\n",
            config.port);
  }
}

static void up_server_listen_handler(struct us_listen_socket_t *listen_socket,
                                     uws_app_listen_config_t config,
                                     void *arg) {
  if (listen_socket) {
    fprintf(stderr, "Server is listening on http://%s:%d\n", config.host,
            config.port);
  }
}

const rb_data_type_t up_client_t = {.wrap_struct_name = "Up::Client",
                                    .function = {.dmark = NULL,
                                                 .dfree = NULL,
                                                 .dsize = NULL,
                                                 .dcompact = NULL,
                                                 .reserved = {0}},
                                    .parent = NULL,
                                    .data = NULL,
                                    .flags = 0};

static VALUE up_client_alloc(VALUE rclass) {
  return TypedData_Wrap_Struct(rclass, &up_client_t, NULL);
}

static VALUE up_client_close(VALUE self) {
  uws_websocket_t *ws = DATA_PTR(self);
  rb_ivar_set(self, at_open, Qfalse);
  if (ws)
    uws_ws_close(USE_SSL, ws);
  return Qnil;
}

static VALUE up_client_pending(VALUE self) {
  uws_websocket_t *ws = DATA_PTR(self);
  if (ws)
    return INT2FIX(uws_ws_get_buffered_amount(USE_SSL, ws));
  return INT2FIX(0);
}

static void up_client_cluster_publish(char *scrt, int st, VALUE channel,
                                      VALUE message) {
  const char *opening_line = "POST " INTERNAL_PUBLISH_PATH " HTTP/1.1\r\n";
  const char *host_header = "Host: localhost\r\n";
  const char *secret = "Secret: ";
  char secret_header[50];
  memcpy(secret_header, secret, 8);
  memcpy(secret_header + 8, scrt, 36);
  memcpy(secret_header + 8 + 36, "\r\n", 2);
  const char *content_type = "Content-Type: text/plain\r\n";
  long c_length = RSTRING_LEN(channel) + RSTRING_LEN(message) + 2;
  char content_length[50];
  memcpy(content_length, "Content-Length: ", 16);
  long cl = ltoa(content_length + 16, c_length);
  memcpy(content_length + 16 + cl, "\r\n\r\n", 4);
  const char *boundary_disposition = "\r\n";

  send(st, opening_line, strlen(opening_line), MSG_DONTROUTE | MSG_MORE);
  send(st, host_header, strlen(host_header), MSG_DONTROUTE | MSG_MORE);
  send(st, secret_header, 46, MSG_DONTROUTE | MSG_MORE);
  send(st, content_type, strlen(content_type), MSG_DONTROUTE | MSG_MORE);
  send(st, content_length, strlen(content_length), MSG_DONTROUTE | MSG_MORE);
  send(st, RSTRING_PTR(channel), RSTRING_LEN(channel),
       MSG_DONTROUTE | MSG_MORE);
  send(st, boundary_disposition, strlen(boundary_disposition),
       MSG_DONTROUTE | MSG_MORE);
  send(st, RSTRING_PTR(message), RSTRING_LEN(message),
       MSG_DONTROUTE | MSG_MORE);

  // char read_buf[256];
  // if (read(st, read_buf, 256)) {
  //   // do nothing
  // };
  // fprintf(stderr, "read: %s\n", read_buf);
}

static void up_internal_publish_to_member(server_s *s, VALUE channel,
                                          VALUE message, int member_idx) {
  struct sockaddr_in member_addr = {.sin_addr.s_addr = inet_addr("127.0.0.1"),
                                    .sin_family = AF_INET};
  int st = socket(AF_INET, SOCK_STREAM, 0);
  if (st) {
    member_addr.sin_port = htons(FIX2INT(s->port) + member_idx);
    if (connect(st, (struct sockaddr *)&member_addr,
                sizeof(struct sockaddr_in)) == 0) {
      up_client_cluster_publish(s->secret, st, channel, message);
      close(st);
    }
  }
}

static VALUE up_client_publish(VALUE self, VALUE channel, VALUE message) {
  uws_websocket_t *ws = DATA_PTR(self);
  if (!ws)
    return Qnil;
  if (TYPE(channel) != T_STRING)
    channel = rb_obj_as_string(channel);
  if (TYPE(message) != T_STRING)
    message = rb_obj_as_string(message);
  VALUE server = rb_ivar_get(self, at_server);
  if (server != Qnil) {
    server_s *s = DATA_PTR(server);
    int res =
        uws_publish(USE_SSL, s->app, RSTRING_PTR(channel), RSTRING_LEN(channel),
                    RSTRING_PTR(message), RSTRING_LEN(message), TEXT, false);
    if (s->member_id > 0) {

      // publish to cluster members
      int i;
      for (i = 1; i <= s->workers; i++) {
        if (i != s->member_id)
          up_internal_publish_to_member(s, channel, message, i);
      }
    }
    return res ? Qtrue : Qfalse;
  }
  return Qfalse;
}

static VALUE up_client_subscribe(int argc, VALUE *argv, VALUE self) {
  uws_websocket_t *ws = DATA_PTR(self);
  if (!ws)
    return Qnil;
  VALUE channel, is_pattern;
  rb_scan_args(argc, argv, "11", &channel, &is_pattern);
  if (TYPE(channel) != T_STRING)
    channel = rb_obj_as_string(channel);
  return uws_ws_subscribe(USE_SSL, ws, RSTRING_PTR(channel),
                          RSTRING_LEN(channel))
             ? Qtrue
             : Qnil;
}

static VALUE up_client_write(VALUE self, VALUE rdata) {
  uws_websocket_t *ws = DATA_PTR(self);
  if (!ws)
    rb_raise(rb_eStandardError, "socket closed, can't write");
  if (TYPE(rdata) != T_STRING)
    rdata = rb_obj_as_string(rdata);
  if (TYPE(rdata) != T_STRING)
    rb_raise(rb_eTypeError,
             "rdata not a string or cannot be converted to a string");
  int opcode = rb_enc_get(rdata) == binary_encoding ? BINARY : TEXT;
  return INT2FIX(
      uws_ws_send(USE_SSL, ws, RSTRING_PTR(rdata), RSTRING_LEN(rdata), opcode));
}

static VALUE up_client_unsubscribe(int argc, VALUE *argv, VALUE self) {
  uws_websocket_t *ws = DATA_PTR(self);
  if (!ws)
    return Qnil;
  VALUE channel, is_pattern;
  rb_scan_args(argc, argv, "11", &channel, &is_pattern);
  if (TYPE(channel) != T_STRING)
    channel = rb_obj_as_string(channel);
  return uws_ws_unsubscribe(USE_SSL, ws, RSTRING_PTR(channel),
                            RSTRING_LEN(channel))
             ? Qtrue
             : Qnil;
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
  return s->self = TypedData_Wrap_Struct(rclass, &up_server_t, s);
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

  rb_ivar_set(self, at_port, s->port);

  return self;
}

void up_ws_drain_handler(uws_websocket_t *ws, void *user_data) {
  VALUE *client = (VALUE *)uws_ws_get_user_data(USE_SSL, ws);
  DATA_PTR(*client) = ws;
  VALUE rhandler = rb_ivar_get(*client, at_handler);
  if (rb_respond_to(rhandler, id_on_drained))
    rb_funcall(rhandler, id_on_drained, 1, *client);
  DATA_PTR(*client) = NULL;
}

void up_ws_ping_handler(uws_websocket_t *ws, const char *message, size_t length,
                        void *user_data) {
  /* You don't need to handle this one, we automatically respond to pings as
   * per standard */
}

void up_ws_pong_handler(uws_websocket_t *ws, const char *message, size_t length,
                        void *user_data) {
  /* You don't need to handle this one either */
}

static void up_ws_close_handler(uws_websocket_t *ws, int code,
                                const char *message, size_t length,
                                void *user_data) {
  VALUE *client = (VALUE *)uws_ws_get_user_data(USE_SSL, ws);
  rb_ivar_set(*client, at_open, Qfalse);
  DATA_PTR(*client) = ws;
  VALUE rhandler = rb_ivar_get(*client, at_handler);
  if (rb_respond_to(rhandler, id_on_close))
    rb_funcall(rhandler, id_on_close, 1, *client);
  // rb_gc_unregister_address(client);
  DATA_PTR(*client) = NULL;
  free(client);
}

static void up_ws_message_handler(uws_websocket_t *ws, const char *message,
                                  size_t length, uws_opcode_t opcode,
                                  void *user_data) {
  VALUE rmessage;
  if (opcode == TEXT) {
    rmessage = rb_enc_str_new(message, length, utf8_encoding);
  } else if (opcode == BINARY) {
    rmessage = rb_enc_str_new(message, length, binary_encoding);
  } else {
    return;
  }
  VALUE *client = (VALUE *)uws_ws_get_user_data(USE_SSL, ws);
  DATA_PTR(*client) = ws;
  VALUE rhandler = rb_ivar_get(*client, at_handler);
  if (rb_respond_to(rhandler, id_on_message))
    rb_funcall(rhandler, id_on_message, 2, *client, rmessage);
  DATA_PTR(*client) = NULL;
}

static void up_ws_open_handler(uws_websocket_t *ws, void *user_data) {
  VALUE *client = (VALUE *)uws_ws_get_user_data(USE_SSL, ws);
  rb_ivar_set(*client, at_open, Qtrue);
  DATA_PTR(*client) = ws;
  VALUE rhandler = rb_ivar_get(*client, at_handler);
  if (rb_respond_to(rhandler, id_on_open))
    rb_funcall(rhandler, id_on_open, 1, *client);
  DATA_PTR(*client) = NULL;
}

static void up_ws_upgrade_handler(uws_res_t *res, uws_req_t *req,
                                  uws_socket_context_t *context, void *arg) {
  server_s *s = (server_s *)arg;
  // prepare rack env
  VALUE renv = rb_hash_dup(s->env_template);
  up_server_prepare_env(renv, req);
  rb_hash_aset(renv, rack_upgrade_q, sym_websocket);

  // call app
  VALUE rres = rb_funcall(s->rapp, id_call, 1, renv);

  if (TYPE(rres) != T_ARRAY)
    goto upgrade_error;

  // response status
  VALUE rstatus = rb_ary_entry(rres, 0);
  int st = FIX2INT(rstatus);

  VALUE rhandler = rb_hash_lookup2(renv, rack_upgrade, Qundef);
  if (st >= 0 && st < 300 && rhandler != Qundef && rhandler != Qnil) {
    // upgrade

    VALUE *client = malloc(sizeof(VALUE));
    // rb_gc_register_address(client);
    *client = rb_class_new_instance(0, NULL, cClient);
    rb_ivar_set(*client, at_env, renv);
    rb_ivar_set(*client, at_open, false);
    rb_ivar_set(*client, at_handler, rhandler);
    rb_ivar_set(*client, at_protocol, sym_websocket);
    rb_ivar_set(*client, at_timeout, INT2FIX(120));
    rb_ivar_set(*client, at_server, s->self);

    const char *ws_key = NULL;
    const char *ws_protocol = NULL;
    const char *ws_extensions = NULL;
    size_t ws_key_length =
        uws_req_get_header(req, "sec-websocket-key", 17, &ws_key);
    size_t ws_protocol_length =
        uws_req_get_header(req, "sec-websocket-protocol", 22, &ws_protocol);
    size_t ws_extensions_length =
        uws_req_get_header(req, "sec-websocket-extensions", 24, &ws_extensions);
    uws_res_upgrade(USE_SSL, res, (void *)client, ws_key, ws_key_length,
                    ws_protocol, ws_protocol_length, ws_extensions,
                    ws_extensions_length, context);
  } else {
    // treat as normal request
    // response status
    if (!up_internal_set_response_status(res, rstatus))
      goto upgrade_error;

    // collect headers
    VALUE rheaders = rb_ary_entry(rres, 1);
    if (TYPE(rheaders) != T_HASH)
      goto upgrade_error;
    rb_hash_foreach(rheaders, up_internal_res_header_handler, (VALUE)res);

    // collect response body
    VALUE rparts = rb_ary_entry(rres, 2);
    up_internal_collect_response_body(res, rparts);

    // end response
    uws_res_end_without_body(USE_SSL, res, false);

    // close resources if necessary
    if (rb_respond_to(rparts, id_close))
      rb_funcall(rparts, id_close, 0);

    RB_GC_GUARD(rheaders);
  }
  return;
  RB_GC_GUARD(rstatus);
  RB_GC_GUARD(rres);
  RB_GC_GUARD(renv);
upgrade_error:
  fprintf(stderr, "upgrade error");
}

static void up_internal_close_sockets(int signal) {
  if (cluster_socket)
    us_listen_socket_close(false, cluster_socket);
  if (cluster_app)
    uws_app_close(USE_SSL, cluster_app);
}

static VALUE up_server_listen(VALUE self) {
  server_s *s = DATA_PTR(self);
  up_internal_check_arg_types(s->rapp, &s->host, &s->port);
  rb_ivar_set(mUp, at_instance, self);

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
  uws_app_listen_config_t config = {
      .port = FIX2INT(s->port), .host = RSTRING_PTR(s->host), .options = 0};
  VALUE rmember_id = rb_ivar_get(self, at_member_id);
  if (rmember_id != Qnil) {
    // got a cluster
    s->member_id = FIX2INT(rmember_id);
    // install signal handler
    cluster_app = s->app;
    cluster_socket = NULL;
    struct sigaction upclcl = {.sa_handler = up_internal_close_sockets,
                               .sa_flags = 0};
    sigemptyset(&upclcl.sa_mask);
    sigaction(SIGINT, &upclcl, NULL);
    // open publish ports
    VALUE rworkers = rb_ivar_get(self, at_workers);
    s->workers = FIX2INT(rworkers);
    VALUE rsecret = rb_ivar_get(self, at_secret);
    if (TYPE(rsecret) != T_STRING || RSTRING_LEN(rsecret) != 36)
      rb_raise(rb_eTypeError, "cluster secret of unknown type");
    memcpy(s->secret, RSTRING_PTR(rsecret), 36);
    s->secret[36] = '\0';
    uws_app_any(USE_SSL, s->app, INTERNAL_PUBLISH_PATH,
                up_internal_publish_handler, (void *)s);
    uws_app_listen_config_t config_internal = {
        .port = config.port + s->member_id, .host = "localhost", .options = 0};
    uws_app_listen_with_config(false, s->app, config_internal,
                               up_server_cluster_listen_handler, NULL);
  } else {
    cluster_app = s->app;
    cluster_socket = NULL;
    struct sigaction upclcl = {.sa_handler = up_internal_close_sockets,
                               .sa_flags = 0};
    sigemptyset(&upclcl.sa_mask);
    sigaction(SIGINT, &upclcl, NULL);
  }
  uws_app_post(USE_SSL, s->app, "/*", up_server_post_handler, (void *)s);
  uws_app_any(USE_SSL, s->app, "/*", up_server_any_handler, (void *)s);
  uws_ws(USE_SSL, s->app, "/*",
         (uws_socket_behavior_t){.compression = DISABLED,
                                 .maxPayloadLength = 5 * 1024 * 1024,
                                 .idleTimeout = 120,
                                 .upgrade = up_ws_upgrade_handler,
                                 .open = up_ws_open_handler,
                                 .message = up_ws_message_handler,
                                 .close = up_ws_close_handler,
                                 .drain = up_ws_drain_handler,
                                 .ping = up_ws_ping_handler,
                                 .pong = up_ws_pong_handler},
         s);
  uws_app_listen_with_config(USE_SSL, s->app, config, up_server_listen_handler,
                             NULL);
  uws_app_run(USE_SSL, s->app);
  return self;
}

static VALUE up_server_publish(VALUE self, VALUE channel, VALUE message) {
  if (TYPE(channel) != T_STRING)
    channel = rb_obj_as_string(channel);
  if (TYPE(message) != T_STRING)
    message = rb_obj_as_string(message);
  server_s *s = DATA_PTR(self);
  VALUE members = rb_ivar_get(self, at_members);
  if (members != Qnil) {
    long i, mb_cnt = RARRAY_LEN(members);
    for (i = 0; i < mb_cnt; i++) {
      up_internal_publish_to_member(s, channel, message, i);
    }
  } else {
    uws_publish(USE_SSL, s->app, RSTRING_PTR(channel), RSTRING_LEN(channel),
                RSTRING_PTR(message), RSTRING_LEN(message), TEXT, false);
    if (s->member_id > 0) {
      // publish to cluster members
      int i;
      for (i = 1; i <= s->workers; i++) {
        if (i != s->member_id)
          up_internal_publish_to_member(s, channel, message, i);
      }
    }
  }
  return Qtrue;
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

  // The input stream is an IO-like object which contains the raw HTTP POST
  // data
  rb_hash_aset(rack_env_template, rack_input, default_input);

  // A common object interface for logging messages
  up_hash_set(rack_env_template, "rack.logger", default_logger);

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

static VALUE up_publish(VALUE self, VALUE channel, VALUE message) {
  VALUE instance = rb_ivar_get(mUp, at_instance);
  if (instance != Qnil)
    return rb_funcall(instance, id_publish, 2, channel, message);
  return Qfalse;
}

void Init_up_ext(void) {
  at_env = rb_intern("@env");
  at_handler = rb_intern("@handler");
  at_instance = rb_intern("@instance");
  at_member_id = rb_intern("@member_id");
  at_members = rb_intern("@members");
  at_open = rb_intern("@open");
  at_port = rb_intern("@port");
  at_protocol = rb_intern("@protocol");
  at_secret = rb_intern("@secret");
  at_server = rb_intern("@server");
  at_timeout = rb_intern("@timeout");
  at_workers = rb_intern("@workers");
  id_app = rb_intern("app");
  id_call = rb_intern("call");
  id_close = rb_intern("close");
  id_each = rb_intern("each");
  id_host = rb_intern("host");
  id_logger = rb_intern("logger");
  id_new = rb_intern("new");
  id_on_close = rb_intern("on_close");
  id_on_drained = rb_intern("on_drained");
  id_on_message = rb_intern("on_message");
  id_on_open = rb_intern("on_open");
  id_port = rb_intern("port");
  id_publish = rb_intern("publish");

  utf8_encoding = rb_enc_find("UTF-8");
  binary_encoding = rb_enc_find("binary");

  set_str_val(empty_string, "");
  set_str_val(http11, "HTTP/1.1");
  set_str_val(rack_input, "rack.input");
  set_str_val(rack_logger, "rack.logger");
  set_str_val(rack_upgrade, "rack.upgrade");
  set_str_val(rack_upgrade_q, "rack.upgrade?");
  set_sym_val(sym_websocket, "websocket");
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
  default_logger = rb_funcall(cLogger, id_new, 1, rb_stderr);

  rb_require("stringio");

  rb_gc_register_address(&cStringIO);
  cStringIO = rb_const_get(rb_cObject, rb_intern("StringIO"));
  rb_gc_register_address(&default_input);
  default_input = rb_funcall(cStringIO, id_new, 1, empty_string);

  up_setup_rack_env_template();

  mUp = rb_define_module("Up");
  rb_define_singleton_method(mUp, "publish", up_publish, 2);

  cClient = rb_define_class_under(mUp, "Client", rb_cObject);
  rb_define_alloc_func(cClient, up_client_alloc);
  rb_define_method(cClient, "close", up_client_close, 0);
  rb_define_method(cClient, "pending", up_client_pending, 0);
  rb_define_method(cClient, "publish", up_client_publish, 2);
  rb_define_method(cClient, "subscribe", up_client_subscribe, -1);
  rb_define_method(cClient, "unsubscribe", up_client_unsubscribe, -1);
  rb_define_method(cClient, "write", up_client_write, 1);

  mRuby = rb_define_module_under(mUp, "Ruby");

  cServer = rb_define_class_under(mRuby, "Server", rb_cObject);
  rb_define_alloc_func(cServer, up_server_alloc);
  rb_define_method(cServer, "initialize", up_server_init, -1);
  rb_define_method(cServer, "listen", up_server_listen, 0);
  rb_define_method(cServer, "publish", up_server_publish, 2);
  rb_define_method(cServer, "stop", up_server_stop, 0);
}
