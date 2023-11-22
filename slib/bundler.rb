# frozen_string_literal: true

module Bundler
  ORIGINAL_ENV = ::ENV.to_h

  VERSION = "3.compat"

  def self.setup
    Gel::GodObject.activate(output: $stderr)
  end

  def self.original_env
    ORIGINAL_ENV.dup
  end

  def self.require(*groups)
    Gel::GodObject.require_groups(*groups)
  end

  def self.ruby_scope
    ""
  end

  def self.default_gemfile
    Kernel.require "pathname"
    ::Pathname.new(Gel::GodObject.find_gemfile(error: false) || "Gemfile")
  end

  def self.default_lockfile
    Kernel.require "pathname"
    ::Pathname.new(Gel::GodObject.lockfile_name)
  end

  def self.bundle_path
    Kernel.require "pathname"
    ::Pathname.new(Gel::GodObject.root_store.root)
  end

  def self.root
    Kernel.require "pathname"
    ::Pathname.new(Gel::GodObject.gemfile.filename).dirname
  end

  module RubygemsIntegration
    def self.loaded_specs(gem_name)
      Gem::Specification.new(Gel::GodObject.activated_gems[gem_name])
    end
  end

  # This is only emulated for bin/spring: we really don't want to try to
  # actually reproduce Bundler's API
  class LockfileParser
    def initialize(content)
    end

    def specs
      []
    end
  end

  def self.rubygems
    RubygemsIntegration
  end

  def self.with_original_env
    # TODO
    yield
  end

  def self.with_clean_env
    # TODO
    yield
  end

  def self.with_unbundled_env
    # TODO
    yield
  end

  def self.settings
    if gemfile = Gel::GodObject.gemfile
      { "gemfile" => gemfile.filename }
    else
      {}
    end
  end
end
