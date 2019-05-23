require 'test_helper'

describe ShopifyIntegration::Product do
  # make_my_diffs_pretty!

  describe '#shopify_obj' do
    it 'without master variants' do
      config = { 'shopify_host' => 'shopify.com',
                 'status' => 200 }
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']
      api = ShopifyIntegration::ShopifyAPI.new(payload, config)
      product = ShopifyIntegration::Product.new
      product.add_wombat_obj payload, api
      product.shopify_obj['product']['variants'].count.must_equal 3
    end
  end
  describe '#shopify_obj_no_variants' do
    it 'contain sku and price' do
      config = { 'shopify_host' => 'shopify.com',
                 'status' => 200 }
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']
      api = ShopifyIntegration::ShopifyAPI.new(payload, config)
      product = ShopifyIntegration::Product.new
      product.add_wombat_obj payload, api
      product.shopify_obj_no_variants['product']['variants'].first['sku'].wont_be_nil
      product.shopify_obj_no_variants['product']['variants'].first['price'].wont_be_nil
    end
  end
end
