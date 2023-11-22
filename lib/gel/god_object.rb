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
    def activate_for_executable(exes, install: false, output: nil) = impl.activate_for_executable(exes, install: install, output: output)
    def activated_gems = impl.__activated_gems
    def config = impl.config
    def filtered_gems(gems = impl.__gemfile.gems) = impl.filtered_gems(gems)
    def find_executable(exe, gem_name = nil, gem_version = nil) = impl.find_executable(exe, gem_name, gem_version)
    def find_gem(name, *requirements, &condition) = impl.find_gem(name, *requirements, &condition)
    def find_gemfile(path = nil, error: true) = impl.find_gemfile(path, error: error)
    def gem(name, *requirements, why: nil) = impl.gem(name, *requirements, why: why)
    def gem_for_path(path) = impl.gem_for_path(path)
    def gem_has_file?(gem_name, path) = impl.gem_has_file?(gem_name, path)
    def gemfile = impl.__gemfile
    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true) = impl.install_gem(catalogs, gem_name, requirements, output: output, solve: solve)
    def load_gemfile(path = nil, error: true) = impl.load_gemfile(path, error: error)
    def locked? = impl.locked?
    def lockfile_name(gemfile = self.gemfile&.filename) = impl.lockfile_name(gemfile)
    def modified_rubylib = impl.modified_rubylib
    def open(store) = impl.open(store)
    def original_rubylib = impl.original_rubylib
    def resolve_gem_path(path) = impl.resolve_gem_path(path)
    def root_store(store = store()) = impl.root_store(store)
    def scoped_require(gem_name, path) = impl.scoped_require(gem_name, path)
    def store = impl.__store
    def store_set = impl.store_set
    def write_lock(output: nil, lockfile: lockfile_name, **args) = impl.write_lock(output: output, lockfile: lockfile, **args)
  end

  module Stateless
  end

  class Impl
    def __set_gemfile(o)
      @gemfile = o
    end
    def __gemfile = @gemfile
    def __store = @store
    def __activated_gems = @activated_gems

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

    def locked? = Stateless.locked?(@store)
    def store_set = Stateless.store_set(@architectures)

    def open(store)
      @store = store

      if @store.respond_to?(:locked_versions) && @store.locked_versions
        gems = @store.gems(@store.locked_versions)
        activate_gems gems.values
      end
    end

    def original_rubylib = Stateless.original_rubylib
    def modified_rubylib = Stateless.modified_rubylib
    def find_gemfile(path = nil, error: true) = Stateless.find_gemfile(@gemfile, path, error: error)

    def load_gemfile(path = nil, error: true)
      return @gemfile if @gemfile

      path = find_gemfile(path, error: error)
      return if path.nil?

      content = File.read(path)
      @gemfile = Gel::GemfileParser.parse(content, path, 1)
    end

    def lockfile_name(gemfile = @gemfile&.filename) = Stateless.lockfile_name(gemfile)
    def root_store(store = @store) = Stateless.root_store(store)
    def write_lock(output: nil, lockfile: lockfile_name, **args) = Stateless.write_lock(output: output, lockfile: lockfile, **args)

    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
      gemfile = Gel::GemfileParser.inline do
        source "https://rubygems.org"

        gem gem_name, *requirements
      end

      gem_set = solve_for_gemfile(output: output, solve: solve, gemfile: gemfile)

      loader = Gel::LockLoader.new(gem_set)
      locked_store = loader.activate(self, root_store, install: true, output: output)
      open(locked_store)
    end

    def activate(fast: false, install: false, output: nil, error: true)
      loaded = Gel::GodObject.load_gemfile(error: error)
      return if loaded.nil?
      return if @active_lockfile

      lockfile = Gel::GodObject.lockfile_name
      if File.exist?(lockfile)
        resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: git_depot)

        resolved_gem_set = nil if !fast && lock_outdated?(loaded, resolved_gem_set)
      end

      return if fast && !resolved_gem_set

      resolved_gem_set ||= write_lock(output: output, lockfile: lockfile)

      @active_lockfile = true
      loader = Gel::LockLoader.new(resolved_gem_set, @gemfile)

      require_relative "../../slib/bundler"

      locked_store = loader.activate(Gel::GodObject, root_store, install: install, output: output)
      open(locked_store)
    end

    def activate_for_executable(exes, install: false, output: nil)
      loaded_gemfile = nil
      resolved_gem_set = nil
      outdated_gem_set = nil
      load_error = nil

      if loaded_gemfile = Gel::GodObject.load_gemfile(error: false)
        lockfile = Gel::GodObject.lockfile_name
        if File.exist?(lockfile)
          resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: git_depot)

          if lock_outdated?(loaded_gemfile, resolved_gem_set)
            outdated_gem_set = resolved_gem_set
            resolved_gem_set = nil
          end
        end

        if resolved_gem_set
          loader = Gel::LockLoader.new(resolved_gem_set, @gemfile)

          begin
            locked_store = loader.activate(self, root_store, install: install, output: output)

            exes.each do |exe|
              if locked_store.each.any? { |g| g.executables.include?(exe) }
                open(locked_store)
                return :lock
              end
            end
          rescue Gel::Error::MissingGemError => ex
            load_error = ex
          end
        end
      end

      locked_gems =
        if resolved_gem_set
          resolved_gem_set.gem_names
        elsif loaded_gemfile
          loaded_gemfile.gem_names | (outdated_gem_set&.gem_names || [])
        else
          []
        end

      @gemfile = nil
      exes.each do |exe|
        candidates = @store.each.select { |g| g.executables.include?(exe) }

        locked_candidates, unlocked_candidates =
          candidates.partition { |g| locked_gems.include?(g.name) }

        # If we failed to load the lockfile, but we've now found a candidate
        # supplied by a locked gem, it's time to fail: we have to run locked
        # gems in a locked environment, and we can't do that right now.
        # The user probably needs to run `gel install`, which is what this
        # error will tell them to do.
        if locked_candidates.any?
          if load_error
            raise load_error
          elsif outdated_gem_set
            raise Gel::Error::OutdatedLockfileError
          elsif resolved_gem_set.nil?
            raise Gel::Error::NoLockfileError
          else
            # The lockfile was up-to-date and fully processed; we can
            # continue and ignore the locked candidates. This could happen
            # if non-locked versions of locked gems supply the executable.
            # We could still succeed if an unlocked_candidate can fill in.
          end
        end

        # Specific situation, but plausible enough to warrant a more
        # helpful error: there's no ambiguity about who owns the
        # executable name, but the one gem that supplies it is locked to a
        # version that doesn't have it.
        if unlocked_candidates.empty? && locked_candidates.map(&:name).uniq.size == 1
          # We're going to describe the set of versions (that we know
          # about) that would have supplied the executable.
          valid_versions = locked_candidates.map(&:version).uniq.map { |v| Gel::Support::Version.new(v) }.sort
          locked_version = Gel::Support::Version.new(resolved_gem_set.gems[locked_candidates.first.name].version)

          # Most likely, our not-executable-having version is outside some
          # contiguous range of executable-having versions, so let's check
          # for that, because it'll give us a shorter error message.
          #
          # (Note we assume but don't prove that every version we know
          # about within the range does have the executable. If that
          # assumption is wrong, the user will get the full list after
          # they retry with a bad in-range version.)
          if valid_versions.first > locked_version || valid_versions.last < locked_version
            valid_versions = valid_versions.first.to_s..valid_versions.last.to_s
          elsif valid_versions.size == 1
            valid_versions = valid_versions.first.to_s
          else
            valid_versions = valid_versions.map(&:to_s)
          end

          raise Gel::Error::MissingExecutableError.new(
            executable: exe,
            gem_name: locked_candidates.first.name,
            gem_versions: valid_versions,
            locked_gem_version: locked_version.to_s,
          )
        end

        case candidates.size
        when 0
          nil
        when 1
          gem(candidates.first.name)
          return :gem
        else
          # Multiple gems can supply this executable; do we have any
          # useful way of deciding which one should win? One obvious
          # tie-breaker: if a gem's name matches the executable, it wins.

          if candidates.map(&:name).include?(exe)
            gem(exe)
          else
            gem(candidates.first.name)
          end

          return :gem
        end
      end

      nil
    end

    def find_executable(exe, gem_name = nil, gem_version = nil) = Stateless.find_executable(@store, exe, gem_name, gem_version)
    def filtered_gems(gems = @gemfile.gems) = Stateless.filtered_gems(gems)

    def find_gem(name, *requirements, &condition)
      requirements = Gel::Support::GemRequirement.new(requirements)

      @store.each(name).find do |g|
        g.satisfies?(requirements) && (!condition || condition.call(g))
      end
    end

    def gem(name, *requirements, why: nil)
      return if IGNORE_LIST.include?(name)

      requirements = Gel::Support::GemRequirement.new(requirements)

      if existing = @activated_gems[name]
        if existing.satisfies?(requirements)
          return
        else
          raise Gel::Error::AlreadyActivatedError.new(
            name: name,
            existing: existing.version,
            requirements: requirements,
            why: why,
          )
        end
      end

      found_any = false
      gem = @store.each(name).find do |g|
        found_any = true
        g.satisfies?(requirements)
      end

      if gem
        activate_gem gem, why: why
      else
        raise Gel::Error::UnsatisfiedDependencyError.new(
          name: name,
          was_locked: locked?,
          found_any: found_any,
          requirements: requirements,
          why: why,
        )
      end
    end

    def gem_has_file?(gem_name, path)
      search_name, search_ext = Gel::Util.split_filename_for_require(path)

      @store.gems_for_lib(search_name) do |gem, subdir, ext|
        next unless Gel::Util.ext_matches_requested?(ext, search_ext)

        if gem.name == gem_name && gem == @activated_gems[gem_name]
          return gem.path(path, subdir)
        end
      end

      false
    end

    def scoped_require(gem_name, path)
      if full_path = gem_has_file?(gem_name, path)
        require full_path
      else
        raise ::LoadError, "No file #{path.inspect} found in gem #{gem_name.inspect}"
      end
    end


    def gem_for_path(path)
      gem, _file, _resolved = scan_for_path(path)
      gem
    end

    def resolve_gem_path(path)
      path = path.to_s # might be e.g. a Pathname

      gem, file, resolved = scan_for_path(path)

      if file
        if gem && resolved
          activate_gems resolved
        else
          unless resolved
            # This is a cheat: we're assuming the caller is about to require
            # the file
            Gel::Stdlib.instance.activate(path)
          end
        end

        return file
      elsif resolved
        raise resolved
      end

      path
    end

    private

    def activate_gem(gem, why: nil)
      raise gem.version.class.name unless gem.version.class == String
      if @activated_gems[gem.name]
        raise @activated_gems[gem.name].version.class.name unless @activated_gems[gem.name].version.class == String
        return if @activated_gems[gem.name].version == gem.version

        raise Gel::Error::AlreadyActivatedError.new(
          name: gem.name,
          existing: @activated_gems[gem.name].version,
          requested: gem.version,
          why: why,
        )
      end

      gem.dependencies.each do |dep, reqs|
        self.gem(dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" }, why: ["required by #{gem.name} #{gem.version}", *why])
      end

      activate_gems [gem]
    end

    def activate_gems(gems)
      lib_dirs = gems.flat_map(&:require_paths)
      preparation = {}
      activation = {}

      gems.each do |g|
        preparation[g.name] = g.version
        activation[g.name] = g
      end

      @store.prepare(preparation)

      @activated_gems.update(activation)
      $:.concat lib_dirs
    end

    def gemfile_dependencies(gemfile:) = Stateless.gemfile_dependencies(gemfile: gemfile)

    # Returns either an array of compatible gems that must all be activated
    # (in the specified order) to activate the given +gem+, or a LoadError
    # describing a dependency conflict that prevents it.
    #
    ##
    #
    # Recurses using internal +context+ as a hash of additional gems to
    # consider already activated. This is used to identify internal conflicts
    # between pending dependencies.
    def gems_for_activation(gem, why: nil, context: {})
      if active_gem = @activated_gems[gem.name] || context[gem.name]
        # This gem name is already active. Either it's the right version, and
        # we have nothing to do, or it's the wrong version, and we're unable
        # to proceed.
        if active_gem == gem
          return []
        else
          return Gel::Error::AlreadyActivatedError.new(
            name: gem.name,
            existing: active_gem.version,
            requested: gem.version,
            why: why,
          )
        end
      end

      context = context.dup
      new_gems = [gem]
      context[gem.name] = gem

      gem.dependencies.each do |dep, reqs|
        next if IGNORE_LIST.include?(dep)

        inner_why = ["required by #{gem.name} #{gem.version}", *why]

        requirements = Gel::Support::GemRequirement.new(
          reqs.map { |(qual, ver)| "#{qual} #{ver}" }
        )

        if existing = @activated_gems[dep] || context[dep]
          if existing.satisfies?(requirements)
            next
          else
            return Gel::Error::AlreadyActivatedError.new(
              name: dep,
              existing: existing.version,
              requirements: requirements,
              why: inner_why,
            )
          end
        end

        resolved = nil
        first_failure = nil

        found_any = false
        candidates = @store.each(dep).select do |g|
          found_any = true
          g.satisfies?(requirements)
        end

        candidates.each do |g|
          result = gems_for_activation(g, why: inner_why, context: context)
          if result.is_a?(Exception)
            first_failure ||= result
          else
            resolved = result
            break
          end
        end

        if resolved
          new_gems += resolved
          resolved.each do |r|
            context[r.name] = r
          end
        elsif first_failure
          return first_failure
        else

          return Gel::Error::UnsatisfiedDependencyError.new(
            name: dep,
            was_locked: locked?,
            found_any: found_any,
            requirements: requirements,
            why: inner_why,
          )
        end
      end

      new_gems
    end

    def git_depot
      require_relative "git_depot"
      @git_depot ||= Gel::GitDepot.new(@store)
    end

    def lock_outdated?(gemfile, resolved_gem_set)
      gemfile_dependencies(gemfile: gemfile) != resolved_gem_set.dependencies
    end

    def require_groups(*groups)
      gems = filtered_gems
      groups = [:default] if groups.empty?
      groups = groups.map(&:to_s)
      gems = gems.reject { |g| ((g[2][:group] || [:default]).map(&:to_s) & groups).empty? }
      @gemfile.autorequire(self, gems)
    end

    # Search gems and stdlib for how we should load the given +path+
    #
    # Returns nil when the path is unrecognised (caller should fall back to
    # scanning $LOAD_PATH). Otherwise, returns an array tuple:
    #
    # [
    #   gem,        # nil == stdlib
    #   file,       # full path to require, or nil if gem is conflicted
    #   resolved,   # if gem: array of gems to activate, or nil if empty
    #               # if conflicted: string describing conflict
    #               # if stdlib: boolean whether the file is known to already
    #               # be loaded (may return false negative)
    # ]
    def scan_for_path(path)
      if @store && !path.start_with?("/")
        search_name, search_ext = Gel::Util.split_filename_for_require(path)

        # Fast scan first: find all the gems that supply a file matching
        # +search_name+ (ignoring ext for now)
        hits = []
        @store.gems_for_lib(search_name) do |gem, subdir, ext|
          hits << [gem, subdir, ext]
        end

        # Now we get a bit more detailed: 1) skip any results that don't
        # match the +search_ext+; 2) immediately return if we've matched a
        # gem that's already loaded.
        results = []
        hits.each do |gem, subdir, ext|
          next unless Gel::Util.ext_matches_requested?(ext, search_ext)

          if @activated_gems[gem.name] == gem
            return [gem, gem.path(path, subdir), nil]
          else
            results << [gem, subdir, ext]
          end
        end

        # Okay, no already-loaded gems supply the file we're looking for.
        # +results+ contains a list of gems that we could load.

        # Before we start gaming out dependency trees for gems we could load,
        # it's time to check whether we've already loaded this file from
        # stdlib.
        stdlib = Gel::Stdlib.instance

        stdlib_path = stdlib.resolve(search_name, search_ext)
        stdlib_path += search_ext if stdlib_path && search_ext

        if stdlib_path && stdlib.active?(path)
          # Yep, we don't need to do anything
          return [nil, stdlib_path, true]
        end

        # We're going to have to activate a gem if we can. Recursively plan
        # out the set of dependencies we need to activate... or alternatively,
        # identify the conflict that prevents it.
        first_activation_error = nil
        results.each do |gem, subdir, ext|
          a = gems_for_activation(gem, why: ["provides #{path.inspect}"])
          if a.is_a?(Array)
            # This is a valid dependency set; activate +a+, and require the
            # file.
            return [gem, gem.path(path, subdir), a]
          else
            # If we don't find a better answer later in this loop (or in
            # +stdlib_path+), then this will be the failure we report.
            first_activation_error ||= [gem, nil, a]
          end
        end

        # We didn't find any viable gems to activate, so now we consider
        # whether we previously found a not-yet-loaded stdlib file.
        if stdlib_path
          return [nil, stdlib_path, false]
        end

        # Still no luck: this file cannot be resolved. If we found a gem that
        # was blocked by a conflict, we'll return the explanation as a string.
        # Otherwise (no installed gems have any knowledge of this file) we
        # return nil.
        first_activation_error
      end
    end

    def solve_for_gemfile(store: @store, output: nil, gemfile: Gel::GodObject.load_gemfile, lockfile: Gel::GodObject.lockfile_name, catalog_options: {}, solve: true, preference_strategy: nil, platforms: nil)
      Stateless.solve_for_gemfile(
        architectures: @architectures,
        store: store, output: output, gemfile: gemfile, lockfile: lockfile,
        catalog_options: catalog_options, solve: solve,
        preference_strategy: preference_strategy, platforms: platforms,
      )
    end
  end
end

require_relative "god_object/stateless"
