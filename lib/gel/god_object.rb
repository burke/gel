# frozen_string_literal: true

require "rbconfig"
require_relative "util"
require_relative "stdlib"
require_relative "support/gem_platform"

class Gel::GodObject
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class << self
    def impl = Impl.instance

    def gemfile=(o)
      impl.__set_gemfile(o)
    end

    def activate(fast: false, install: false, output: nil, error: true) = impl.activate(fast: fast, install: install, output: output, error: error)
    def activate_for_executable(exes, install: false, output: nil) = Stateless.activate_for_executable(impl.__store, impl.__gemfile, exes, install: install, output: output)
    def activated_gems = impl.__activated_gems
    def config = impl.config
    def filtered_gems(gems = impl.__gemfile.gems) = Stateless.filtered_gems(gems)
    def find_executable(exe, gem_name = nil, gem_version = nil) = Stateless.find_executable(impl.__store, exe, gem_name, gem_version)
    def find_gem(name, *requirements, &condition) = Stateless.find_gem(impl.__store, name, *requirements, &condition)
    def find_gemfile(path = nil, error: true) = Stateless.find_gemfile(impl.__gemfile, path, error: error)
    def gem(name, *requirements, why: nil) = Stateless.gem(impl.__store, impl.__activated_gems, name, *requirements, why: why)
    def gem_for_path(path) = Stateless.gem_for_path(impl.__store, impl.__activated_gems, path)
    def gem_has_file?(gem_name, path) = Stateless.gem_has_file?(impl.__store, impl.__activated_gems, gem_name, path)
    def gemfile = impl.__gemfile
    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true) = Stateless.install_gem(impl.__architectures, impl.__store, catalogs, gem_name, requirements, output: output, solve: solve)
    def load_gemfile(path = nil, error: true) = impl.load_gemfile(path, error: error)
    def locked? = Stateless.locked?(impl.__store)
    def lockfile_name(gemfile = self.gemfile&.filename) = Stateless.lockfile_name(gemfile)
    def modified_rubylib = Stateless.modified_rubylib
    def open(store) = impl.open(store)
    def original_rubylib = Stateless.original_rubylib
    def resolve_gem_path(path) = Stateless.resolve_gem_path(impl.__store, impl.__activated_gems, path)
    def root_store(store = store()) = Stateless.root_store(store)
    def scoped_require(gem_name, path) = Stateless.scoped_require(impl.__store, impl.__activated_gems, gem_name, path)
    def store = impl.__store
    def store_set = Stateless.store_set(impl.__architectures)
    def write_lock(output: nil, lockfile: lockfile_name, **args) = Stateless.write_lock(impl.__architectures, impl.__store, output: output, lockfile: lockfile, **args)
    def require_groups(*groups) = Stateless.require_groups(impl.__gemfile, *groups)
  end

  class Impl
    def __set_gemfile(o)
      @gemfile = o
    end
    def __gemfile = @gemfile
    def __store = @store
    def __activated_gems = @activated_gems
    def __architectures = @architectures

    private_class_method :new
    def self.instance
      @instance ||= new
    end

    def initialize
      @config = nil
      @activated_gems = {}
      @gemfile = nil
      @active_lockfile = false
      @architectures = Stateless.build_architecture_list
    end

    def config
      @config ||= Gel::Config.new
    end

    def git_depot
      require_relative "git_depot"
      @git_depot ||= Gel::GitDepot.new(@store)
    end

    def open(store)
      @store = store
      Stateless.activate_locked_gems(@store, @activated_gems, $LOAD_PATH)
    end

    def load_gemfile(path = nil, error: true)
      @gemfile ||= Stateless.load_gemfile(@gemfile, path, error: error)
    end

    def activate(fast: false, install: false, output: nil, error: true)
      @active_lockfile ||= Stateless.activate(@active_lockfile, @architectures, @store, @gemfile, fast: fast, install: install, output: output, error: error)
      nil
    end
  end
end

require_relative "god_object/stateless"
