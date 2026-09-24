module CustomExceptions::ScanSolo
end

class CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured < StandardError; end
class CustomExceptions::ScanSolo::CadenceDefinitionMissing < StandardError; end
class CustomExceptions::ScanSolo::Forbidden < StandardError; end
