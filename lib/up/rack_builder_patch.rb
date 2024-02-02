module Rack
  class Builder
    def self.load_file(path, **options)
      config = ::File.read(path)

      # config = config.slice(/\A#{UTF_8_BOM}/) if config.encoding == Encoding::UTF_8

      if config[/^#\\(.*)/]
        fail "Parsing options from the first comment line is no longer supported: #{path}"
      end

      config = config.sub(/^__END__\n.*\Z/m, '')

      return new_from_string(config, path, **options)
    end
  end
end
