# frozen_string_literal: true

module Callmend
  class Output
    attr_reader :stdout, :stderr

    def initialize
      @stdout = +""
      @stderr = +""
    end

    def write_out(text)
      @stdout << text
    end

    def write_err(text)
      @stderr << text
    end
  end
end
