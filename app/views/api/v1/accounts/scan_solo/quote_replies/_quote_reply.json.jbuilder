message = quote_reply.message

json.id quote_reply.id
json.conversation_id quote_reply.conversation_id
json.message_id message.id
json.sender_email message.sender.email
json.subject message.conversation.additional_attributes.to_h['mail_subject']
json.received_at message.created_at
json.excerpt message.content.to_s.first(200)
json.kind quote_reply.kind
json.quote_request_id quote_reply.quote_request_id
