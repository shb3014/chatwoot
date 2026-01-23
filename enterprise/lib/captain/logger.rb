module Captain
  class Logger
    DEFAULT_LEVEL = ::Logger::INFO

    def self.logger
      @logger ||= build_logger
    end

    def self.build_logger
      log_path = Rails.root.join('log/captain.log')
      logger = ActiveSupport::Logger.new(log_path)
      logger.level = resolve_level
      logger.formatter = ::Logger::Formatter.new
      logger
    end

    def self.resolve_level
      level = ENV['CAPTAIN_LOG_LEVEL']&.downcase
      return DEFAULT_LEVEL if level.blank?

      ::Logger.const_get(level.upcase)
    rescue NameError
      DEFAULT_LEVEL
    end
  end
end
