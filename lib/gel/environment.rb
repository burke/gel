# frozen_string_literal: true

require_relative "god_object"

class Gel::Environment
  def initialize(store)
    @impl = Gel::GodObject::Impl.new(store)
  end

  # Just accessors for global state bits
  def gemfile = @impl.__gemfile
  def store = @impl.__store

  # only used in tests
  def gemfile=(o)
    @impl.__set_gemfile(o)
  end

  # Read-only
  def lockfile_name(gemfile = @impl.__gemfile&.filename) = Gel::GodObject::Stateless.lockfile_name(gemfile)
  def filtered_gems(gems = @impl.__gemfile.gems) = Gel::GodObject::Stateless.filtered_gems(gems)
  def find_executable(exe, gem_name = nil, gem_version = nil) = Gel::GodObject::Stateless.find_executable(@impl.__store, exe, gem_name, gem_version)
  def find_gem(name, *requirements, &condition) = Gel::GodObject::Stateless.find_gem(@impl.__store, name, *requirements, &condition)
  def find_gemfile(path = nil, error: true) = Gel::GodObject::Stateless.find_gemfile(@impl.__gemfile, path, error: error)
  def gem_for_path(path) = Gel::GodObject::Stateless.gem_for_path(@impl.__store, Gel::LoadPathManager.activated_gems, path)
  def locked? = Gel::GodObject::Stateless.locked?(@impl.__store)
  def write_lock(output: nil, lockfile: lockfile_name, **args) = Gel::GodObject::Stateless.write_lock(@impl.load_gemfile, @impl.__store, output: output, lockfile: lockfile, **args)
  # gem_has_file? and scoped_require exclusively used by GemfileParser#autorequire
  def gem_has_file?(gem_name, path) = Gel::GodObject::Stateless.gem_has_file?(@impl.__store, Gel::LoadPathManager.activated_gems, gem_name, path)
  # requires are obviously side effects.. how can we flag these clearly?
  def scoped_require(gem_name, path) = Gel::GodObject::Stateless.scoped_require(@impl.__store, Gel::LoadPathManager.activated_gems, gem_name, path)
  def require_groups(*groups) = Gel::GodObject::Stateless.require_groups(@impl.__gemfile, *groups)

  # Significant mutations
  def activate(fast: false, install: false, output: nil, error: true) = @impl.activate(fast: fast, install: install, output: output, error: error)
  def activate_for_executable(exes, install: false, output: nil) = @impl.activate_for_executable(exes, install: install, output: output)
  def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true) = @impl.install_gem(catalogs, gem_name, requirements, output: output, solve: solve)
  def gem(name, *requirements, why: nil) = @impl.gem(name, *requirements, why: why)
  def resolve_gem_path(path) = @impl.resolve_gem_path(path)
end
