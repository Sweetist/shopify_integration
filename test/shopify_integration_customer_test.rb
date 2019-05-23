require 'test_helper'

describe ShopifyIntegration::Variant do
  # make_my_diffs_pretty!

  describe '#shopify_obj' do
    it 'return with inventory' do
      config = { 'shopify_host' => 'shopify.com',
                 'status' => 200 }
      payload = parse_fixture('shopify_customer.json')
      api = ShopifyIntegration::ShopifyAPI.new(payload, config)
      order = ShopifyIntegration::Customer.new
      order.add_shopify_obj payload, api
      wombat_obj = order.wombat_obj
      wombat_obj['tax_exempt'].wont_be_nil
      wombat_obj['tax_exempt'].must_equal true
    end
  end
end
