json.id @contact.id
json.email @contact.email
json.name @contact.name
json.has_email @contact.email.present?
json.has_name @contact.name.present?
json.has_phone_number @contact.phone_number.present?
json.identifier @contact.identifier
