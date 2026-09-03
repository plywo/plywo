source "https://rubygems.org"

ruby "3.4.10"

gem "rails", "8.1.3.1"
gem "pg", "~> 1.5"
gem "puma", ">= 6.0"
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end
