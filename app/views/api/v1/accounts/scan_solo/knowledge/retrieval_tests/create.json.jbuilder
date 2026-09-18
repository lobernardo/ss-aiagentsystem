json.results @response[:results] do |result|
  json.chunk_id result.chunk_id
  json.source_id result.source_id
  json.source_type result.source_type
  json.content_snippet result.content_snippet
  json.similarity_score result.similarity_score
end
json.failure_reason @response[:failure_reason]
