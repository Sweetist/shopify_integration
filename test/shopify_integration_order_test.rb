require 'test_helper'

describe ShopifyIntegration::Order do
  # make_my_diffs_pretty!

  describe '#wombat_obj' do
    it 'return with refund adjustments' do
      config = { 'shopify_host' => 'shopify.com',
                 'status' => 200 }
      payload = parse_fixture('shopify_order_with_refund.json')
      api = ShopifyIntegration::ShopifyAPI.new(payload, config)
      order = ShopifyIntegration::Order.new
      order.add_shopify_obj payload, api
      wombat_obj = order.wombat_obj
      refund = payload['refunds'].first['transactions'].first['amount'].to_f

      wombat_obj.wont_be_nil
      wombat_obj['adjustments']
        .select { |adj| adj['name'] == 'Refund' }
        .first['value']
        .must_equal refund
    end
  end
end
