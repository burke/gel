module Gel::Support
  module Tar
    extend(Gel::Autoload)

    gel_autoload(:TarHeader, "gel/support/tar/tar_header")
    gel_autoload(:TarReader, "gel/support/tar/tar_reader")
    gel_autoload(:TarWriter, "gel/support/tar/tar_writer")

    class Error < ::RuntimeError; end

    class NonSeekableIO < Error; end
    class TooLongFileName < Error; end
    class TarInvalidError < Error; end
  end
end
