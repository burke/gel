require "rbconfig"

module Gel::HostSystem
  GEMFILE_PLATFORMS = begin
    v = RbConfig::CONFIG["ruby_version"].split(".")[0..1].inject(:+)

    # FIXME: This isn't the right condition
    if defined?(org.jruby.Ruby)
      ["jruby", "jruby_#{v}", "java", "java_#{v}"]
    else
      ["ruby", "ruby_#{v}", "mri", "mri_#{v}"]
    end
  end

  def self.store_keys
    list = []
    architectures.each do |arch|
      list << Gel::MultiStore.subkey(arch, true)
      list << Gel::MultiStore.subkey(arch, false)
    end
    list
  end

  def self.architectures
    @architectures ||= begin
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

      list.compact.map(&:freeze).freeze
    end
  end

  def self.rubylib_with_gel
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("../../slib", __dir__)
    lib.unshift dir unless lib.include?(dir)
    lib.join(File::PATH_SEPARATOR)
  end

  def self.rubylib_without_gel
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    lib.delete File.expand_path("../../slib", __dir__)
    return nil if lib.empty?
    lib.join(File::PATH_SEPARATOR)
  end
end
