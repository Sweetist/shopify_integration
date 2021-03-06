require 'test_helper'

class ShopifyIntegrationTest < Minitest::Test
  include Rack::Test::Methods
  make_my_diffs_pretty!
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

  def test_respond_not_support
    payload = load_fixture('get_orders_request_from_sweet.json')
    post '/update_orders', payload

    assert last_response.ok?
    logs_body = JSON.parse(last_response.body)['logs'].first
    assert_equal logs_body['message'], I18n.t('not_support')
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

  def test_respond_for_get_payments
    payload = load_fixture('get_transactions_request_from_sweet.json')
    response = load_fixture('shopify_transactions.json')

    RestClient.stub :get, response do
      post '/get_payments', payload
    end

    assert last_response.ok?
    payments = JSON.parse(last_response.body)['payments'].first
    params_body = JSON.parse(last_response.body)['parameters']
    assert_equal params_body['sync_type'], 'shopify'
    refute_nil payments['amount']
    refute_empty payments['status']
    refute_empty payments['payment_method']
    refute_nil payments['id']
  end

  def test_respond_for_get_refunds
    payload = load_fixture('get_refunds_request_from_sweet.json')
    response = load_fixture('shopify_refunds.json')

    RestClient.stub :get, response do
      post '/get_refunds', payload
    end

    assert last_response.ok?
    refunds = JSON.parse(last_response.body)['refunds'].first
    params_body = JSON.parse(last_response.body)['parameters']
    assert_equal params_body['sync_type'], 'shopify'
    refute_nil refunds['restock']
    refute_empty refunds['refund_line_items']
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

  # def test_respond_add_product
  #   payload = load_fixture('add_product_payload.json')
  #   response_products = load_fixture('get_products_from_shopify.json')
  #   response_add = load_fixture('add_product_from_shopify.json')

  #   RestClient.stub :get, response_products do
  #     RestClient.stub :post, response_add do
  #       post '/add_shipment', payload
  #     end
  #   end
  #   assert last_response.ok?
  #   params_body = JSON.parse(last_response.body)['parameters']
  #   assert_equal params_body['sync_type'], 'shopify'
  #   refute_nil params_body['sync_action']
  # end

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
