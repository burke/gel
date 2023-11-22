require "rbconfig"

module Gel::GodObject::Stateless
  GEMFILE_PLATFORMS = begin
    v = RbConfig::CONFIG["ruby_version"].split(".")[0..1].inject(:+)

    # FIXME: This isn't the right condition
    if defined?(org.jruby.Ruby)
      ["jruby", "jruby_#{v}", "java", "java_#{v}"]
    else
      ["ruby", "ruby_#{v}", "mri", "mri_#{v}"]
    end
  end

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
      lib.delete File.expand_path("../../../slib", __dir__)
      return nil if lib.empty?
      lib.join(File::PATH_SEPARATOR)
    end

    def modified_rubylib
      lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
      dir = File.expand_path("../../../slib", __dir__)
      lib.unshift dir unless lib.include?(dir)
      lib.join(File::PATH_SEPARATOR)
    end

    def find_executable(store, exe, gem_name = nil, gem_version = nil)
      store.each(gem_name) do |g|
        next if gem_version && g.version != gem_version
        return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
      end
      nil
    end

    def filtered_gems(gems)
      platforms = GEMFILE_PLATFORMS.map(&:to_s)
      gems.reject do |_, _, options|
        platform_options = Array(options[:platforms]).map(&:to_s)

        next true if platform_options.any? && (platform_options & platforms).empty?
        next true unless options.fetch(:install_if, true)
      end
    end

    def find_gemfile(current_gemfile, path = nil, error: true)
      if path && current_gemfile && current_gemfile.filename != File.expand_path(path)
        raise Gel::Error::CannotActivateError.new(path: path, gemfile: current_gemfile.filename)
      end
      return current_gemfile.filename if current_gemfile

      path ||= ENV["GEL_GEMFILE"]
      path ||= Gel::Util.search_upwards("Gemfile")
      path ||= "Gemfile"

      if File.exist?(path)
        path
      elsif error
        raise Gel::Error::NoGemfile.new(path: path)
      end
    end

    def lockfile_name(gemfile)
      ENV["GEL_LOCKFILE"] || (gemfile && gemfile + ".lock") || "Gemfile.lock"
    end

    def root_store(store)
      if store.is_a?(Gel::LockedStore)
        store.inner
      else
        store
      end
    end

    def write_lock(output: nil, lockfile: lockfile_name, **args)
      # TODO XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
      gem_set = Gel::GodObject.impl.send(:solve_for_gemfile, output: output, lockfile: lockfile, **args)

      if lockfile
        output.puts "Writing lockfile to #{File.expand_path(lockfile)}" if output
        File.write(lockfile, gem_set.dump)
      end

      gem_set
    end
  end
end
