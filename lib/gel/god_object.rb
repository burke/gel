# frozen_string_literal: true

require "rbconfig"
require_relative "util"
require_relative "stdlib"
require_relative "support/gem_platform"
require_relative "load_path_manager"

class Gel::GodObject
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class << self
    def impl = Impl.instance

    # Should this be what creates an instance and makes most of the other methods available?
    def open(store) = impl.open(store)

    # Significant mutations
    def activate(fast: false, install: false, output: nil, error: true) = impl.activate(fast: fast, install: install, output: output, error: error)
    def activate_for_executable(exes, install: false, output: nil) = impl.activate_for_executable(exes, install: install, output: output)
    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true) = impl.install_gem(catalogs, gem_name, requirements, output: output, solve: solve)
    def gem(name, *requirements, why: nil) = impl.gem(name, *requirements, why: why)
    def resolve_gem_path(path) = impl.resolve_gem_path(path)

    # Just accessors for global state bits
    def gemfile = impl.__gemfile
    def store = impl.__store
    def config = impl.config # Not related to or used by anything else here.

    # only used in tests
    def gemfile=(o)
      impl.__set_gemfile(o)
    end

    # Read-only
    def lockfile_name(gemfile = impl.__gemfile&.filename) = Stateless.lockfile_name(gemfile)
    def filtered_gems(gems = impl.__gemfile.gems) = Stateless.filtered_gems(gems)
    def find_executable(exe, gem_name = nil, gem_version = nil) = Stateless.find_executable(impl.__store, exe, gem_name, gem_version)
    def find_gem(name, *requirements, &condition) = Stateless.find_gem(impl.__store, name, *requirements, &condition)
    def find_gemfile(path = nil, error: true) = Stateless.find_gemfile(impl.__gemfile, path, error: error)
    def gem_for_path(path) = Stateless.gem_for_path(impl.__store, Gel::LoadPathManager.activated_gems, path)
    def locked? = Stateless.locked?(impl.__store)
    def write_lock(output: nil, lockfile: lockfile_name, **args) = Stateless.write_lock(impl.load_gemfile, impl.__store, output: output, lockfile: lockfile, **args)
    def require_groups(*groups) = Stateless.require_groups(impl.__gemfile, *groups)

    # Exclusively used by GemfileParser#autorequire
    def gem_has_file?(gem_name, path) = Stateless.gem_has_file?(impl.__store, Gel::LoadPathManager.activated_gems, gem_name, path)
    def scoped_require(gem_name, path) = Stateless.scoped_require(impl.__store, Gel::LoadPathManager.activated_gems, gem_name, path)
  end

  class Impl
    def __set_gemfile(o)
      @gemfile = o
    end
    def __gemfile = @gemfile
    def __store = @store

    private_class_method :new
    def self.instance
      @instance ||= new
    end

    def initialize
      @config = nil
      @gemfile = nil
      @active_lockfile = false
    end

    def config
      @config ||= Gel::Config.new
    end

    def resolve_gem_path(path)
      Stateless.resolve_gem_path(@store, Gel::LoadPathManager.activated_gems, path, &method(:activate_gems_now))
    end

    def gem(name, *requirements, why: nil)
      Stateless.gem(@store, Gel::LoadPathManager.activated_gems, name, *requirements, why: why, &method(:activate_gems_now))
    end

    def open(store)
      @store = store
      Stateless.activate_locked_gems(@store, &method(:activate_gems_now))
    end

    def load_gemfile(path = nil, error: true)
      @gemfile ||= Stateless.load_gemfile(@gemfile, path, error: error)
    end

    def activate(fast: false, install: false, output: nil, error: true)
      @active_lockfile ||= Stateless.activate(@active_lockfile, load_gemfile(error: error), @store, @gemfile, fast: fast, output: output) do |loader|
        require_relative "../../slib/bundler"
        locked_store = loader.activate(Gel::GodObject, @store.root_store, install: install, output: output)
        open(locked_store)
      end
      nil
    end

    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
      Stateless.install_gem(@store, catalogs, gem_name, requirements, output: output, solve: solve) do |loader|
        locked_store = loader.activate(Gel::GodObject, @store.root_store, install: true, output: output)
        open(locked_store)
      end
    end

    def activate_gems_now(preparation, activation, lib_dirs)
      @store.prepare(preparation)
      Gel::LoadPathManager.activate(activation, lib_dirs)
    end

    def activate_for_executable(exes, install: false, output: nil)
      loaded_gemfile = load_gemfile(error: false)
      Stateless.activate_for_executable(loaded_gemfile, @store, Gel::LoadPathManager.activated_gems, @gemfile, exes, install: install, output: output, activate_gems_now: method(:activate_gems_now)) do |loader|
        locked_store = loader.activate(Gel::GodObject, @store.root_store, install: install, output: output)

        ret = nil
        exes.each do |exe|
          if locked_store.each.any? { |g| g.executables.include?(exe) }
            open(locked_store)
            ret = :lock
            break
          end
        end
        ret
      end
    end
  end
end

require_relative "god_object/stateless"
