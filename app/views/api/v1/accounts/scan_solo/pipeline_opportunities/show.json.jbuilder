json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/detail'
# CT-02 / UI-07: whether the manual resend (RF-56) would be accepted.
json.quote_request_resend_available ScanSolo::Quote::ResendService.available?(@opportunity)
