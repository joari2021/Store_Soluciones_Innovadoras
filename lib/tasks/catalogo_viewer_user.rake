namespace :users do
  desc "Create or update the catalog viewer user"
  task create_catalog_viewer: :environment do
    username = "max"
    email = "max@catalogo.local"
    password = "max"

    business = Business.order(:id).first
    unless business
      puts "No business found. Create a business first."
      exit 1
    end

    user = User.find_or_initialize_by(username: username)
    user.email = email if user.email.to_s.strip.empty?
    user.full_name = "Max" if user.full_name.to_s.strip.empty?
    user.active = true
    user.admin = false
    user.personal = false if user.respond_to?(:personal)
    user.business_id = business.id
    user.password = password
    user.password_confirmation = password

    begin
      user.save!
    rescue ActiveRecord::RecordInvalid
      user.password = nil
      user.password_confirmation = nil
      user.password_digest = BCrypt::Password.create(password)
      user.save!(validate: false)
    end

    assignment = BusinessUserAssignment.find_or_initialize_by(user: user, business: business)
    assignment.authorization_level = "none"
    assignment.customer_access_level = "catalog_viewer"
    assignment.active = true
    assignment.save!

    puts "Catalogo viewer listo: #{user.username} / #{password}"
  end
end
