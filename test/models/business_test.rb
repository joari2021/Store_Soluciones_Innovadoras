require 'test_helper'

class BusinessTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'assigns neon blue as default theme profile' do
    business = Business.new(name: 'Negocio tema')

    assert business.valid?
    assert_equal 'neon_blue', business.theme_profile
  end

  test 'exposes theme metadata and css variables for the assigned profile' do
    business = Business.new(name: 'Negocio tema', theme_profile: 'neon_blue')

    assert_equal 'Azul claro + cyan', business.theme_label
    assert_match(/cyan electrico/i, business.theme_description)
    assert_includes business.theme_css_variables, '--theme-sky-500: #0ea5e9'
    assert_includes business.theme_preview_style, 'linear-gradient'
    assert_includes Business.theme_profile_options, ['Azul claro + cyan', 'neon_blue']
    assert_includes Business.theme_profile_options, ['Cyan electrico', 'electric_cyan']
    assert_includes Business.theme_profile_options, ['Neon arcade', 'neon_arcade']
  end
end
