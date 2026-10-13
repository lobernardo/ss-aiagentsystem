# CT-04 / RF-09 / RF-11 / RNF-02 / RNF-03: converts a rendered `.docx` into a
# PDF through the internal Gotenberg service
# (`POST #{SCANSOLO_GOTENBERG_URL}/forms/libreoffice/convert`, 1 file in the
# `files` field). Fixed internal host from the env, so no `SafeFetch`.
#
# Never runs inside an open transaction. Timeout, connection error and 5xx →
# GotenbergUnavailable (retried by the job); 4xx → GotenbergRejected; a 200
# that is not a PDF with at least 1 page → GotenbergInvalidPdf. Error messages
# carry only the HTTP status or error class, never a body (RNF-04).
class ScanSolo::Proposal::GotenbergClient
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  CONNECTION_ERRORS = [
    RestClient::Exceptions::Timeout, RestClient::ServerBrokeConnection, Errno::ECONNREFUSED, Errno::ECONNRESET,
    Errno::EHOSTUNREACH, SocketError
  ].freeze

  def self.convert!(docx:, filename:)
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?

    file = StringIO.new(docx)
    file.define_singleton_method(:path) { filename }
    response = RestClient::Request.execute(
      method: :post,
      url: "#{ENV.fetch('SCANSOLO_GOTENBERG_URL')}/forms/libreoffice/convert",
      payload: { multipart: true, files: file },
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    )
    pdf!(response.body)
  rescue *CONNECTION_ERRORS => e
    raise CustomExceptions::ScanSolo::GotenbergUnavailable, e.class.name
  rescue RestClient::ExceptionWithResponse => e
    raise CustomExceptions::ScanSolo::GotenbergUnavailable, "HTTP #{e.http_code}" if e.http_code.to_i >= 500

    raise CustomExceptions::ScanSolo::GotenbergRejected, "HTTP #{e.http_code}"
  end

  def self.pdf!(body)
    raise CustomExceptions::ScanSolo::GotenbergInvalidPdf, 'not_pdf' unless body.start_with?('%PDF')
    raise CustomExceptions::ScanSolo::GotenbergInvalidPdf, 'no_pages' unless PDF::Reader.new(StringIO.new(body)).page_count >= 1

    body
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    raise CustomExceptions::ScanSolo::GotenbergInvalidPdf, 'unreadable_pdf'
  end
  private_class_method :pdf!
end
