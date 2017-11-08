require 'test_helper'

class ShopifyIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ShopifyIntegration::Server
  end

  def test_that_it_has_a_version_number
    refute_nil ::ShopifyIntegration::VERSION
  end

  def test_tespond_ok_for_root
    get '/'
    assert last_response.ok?
  end
end
