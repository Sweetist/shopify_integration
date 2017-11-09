require 'test_helper'

class ShopifyIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ShopifyIntegration::Server
  end

  def test_that_it_has_a_version_number
    refute_nil ::ShopifyIntegration::VERSION
  end

  def test_respond_ok_for_root
    get '/'
    assert last_response.ok?
  end

  # def test_endpoint
  #   get '/test_endpoint'
  #   assert last_response.ok?
  # end

  # def test_get_products
  #   post '/get_products'
  #   assert last_response.ok?
  # end

  # def test_get_products
  #   post '/add_product', {some: 'data'}.to_json
  #   assert last_response.ok?
  # end

  # def test_add_shipment
  #   post '/add_shipment', {some: 'data'}.to_json
  #   assert last_response.ok?
  # end
end
