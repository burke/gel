# frozen_string_literal: true

module Gel
  module Autoload
    def gel_autoload(const_name, relative_path)
      self.autoload(const_name, File.expand_path(relative_path, __dir__))
    end
  end

  module Support
    extend Autoload

    gel_autoload(:CGIEscape, "gel/support/cgi_escape")
    gel_autoload(:GemPlatform, "gel/support/gem_platform")
    gel_autoload(:GemRequirement, "gel/support/gem_requirement")
    gel_autoload(:GemVersion, "gel/support/gem_version")
    gel_autoload(:SHA512, "gel/support/sha512")
    gel_autoload(:Tar, "gel/support/tar")
  end

  module Vendor
    extend Autoload

    gel_autoload(:PStore, "../vendor/pstore/lib/pstore")
    gel_autoload(:RubyDigest, "../vendor/ruby-digest/lib/ruby_digest")
    gel_autoload(:PubGrub, "../vendor/pub_grub/lib/pub_grub")
    gel_autoload(:Slop, "../vendor/slop/lib/slop")
  end

  extend Autoload

  gel_autoload(:ReportableError, "gel/error")
  gel_autoload(:UserError, "gel/error")
  gel_autoload(:LoadError, "gel/error")

  gel_autoload(:Catalog, "gel/catalog")
  gel_autoload(:CatalogSet, "gel/catalog_set")
  gel_autoload(:CLI, "gel/cli")
  gel_autoload(:Command, "gel/command")
  gel_autoload(:Config, "gel/config")
  gel_autoload(:DB, "gel/db")
  gel_autoload(:DirectGem, "gel/direct_gem")
  gel_autoload(:Environment, "gel/environment")
  gel_autoload(:Error, "gel/error")
  gel_autoload(:GemfileParser, "gel/gemfile_parser")
  gel_autoload(:GemspecParser, "gel/gemspec_parser")
  gel_autoload(:GitCatalog, "gel/git_catalog")
  gel_autoload(:GitDepot, "gel/git_depot")
  gel_autoload(:Httpool, "gel/httpool")
  gel_autoload(:Installer, "gel/installer")
  gel_autoload(:LockLoader, "gel/lock_loader")
  gel_autoload(:LockParser, "gel/lock_parser")
  gel_autoload(:LockedStore, "gel/locked_store")
  gel_autoload(:MultiStore, "gel/multi_store")
  gel_autoload(:NullSolver, "gel/null_solver")
  gel_autoload(:Package, "gel/package")
  gel_autoload(:PathCatalog, "gel/path_catalog")
  gel_autoload(:Pinboard, "gel/pinboard")
  gel_autoload(:Platform, "gel/platform")
  gel_autoload(:PubGrub, "gel/pub_grub")
  gel_autoload(:ResolvedGemSet, "gel/resolved_gem_set")
  gel_autoload(:Set, "gel/set")
  gel_autoload(:Stdlib, "gel/stdlib")
  gel_autoload(:Store, "gel/store")
  gel_autoload(:StoreCatalog, "gel/store_catalog")
  gel_autoload(:StoreGem, "gel/store_gem")
  gel_autoload(:StubSet, "gel/stub_set")
  gel_autoload(:TailFile, "gel/tail_file")
  gel_autoload(:Util, "gel/util")
  gel_autoload(:VERSION, "gel/version")
  gel_autoload(:VendorCatalog, "gel/vendor_catalog")
  gel_autoload(:WorkPool, "gel/work_pool")

  def self.stub(name)
    Gel::CLI.run(["stub", name, :stub, *ARGV])
  end

  # This can be used to e.g. identify $LOADED_FEATURES or source_locations
  # entries that belong to the running Gel instance
  def self.self_location
    File.expand_path("..", __dir__)
  end
end
