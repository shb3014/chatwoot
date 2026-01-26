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

    # Convenience methods that delegate to the logger instance
    def self.debug(message = nil, data = {})
      log_message(:debug, message, data)
    end

    def self.info(message = nil, data = {})
      log_message(:info, message, data)
    end

    def self.warn(message = nil, data = {})
      log_message(:warn, message, data)
    end

    def self.error(message = nil, data = {})
      log_message(:error, message, data)
    end

    def self.fatal(message = nil, data = {})
      log_message(:fatal, message, data)
    end

    def self.log_message(level, message, data)
      return unless logger.send("#{level}?")

      log_entry = message.to_s
      log_entry += " #{data.inspect}" unless data.empty?

      logger.send(level, log_entry)
    end
  end
end
