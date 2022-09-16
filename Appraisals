# frozen_string_literal: true

appraise 'rails_5_1' do
  gem 'rails', '~> 5.1.0'
end

appraise 'rails_5_2' do
  gem 'rails', '~> 5.2.0'
end

appraise 'rails_6_0' do
  gem 'rails', '~> 6.0.0'
end

appraise 'rails_6_1' do
  gem 'rails', '~> 6.1.0'

  # https://stackoverflow.com/questions/70500220/rails-7-ruby-3-1-loaderror-cannot-load-such-file-net-smtp
  gem 'net-smtp', require: false
  gem 'net-imap', require: false
  gem 'net-pop', require: false
end

appraise 'rails_7_0' do
  gem 'rails', '~> 7.0'
end
