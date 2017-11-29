module Trailblazer
  module Operation::Railway
    def self.fail!     ; Circuit::Left  end
    def self.pass!     ; Circuit::Right end
    def self.fail_fast!; Activity::Magnetic::Builder::FastTrack::FailFast end
    def self.pass_fast!; Activity::Magnetic::Builder::FastTrack::PassFast end

    module End
      FailFast = Class.new(Operation::Railway::End::Failure).new(:fail_fast)
      PassFast = Class.new(Operation::Railway::End::Success).new(:pass_fast)
    end
  end
end
