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

    def install_gem(architectures, store, catalogs, gem_name, requirements = nil, output: nil, solve: true)
      gemfile = Gel::GemfileParser.inline do
        source "https://rubygems.org"
        gem gem_name, *requirements
      end

      gem_set = solve_for_gemfile(
        architectures: architectures, store: store,
        output: output, solve: solve, gemfile: gemfile, lockfile: lockfile_name(gemfile),
      )

      loader = Gel::LockLoader.new(gem_set)
      locked_store = loader.activate(Gel::GodObject, root_store(store), install: true, output: output)
      Gel::GodObject.open(locked_store)
    end

    # private

    def gemfile_dependencies(gemfile:)
      gemfile.gems.
        group_by { |name, _constraints, _options| name }.
        map do |name, list|

        constraints = list.flat_map { |_, c, _| c }.compact

        if constraints == []
          name
        else
          r = Gel::Support::GemRequirement.new(constraints)
          req_strings = r.requirements.sort_by { |(_op, ver)| [ver, ver.segments] }.map { |(op, ver)| "#{op} #{ver}" }

          "#{name} (#{req_strings.join(", ")})"
        end
      end.sort
    end

    def solve_for_gemfile(architectures:, store:, output:, gemfile:, lockfile:, catalog_options: {}, solve: true, preference_strategy: nil, platforms: nil)
      output = nil if $DEBUG

      target_platforms = Array(platforms)

      if lockfile && File.exist?(lockfile)
        require_relative "../resolved_gem_set"
        # TODO XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: Gel::GodObject.impl.send(:git_depot))
        target_platforms |= gem_set.platforms if gem_set.platforms

        strategy = preference_strategy&.call(gem_set)
      end

      if target_platforms.empty?
        possible_inferred_targets = architectures.map { |arch| Gel::Support::GemPlatform.new(arch) }
        target_platforms = [architectures.first]
      end

      require_relative "../work_pool"
      require_relative "../catalog"
      all_sources = (gemfile.sources | gemfile.gems.flat_map { |_, _, o| o[:source] }).compact
      local_source = all_sources.delete(:local)
      server_gems = gemfile.gems.select { |_, _, o| !o[:path] && !o[:git] }.map(&:first)
      catalog_pool = Gel::WorkPool.new(8, name: "gel-catalog")
      server_catalogs = all_sources.map { |s| Gel::Catalog.new(s, initial_gems: server_gems, work_pool: catalog_pool, **catalog_options) }

      require_relative "../store_catalog"
      local_catalogs = local_source ? [Gel::StoreCatalog.new(root_store(store))] : []

      git_sources = gemfile.gems.map { |_, _, o|
        if o[:git]
          if o[:branch]
            [o[:git], :branch, o[:branch]]
          elsif o[:tag]
            [o[:git], :tag, o[:tag]]
          else
            [o[:git], :ref, o[:ref]]
          end
        end
      }.compact.uniq

      path_sources = gemfile.gems.map { |_, _, o| o[:path] }.compact

      vendor_dir = File.expand_path("../vendor/cache", gemfile.filename)
      if Dir.exist?(vendor_dir)
        require_relative "../vendor_catalog"
        vendor_catalogs = [Gel::VendorCatalog.new(vendor_dir)]
      else
        vendor_catalogs = []
      end

      require_relative "../path_catalog"
      require_relative "../git_catalog"

      previous_git_catalogs = {}
      if gem_set
        gem_set.gems.each do |gem_name, gem_resolutions|
          next if strategy&.refresh_git?(gem_name)

          gem_resolutions.map(&:catalog).grep(Gel::GitCatalog).uniq.each do |catalog|
            previous_git_catalogs[[catalog.remote, catalog.ref_type, catalog.ref]] = catalog
          end
        end
      end

      git_catalogs = git_sources.map do |remote, ref_type, ref|
        # TODO XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        git_depot = Gel::GodObject.impl.send(:git_depot)
        previous_git_catalogs[[remote, ref_type, ref]] || Gel::GitCatalog.new(git_depot, remote, ref_type, ref)
      end

      catalogs =
        vendor_catalogs +
        path_sources.map { |path| Gel::PathCatalog.new(path) } +
        git_catalogs +
        [nil] +
        local_catalogs +
        server_catalogs

      Gel::WorkPool.new(8, name: "gel-catalog-prep") do |pool|
        if output
          output.print "Fetching sources..."
        else
          Gel::Httpool::Logger.info "Fetching sources..."
        end

        catalogs.each do |catalog|
          next if catalog.nil?

          pool.queue("catalog") do
            catalog.prepare
            output.print "." if output
          end
        end
      end

      require_relative "../catalog_set"
      catalog_set = Gel::CatalogSet.new(catalogs)

      if solve
        require_relative "../pub_grub/solver"

        if gem_set
          # If we have any existing resolution, and no strategy has been
          # provided (i.e. we're doing an auto-resolve for 'gel install'
          # or similar), then default to "anything is permitted, but
          # change the least necessary to satisfy our constraints"

          require_relative "../pub_grub/preference_strategy"
          strategy ||= Gel::PubGrub::PreferenceStrategy.new(gem_set, {}, bump: :hold, strict: false)
        end

        solver = Gel::PubGrub::Solver.new(gemfile: gemfile, catalog_set: catalog_set, platforms: target_platforms, strategy: strategy)
      else
        require_relative "../null_solver"
        solver = Gel::NullSolver.new(gemfile: gemfile, catalog_set: catalog_set, platforms: target_platforms)
      end

      if output
        output.print "\nResolving dependencies..."
        t = Time.now
        until solver.solved?
          solver.work
          if Time.now > t + 0.1
            output.print "."
            t = Time.now
          end
        end
        output.puts
      else
        if solver.respond_to?(:logger)
          solver.logger.info "Resolving dependencies..."
        end

        solver.work until solver.solved?
      end

      catalog_pool.stop

      new_resolution = Gel::ResolvedGemSet.new(lockfile)

      packages_by_name = {}
      versions_by_name = {}
      solver.each_resolved_package do |package, version|
        next if package.platform.nil?

        ((packages_by_name[package.name] ||= {})[catalog_set.platform_for(package, version)] ||= []) << package

        if versions_by_name[package.name]
          raise "Conflicting version resolution #{versions_by_name[package.name].inspect} != #{version.inspect}" if versions_by_name[package.name] != version
        else
          versions_by_name[package.name] = version
        end
      end

      active_platforms = []

      packages_by_name.each do |package_name, platformed_packages|
        version = versions_by_name[package_name]

        new_resolution.gems[package_name] =
          platformed_packages.map do |resolved_platform, packages|
            package = packages.first

            active_platforms << resolved_platform

            if possible_inferred_targets
              possible_inferred_targets = possible_inferred_targets.select do |target|
                next true if resolved_platform == "ruby"
                next false if target == "ruby"

                # This is a one-sided version of the GemPlatform#=== condition:
                # we want to know whether the target adequately specifies the
                # resolved platform, not just whether they're compatible.

                resolved = Gel::Support::GemPlatform.new(resolved_platform)
                ([nil, "universal"].include?(resolved.cpu) || resolved.cpu == target.cpu || resolved.cpu == "arm" && target.cpu.start_with?("arm")) &&
                  resolved.os == target.os &&
                  (resolved.version.nil? || resolved.version == target.version)
              end
            end

            catalog = catalog_set.catalog_for_version(package, version)

            deps = catalog_set.dependencies_for(package, version)

            resolved_platform = nil if resolved_platform == "ruby"

            Gel::ResolvedGemSet::ResolvedGem.new(
              package.name, version, resolved_platform,
              deps.map do |(dep_name, dep_requirements)|
                next [dep_name] if dep_requirements == [">= 0"] || dep_requirements == []

                req = Gel::Support::GemRequirement.new(dep_requirements)
                req_strings = req.requirements.map { |(op, ver)| "#{op} #{ver}" }.sort.reverse

                [dep_name, req_strings.join(", ")]
              end,
              set: new_resolution,
              catalog: catalog
            )
          end
      end
      new_resolution.dependencies = gemfile_dependencies(gemfile: gemfile)

      if possible_inferred_targets
        # Infer the least specific platform that selects all of the resolved
        # gems
        new_resolution.platforms = [possible_inferred_targets.last.to_s]
      else
        new_resolution.platforms = target_platforms & active_platforms
      end
      new_resolution.server_catalogs = server_catalogs
      new_resolution.bundler_version = gem_set&.bundler_version
      new_resolution.ruby_version = RUBY_DESCRIPTION.split.first(2).join(" ") if gem_set&.ruby_version
      new_resolution
    end
  end
end
