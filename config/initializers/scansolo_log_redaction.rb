# RF-88 / RNF-07: no secret-shaped value (API key/token pattern) may appear
# in application logs. Rails' `filter_parameters` (config/initializers/
# filter_parameter_logging.rb) only scrubs structured param hashes; it does
# not touch a secret interpolated into a free-form log message (e.g. an
# error string). This wraps the app logger's formatter so every rendered log
# line passes through ScanSolo::AiTurn::PromptRedactor first, regardless of
# which code produced it.
#
# The base formatter is `Rails.logger`'s existing `ActiveSupport::
# TaggedLogging::Formatter` instance, which ActiveJob/Rack relies on for
# `current_tags`/`tagged`/`push_tags`/`pop_tags`. Replacing it outright with
# a bare proc breaks that tagging contract, so this delegates everything
# except `#call` to the original formatter instead.
require 'delegate'

Rails.application.config.after_initialize do
  next if Rails.logger.blank?

  base_formatter = Rails.logger.formatter || ActiveSupport::Logger::SimpleFormatter.new

  redacting_formatter = SimpleDelegator.new(base_formatter)
  def redacting_formatter.call(severity, datetime, progname, msg)
    __getobj__.call(severity, datetime, progname, ScanSolo::AiTurn::PromptRedactor.call(msg.to_s))
  end

  Rails.logger.formatter = redacting_formatter
end
