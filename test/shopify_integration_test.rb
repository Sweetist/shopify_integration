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

  def test_respond_ok_for_callback
    payload = load_fixture('create_order_callback.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      post '/order_callback', payload
    end

    assert last_response.ok?
    # parsed_body = JSON.parse(last_response.body)
    # order_body = parsed_body['orders'].first

    # assert parsed_body['orders'].size == 1
    # assert_equal order_body['id'], 'R1-R572547556'
  end

  def test_respond_ok_for_create_product_callback
    payload = load_fixture('create_product_callback.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      post '/product_callback', payload
    end

    assert last_response.ok?
    # parsed_body = JSON.parse(last_response.body)
    # order_body = parsed_body['orders'].first

    # assert parsed_body['orders'].size == 1
    # assert_equal order_body['id'], 'R1-R572547556'
  end

  def test_respond_ok_for_create_customer_callback
    payload = load_fixture('create_customer_callback.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      post '/customer_callback', payload
    end

    assert last_response.ok?
    # parsed_body = JSON.parse(last_response.body)
    # order_body = parsed_body['orders'].first

    # assert parsed_body['orders'].size == 1
    # assert_equal order_body['id'], 'R1-R572547556'
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
