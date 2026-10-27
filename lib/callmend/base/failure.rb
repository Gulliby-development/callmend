# frozen_string_literal: true

module Callmend
  class Failure < StandardError
    attr_reader :exit_code

    def initialize(exit_code, message)
      @exit_code = exit_code
      super(message)
    end
  end
end
