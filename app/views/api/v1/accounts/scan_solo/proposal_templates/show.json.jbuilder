# RF-18: metadata only -- never the file content nor a blob URL.
if @template
  json.template do
    json.id @template.id
    json.filename @template.filename
    json.byte_size @template.byte_size
    json.sha256 @template.sha256
    if @template.uploaded_by
      json.uploaded_by do
        json.id @template.uploaded_by.id
        json.name @template.uploaded_by.name
      end
    else
      json.uploaded_by nil
    end
    json.uploaded_at @template.created_at
  end
else
  json.template nil
end
