# backtick_javascript: true

require 'logger'
require 'up/version'

module Up
  module Bun
    class RackEnv < ::Hash
      RACK_VARS = %w[rack.errors rack.hijack rack.hijack? rack.input rack.logger
                    rack.multipart.buffer_size rack.multipart.tempfile_factory
                    rack.response_finished
                    rack.session rack.upgrade rack.upgrade? rack.url_scheme
                    HTTP_ACCEPT HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE
                    HTTP_CONNECTION HTTP_HOST HTTP_USER_AGENT PATH_INFO QUERY_STRING REQUEST_METHOD
                    SCRIPT_NAME SERVER_NAME SERVER_PROTOCOL SERVER_SOFTWARE]
      def initialize(req, config)
        @req = req
        @config = config
      end

      def [](key)
        return super(key) if key?(key)
        self[key] = case key
                    when 'rack.errors'
                      STDERR
                    when 'rack.hijack'
                      nil
                    when 'rack.hijack?'
                      false
                    when 'rack.input'
                      ::IO.new
                    when 'rack.logger'
                      ::Logger.new(self['rack.errors'])
                    when 'rack.multipart.buffer_size'
                      4096
                    when 'rack.multipart.tempfile_factory'
                      proc { |_filename, _content_type| File.new }
                    when 'rack.response_finished'
                      []
                    when 'rack.session'
                      {}
                    when 'rack.upgrade'
                      nil
                    when 'rack.upgrade?'
                      nil
                    when 'rack.url_scheme'
                      @config[:scheme]
                    when 'PATH_INFO'
                      `#@req.url`
                    when 'QUERY_STRING'
                      ""
                    when 'RACK_ERRORS'
                      self['rack.errors']
                    when 'RACK_LOGGER'
                      self['rack.logger']
                    when 'REQUEST_METHOD'
                      `#@req.method`
                    when 'SCRIPT_NAME'
                      ""
                    when 'SERVER_NAME'
                      @config[:host]
                    when 'SERVER_PORT'
                      @config[:port].to_s
                    when 'SERVER_PROTOCOL'
                      ""
                    when 'SERVER_SOFTWARE'
                      "#{@config[:handler]}/#{Up::VERSION} #{@config[:engine]}"
                    else
                      if key.start_with?('HTTP_')
                        key = key[5..].gsub(/_/, '-')
                        `#@req.headers.get(key.toLowerCase())`
                      else
                        nil
                      end
                    end
      end

      def req_headers
        h = {}
        %x{
          var hdr, hds = #@req.headers;
          for (hdr of hds) { h.set(hdr[0], hdr[1]); }
        }
        h
      end

      def each
        unless @got_them_all
          RACK_VARS.each { |k| self[k] unless self.key?(k) }
          @got_them_all = true
        end
        super
      end

      def to_s
        unless @got_them_all
          RACK_VARS.each { |k| self[k] unless self.key?(k) }
          @got_them_all = true
        end
        super
      end
    end
  end
end
