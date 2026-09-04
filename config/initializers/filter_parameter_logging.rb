Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,
  :pull_request, :check_run, :repository, :organization, :sender, :installation, :changes
]
