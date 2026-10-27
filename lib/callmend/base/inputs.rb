# frozen_string_literal: true

require_relative "failure"

module Callmend
  class Inputs
    def initialize(read_file, read_stdin)
      @read_file = read_file
      @read_stdin = read_stdin
    end

    def text(path)
      bytes = read(path)
      decode_utf8(bytes, path)
    end

    def self.display_name(path)
      path == "-" ? "<stdin>" : path
    end

    private

    def read(path)
      path == "-" ? @read_stdin.call : @read_file.call(path)
    rescue SystemCallError, IOError
      raise Failure.new(2, "cannot read #{path}")
    end

    def decode_utf8(bytes, path)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      return text if text.valid_encoding?

      raise Failure.new(2, "#{self.class.display_name(path)}: input is not valid UTF-8")
    end
  end
end
