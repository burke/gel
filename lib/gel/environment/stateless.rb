# frozen_string_literal: true

require "rbconfig"

require_relative "../util"
require_relative "../host_system"
require_relative "../stdlib"
require_relative "../path_resolver"
require_relative "../gem_set_solver"

# This module contains a bunch of behaviour for Gel.environment.
# Some of it is pretty thorny and could use a reafactor, but what is here
# notably doesn't mutate any state on the Gel.environment except through callbacks.
#
# This is a transitional state: Environment needs to be split up a bit and this is
# a temporary home for this code while I pick it apart a bit more.
module Gel::Environment::Stateless
  class << self
    def find_executable(store, exe, gem_name = nil, gem_version = nil)
      store.each(gem_name) do |g|
        next if gem_version && g.version != gem_version
        return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
      end
      nil
    end

    def filtered_gems(gems)
      platforms = Gel::HostSystem::GEMFILE_PLATFORMS.map(&:to_s)
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

    def scoped_require(store, activated_gems, gem_name, path)
      if full_path = gem_has_file?(store, activated_gems, gem_name, path)
        yield full_path
      else
        raise ::LoadError, "No file #{path.inspect} found in gem #{gem_name.inspect}"
      end
    end

    def find_gem(store, name, *requirements, &condition)
      requirements = Gel::Support::GemRequirement.new(requirements)

      store.each(name).find do |g|
        g.satisfies?(requirements) && (!condition || condition.call(g))
      end
    end

    # NOTE: untested
    def require_groups(gemfile, *groups)
      gems = filtered_gems(gemfile.gems)
      groups = [:default] if groups.empty?
      groups = groups.map(&:to_s)
      gems = gems.reject { |g| ((g[2][:group] || [:default]).map(&:to_s) & groups).empty? }
      yield gems
    end

    def load_gemfile(gemfile, path = nil, error: true)
      path = find_gemfile(@gemfile, path, error: error)
      return if path.nil?

      content = File.read(path)
      Gel::GemfileParser.parse(content, path, 1)
    end

    def gem_has_file?(store, activated_gems, gem_name, path)
      search_name, search_ext = Gel::Util.split_filename_for_require(path)

      store.gems_for_lib(search_name) do |gem, subdir, ext|
        next unless Gel::Util.ext_matches_requested?(ext, search_ext)

        if gem.name == gem_name && gem == activated_gems[gem_name]
          return gem.path(path, subdir)
        end
      end

      false
    end
  end
end
