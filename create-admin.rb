# Creates the first user from ADMIN_EMAIL and ADMIN_PASSWORD, so signup can stay
# closed from the first boot. Runs on every start through `rails runner` and does
# nothing once any user exists: after that, users change their password in the app.
email = ENV["ADMIN_EMAIL"].to_s.strip
password = ENV["ADMIN_PASSWORD"].to_s

if User.exists?
  puts "[railway-entrypoint] Users exist; ADMIN_EMAIL and ADMIN_PASSWORD are not used."
elsif email.empty? || password.length < 8
  warn "[railway-entrypoint] WARNING: no users yet, and ADMIN_EMAIL is empty or ADMIN_PASSWORD has fewer " \
       "than 8 characters. Set both, then redeploy, to create the first user."
else
  ActiveRecord::Base.transaction do
    User.lock_first_user_role!
    family = Family.create!
    family.users.create!(email: email, password: password, role: User.role_for_new_family_creator)
  end
  puts "[railway-entrypoint] Created the admin user #{email}."
end
