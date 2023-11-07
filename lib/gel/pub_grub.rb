# frozen_string_literal: true

module Gel::PubGrub
  extend Gel::Autoload
  gel_autoload :PreferenceStrategy, "gel/pub_grub/preference_strategy"
  gel_autoload :Package, "gel/pub_grub/package"
  gel_autoload :Solver, "gel/pub_grub/solver"
  gel_autoload :Source, "gel/pub_grub/source"
end
