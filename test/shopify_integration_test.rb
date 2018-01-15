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

  def test_respond_ok_for_order_callback
    payload = load_fixture('order_object.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      header 'X_SHOPIFY_SHOP_DOMAIN', 'test.com'
      post '/order_callback', payload
    end

    assert last_response.ok?
    order_body = JSON.parse(last_response.body)['orders'].first
    params_body = JSON.parse(last_response.body)['parameters']
    refute_nil order_body['line_items']
    assert_equal params_body['sync_type'], 'shopify'
    assert_equal order_body['status'], 'completed'
  end

  def test_respond_ok_for_create_product_callback
    payload = load_fixture('product_object.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      header 'X_SHOPIFY_SHOP_DOMAIN', 'test.com'
      post '/product_callback', payload
    end

    assert last_response.ok?
    product_body = JSON.parse(last_response.body)['products'].first
    inventories_body = JSON.parse(last_response.body)['inventories']
    assert_equal product_body['id'], '788032119674292900'
    refute_nil inventories_body
  end

  def test_respond_ok_for_create_customer_callback
    payload = load_fixture('customer_object.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      header 'X_SHOPIFY_SHOP_DOMAIN', 'test.com'
      post '/customer_callback', payload
    end

    assert last_response.ok?
    parsed_body = JSON.parse(last_response.body)
    customer_body = parsed_body['customers'].first

    assert_equal customer_body['id'], '706405506930370000'
  end

  def test_respond_ok_for_get_orders
    payload = load_fixture('get_orders_request_from_sweet.json')
    response = load_fixture('get_orders_response_from_shopify.json')

    RestClient.stub :get, response do
      post '/get_orders', payload
    end

    assert last_response.ok?
    order_body = JSON.parse(last_response.body)['orders'].first
    params_body = JSON.parse(last_response.body)['parameters']
    assert_equal params_body['sync_type'], 'shopify'
    refute_nil order_body['line_items']
    refute_empty order_body['shopify_id']
  end

  def test_respond_right_cancel_status
    payload = load_fixture('cancel_order_shopify_payload.json')
    mock = Minitest::Mock.new
    def mock.code; 202; end

    HTTParty.stub :post, mock do
      header 'X_SHOPIFY_SHOP_DOMAIN', 'test.com'
      post '/order_callback', payload
    end

    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal response['orders'].first['status'], 'cancelled'
  end

  def test_respond_add_shipment
    payload = load_fixture('add_shipment_order_shopify_payload.json')
    response = load_fixture('get_orders_response_from_shopify.json')

    RestClient.stub :post, response do
      post '/add_shipment', payload
    end

    assert last_response.ok?
    params_body = JSON.parse(last_response.body)['parameters']
    assert_equal params_body['sync_type'], 'shopify'
    refute_nil params_body['sync_action']
  end

  # def test_endpoint
  #   get '/test_endpoint'
  #   assert last_response.ok?
  # end

  # def test_get_products
  #   post '/get_products'
  #   assert last_response.ok?
  # end


end
