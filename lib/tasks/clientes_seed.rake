namespace :clientes do
  desc 'Create demo clients for pagination'
  task seed_demo: :environment do
    count = (ENV['COUNT'] || 40).to_i
    business_id = ENV['BUSINESS_ID'].presence || Business.first&.id

    if business_id.blank?
      puts 'No business found. Create one or pass BUSINESS_ID=<id>.'
      exit 1
    end

    business = Business.find(business_id)
    start_index = business.clientes.count + 1
    created = 0

    count.times do |i|
      seq = start_index + i
      document_number = (10_000_000 + seq).to_s
      name = "Cliente Demo #{seq.to_s.rjust(2, '0')}"
      phone = "0412#{rand(1_000_000..9_999_999)}"
      address = "Calle #{seq}, Sector Demo"

      cliente = business.clientes.find_or_initialize_by(
        document_type: 'V',
        document_number: document_number
      )
      cliente.name = name
      cliente.phone = phone
      cliente.address = address

      if cliente.new_record?
        cliente.save!
        created += 1
      end
    end

    puts "Created #{created} demo clients for business #{business.id}."
  end
end
