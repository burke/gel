module Gel::GodObject::Stateless
  class << self
    def locked?(store) = store.is_a?(Gel::LockedStore)

    def build_architecture_list
      begin
        local = Gel::Support::GemPlatform.local

        list = []
        if local.cpu == "universal" && RUBY_PLATFORM =~ /^universal\.([^-]+)/
          list << "#$1-#{local.os}"
        end
        list << "#{local.cpu}-#{local.os}"
        list << "universal-#{local.os}" unless local.cpu == "universal"
        list = list.map { |arch| "#{arch}-#{local.version}" } + list if local.version
        list << "java" if defined?(org.jruby.Ruby)
        list << "ruby"

        list
      end.compact.map(&:freeze).freeze
    end

    def store_set(architectures)
      list = []
      architectures.each do |arch|
        list << Gel::MultiStore.subkey(arch, true)
        list << Gel::MultiStore.subkey(arch, false)
      end
      list
    end

    def original_rubylib
      lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
      lib.delete File.expand_path("../../slib", __dir__)
      return nil if lib.empty?
      lib.join(File::PATH_SEPARATOR)
    end

    def modified_rubylib
      lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
      dir = File.expand_path("../../slib", __dir__)
      lib.unshift dir unless lib.include?(dir)
      lib.join(File::PATH_SEPARATOR)
    end
  end
end
