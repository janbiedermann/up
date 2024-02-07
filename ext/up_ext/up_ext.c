#include <ruby.h>
#include <unistd.h>
#include "libusockets.h"
#include "libuwebsockets.h"

#define USE_SSL 0

static VALUE mUp;
static VALUE mRuby;
static VALUE cServer;
static VALUE cCluster;
static VALUE cRackEnv;
static VALUE cRequest;

static ID id_app;
static ID id_call;
static ID id_close;
static ID id_each;
static ID id_host;
static ID id_port;

const rb_data_type_t up_request_t = {.wrap_struct_name = "Up::Ruby::Request",
                                       .function = {.dmark = NULL,
                                                    .dfree = NULL,
                                                    .dsize = NULL,
                                                    .dcompact = NULL,
                                                    .reserved = {0}},
                                       .parent = NULL,
                                       .data = NULL,
                                       .flags = 0};

VALUE up_internal_handle_part(RB_BLOCK_CALL_FUNC_ARGLIST(rpart, res)) {
  Check_Type(rpart, T_STRING);
  uws_res_write(USE_SSL, (uws_res_t *)res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
  return Qnil;
}

static void up_server_request_handler(uws_res_t *res, uws_req_t *req, void *rapp) {
  VALUE rreq = TypedData_Wrap_Struct(cRequest, &up_request_t, req);
  VALUE renv = rb_class_new_instance(1, (const VALUE *)&rreq, cRackEnv);
  VALUE rres = rb_funcall((VALUE)rapp, id_call, 1, renv);
  Check_Type(rres, T_ARRAY);
  VALUE rparts = RARRAY_AREF(rres, 2);
  VALUE rpart;
  if (TYPE(rparts) == T_ARRAY) {
    long i, l = RARRAY_LEN(rparts);
    for (i = 0; i < l; i++) {
      rpart = RARRAY_AREF(rparts, i);
      Check_Type(rpart, T_STRING);
      uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
    }
  } else if (rb_respond_to(rparts, id_each)) {
    rb_block_call(rparts, id_each, 0, NULL, up_internal_handle_part, (VALUE)res);
  } else if (rb_respond_to(rparts, id_call)) {
    rpart = rb_funcall(rparts, id_call, 0);
    Check_Type(rpart, T_STRING);
    uws_res_write(USE_SSL, res, RSTRING_PTR(rpart), RSTRING_LEN(rpart));
  }
  if (rb_respond_to(rparts, id_close))
    rb_funcall(rparts, id_close, 0);
  FIX2INT(RARRAY_PTR(rres)[0]);
  uws_res_end_without_body(USE_SSL, res, false);
}

static void up_server_listen_handler(struct us_listen_socket_t *listen_socket, uws_app_listen_config_t config, void *user_data) {
    if (listen_socket)
        fprintf(stderr, "Server is running on http://%s:%d\n", config.host, config.port);
}

static void up_server_t_free(void *p) {
  if (p)
    uws_app_destroy(USE_SSL, (uws_app_t *)p);
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
  uws_app_t *app = NULL;
  return TypedData_Wrap_Struct(rclass, &up_server_t, app);
}

static void up_internal_check_arg_types(VALUE rapp, VALUE *rhost, VALUE *rport) {
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
  ID kwargs[] = {id_app, id_host, id_port};
  VALUE rargs[3] = {Qnil, Qnil, Qnil};
  VALUE options = Qnil;

  rb_scan_args_kw(1, argc, argv, ":", &options);
  rb_get_kwargs(options, kwargs, 1, 2, rargs);
  
  VALUE rapp = rargs[0];
  VALUE rhost = rargs[1];
  VALUE rport = rargs[2];

  up_internal_check_arg_types(rapp, &rhost, &rport);

  rb_ivar_set(self, id_app, rapp);
  rb_ivar_set(self, id_host, rhost);
  rb_ivar_set(self, id_port, rport);
  return self;
}

static VALUE up_server_listen(VALUE self) {
  VALUE rapp = rb_ivar_get(self, id_app);
  VALUE rhost = rb_ivar_get(self, id_host);
  VALUE rport = rb_ivar_get(self, id_port);

  up_internal_check_arg_types(rapp, &rhost, &rport);

  struct us_socket_context_options_t options = {.key_file_name = NULL, .cert_file_name = NULL, .ca_file_name = NULL,
                                                .passphrase = NULL, .dh_params_file_name = NULL, .ssl_ciphers = NULL};
  DATA_PTR(self) = uws_create_app(USE_SSL, options);
  uws_app_t *app = DATA_PTR(self);
  if (!app)
    rb_raise(rb_eRuntimeError, "could not init uws app");
  uws_app_any(USE_SSL, app, "/*", up_server_request_handler, (void *)rapp);
  uws_app_listen_config_t config = {.port=3000, .host="localhost", .options=0};
  uws_app_listen_with_config(USE_SSL, app, config, up_server_listen_handler, NULL);
  uws_app_run(USE_SSL, app);
  return Qnil;
}

static VALUE up_server_stop(VALUE self) {
  uws_app_t *app = DATA_PTR(self);
  if (!app)
    rb_raise(rb_eRuntimeError, "no uws, did initialize call super?");
  uws_app_close(USE_SSL, app);
  return Qnil;
}

static VALUE up_cluster_listen(VALUE self) {
  VALUE rapp = rb_ivar_get(self, id_app);
  VALUE rhost = rb_ivar_get(self, id_host);
  VALUE rport = rb_ivar_get(self, id_port);

  up_internal_check_arg_types(rapp, &rhost, &rport);
  long i = sysconf(_SC_NPROCESSORS_ONLN);
  pid_t pid;
  for (; i > 1; i--) {
    pid = fork();
    if (pid > 0) {
      // do nothing
    } else if (pid == 0) {
      struct us_socket_context_options_t options = {.key_file_name = NULL, .cert_file_name = NULL, .ca_file_name = NULL,
                                                .passphrase = NULL, .dh_params_file_name = NULL, .ssl_ciphers = NULL};
      DATA_PTR(self) = uws_create_app(USE_SSL, options);
      uws_app_t *app = DATA_PTR(self);
      if (!app)
        rb_raise(rb_eRuntimeError, "could not init uws app");
      uws_app_any(USE_SSL, app, "/*", up_server_request_handler, (void *)rapp);
      uws_app_listen_config_t config = {.port=3000, .host="localhost", .options=0};
      uws_app_listen_with_config(USE_SSL, app, config, up_server_listen_handler, NULL);
      uws_app_run(USE_SSL, app);
    }
  }
  if (pid > 0) {
    struct us_socket_context_options_t options = {.key_file_name = NULL, .cert_file_name = NULL, .ca_file_name = NULL,
                                              .passphrase = NULL, .dh_params_file_name = NULL, .ssl_ciphers = NULL};
    DATA_PTR(self) = uws_create_app(USE_SSL, options);
    uws_app_t *app = DATA_PTR(self);
    if (!app)
      rb_raise(rb_eRuntimeError, "could not init uws app");
    uws_app_any(USE_SSL, app, "/*", up_server_request_handler, (void *)rapp);
    uws_app_listen_config_t config = {.port=3000, .host="localhost", .options=0};
    uws_app_listen_with_config(USE_SSL, app, config, up_server_listen_handler, NULL);
    uws_app_run(USE_SSL, app);
  }

  return Qnil;
}

static VALUE up_cluster_stop(VALUE self) {
  // uws_app_t *app = DATA_PTR(self);
  // uws_app_close(USE_SSL, app);
  return Qnil;
}

static VALUE up_request_alloc(VALUE rclass) {
  return TypedData_Wrap_Struct(rclass, &up_request_t, (uws_req_t*)NULL);
}

static void up_internal_header_handler(const char *h, size_t h_len, const char *v, size_t v_len, void *rheaders) {
  rb_hash_aset((VALUE)rheaders, rb_str_new(h, h_len), rb_str_new(v, v_len));
}

static VALUE up_request_headers(VALUE self) {
  uws_req_t *req = DATA_PTR(self);
  if (!req)
    return Qnil;
  VALUE rheaders = rb_hash_new();
  uws_req_for_each_header(req, up_internal_header_handler, (void *)rheaders);
  return rheaders;
}

static VALUE up_request_get_header(VALUE self, VALUE rheader) {
  uws_req_t *req = DATA_PTR(self);
  if (!req)
    return Qnil;
  Check_Type(rheader, T_STRING);
  const char *header;
  size_t len = uws_req_get_header(req, RSTRING_PTR(rheader), RSTRING_LEN(rheader), &header);
  return rb_str_new(header, len);
}

static VALUE up_request_get_method(VALUE self) {
  uws_req_t *req = DATA_PTR(self);
  if (!req)
    return Qnil;
  const char *method;
  size_t len = uws_req_get_method(req, &method);
  return rb_str_new(method, len);
}

static VALUE up_request_get_query(VALUE self) {
  return Qnil;
}

static VALUE up_request_get_url(VALUE self) {
  uws_req_t *req = DATA_PTR(self);
  if (!req)
    return Qnil;
  const char *url;
  size_t len = uws_req_get_url(req, &url);
  return rb_str_new(url, len);
}

void Init_up_ext(void) {
  id_app = rb_intern("app");
  id_call = rb_intern("call");
  id_close = rb_intern("close");
  id_each = rb_intern("each");
  id_host = rb_intern("host");
  id_port = rb_intern("port");

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

  cRackEnv = rb_define_class_under(mRuby, "RackEnv", rb_cHash);
  cRequest = rb_define_class_under(mRuby, "Request", rb_cObject);
  rb_define_alloc_func(cRequest, up_request_alloc);
  rb_define_method(cRequest, "each_header", up_request_headers, 0);
  rb_define_method(cRequest, "get_header", up_request_get_header, 1);
  rb_define_method(cRequest, "get_method", up_request_get_method, 0);
  rb_define_method(cRequest, "get_query", up_request_get_query, 0);
  rb_define_method(cRequest, "get_url", up_request_get_url, 0);
}
