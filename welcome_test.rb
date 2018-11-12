require 'rails_helper'

RSpec.describe 'Welcome page' do
  it 'displays a simple welcome message' do
    visit root_path
    expect(page).to have_content('welcome!')
  end
end
