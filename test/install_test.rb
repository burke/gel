# frozen_string_literal: true

require "test_helper"

require "paperback/package"
require "paperback/package/installer"

class InstallTest < Minitest::Test
  def test_install_single_package
    Dir.mktmpdir do |dir|
      store = Paperback::Store.new(dir)

      result = Paperback::Package::Installer.new(store)
      g = Paperback::Package.extract(fixture_file("rack-2.0.3.gem"), result)
      g.compile
      g.install

      g = Paperback::Package.extract(fixture_file("rack-0.1.0.gem"), result)
      g.compile
      g.install

      assert File.exist?("#{dir}/gems/rack-2.0.3/SPEC")

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["rack", "0.1.0"],
        ["rack", "2.0.3"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: ["rackup"],
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("rack", "0.1.0").info)
    end
  end

  def test_record_dependencies
    with_fixture_gems_installed(["hoe-3.0.0.gem"]) do |store|
      assert_equal({
        bindir: "bin",
        executables: ["sow"],
        require_paths: ["lib"],
        dependencies: {
          "rake" => [["~>", "0.8"]],
        },
      }, store.gem("hoe", "3.0.0").info)
    end
  end

  def test_mode_on_installed_files
    with_fixture_gems_installed(["rack-2.0.3.gem"]) do |store|
      assert_equal 0644, File.stat("#{store.root}/gems/rack-2.0.3/lib/rack.rb").mode & 03777
      refute File.executable?("#{store.root}/gems/rack-2.0.3/lib/rack.rb")

      assert_equal 0755, File.stat("#{store.root}/gems/rack-2.0.3/bin/rackup").mode & 03777
      assert File.executable?("#{store.root}/gems/rack-2.0.3/bin/rackup")
    end
  end

  def test_installing_an_extension
    skip if jruby?

    Dir.mktmpdir do |dir|
      store = Paperback::Store.new(dir)
      result = Paperback::Package::Installer.new(store)
      g = Paperback::Package.extract(fixture_file("fast_blank-1.0.0.gem"), result)
      g.compile
      g.install

      # Files from gem
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/benchmark")
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/extconf.rb")
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/fast_blank.c")

      # Build artifact
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/fast_blank.o")

      # Compiled binary
      dlext = RbConfig::CONFIG["DLEXT"]
      assert File.exist?("#{dir}/ext/fast_blank-1.0.0/fast_blank.#{dlext}")

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["fast_blank", "1.0.0"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: [],
        extensions: true,
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("fast_blank", "1.0.0").info)
    end
  end

  def test_installing_a_rake_extension
    skip if jruby?

    with_fixture_gems_installed(["rake-12.3.2.gem", "ffi-1.9.25.gem"], multi: true) do |store|
      result = Paperback::Package::Installer.new(store)
      dir = store["ruby", true].root

      g = Paperback::Package.extract(fixture_file("sassc-2.0.0.gem"), result)
      g.compile
      g.install

      # Files from gem
      assert File.exist?("#{dir}/gems/sassc-2.0.0/ext/Rakefile")
      assert File.exist?("#{dir}/gems/sassc-2.0.0/lib/sassc.rb")

      # Compiled binary
      ext = RbConfig::CONFIG["DLEXT"]
      ext = "so" if ext == "bundle"
      # sassc's build script ignores sitelibdir, so the compiled binary
      # ends up in the gem dir.
      assert File.exist?("#{dir}/gems/sassc-2.0.0/ext/libsass/lib/libsass.#{ext}")

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["ffi", "1.9.25"],
        ["rake", "12.3.2"],
        ["sassc", "2.0.0"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: [],
        extensions: true,
        require_paths: ["lib"],
        dependencies: {
          "ffi" => [%w(~> 1.9.6)],
          "rake" => [%w(>= 0)],
        },
      }, store.gem("sassc", "2.0.0").info)
    end
  end
end
