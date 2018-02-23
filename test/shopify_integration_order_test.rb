require 'test_helper'

describe ShopifyIntegration::Order do
  # make_my_diffs_pretty!

  def create_order_from(payload)
    config = { 'shopify_host' => 'shopify.com',
               'status' => 200 }
    api = ShopifyIntegration::ShopifyAPI.new(payload, config)
    order = ShopifyIntegration::Order.new
    order.add_shopify_obj payload, api
    order.wombat_obj
  end

  describe '#wombat_obj' do
    it 'return with refund adjustments' do
      payload = parse_fixture('shopify_order_with_refund.json')
      wombat_obj = create_order_from(payload)

      refund = payload['refunds'].first['transactions'].first['amount'].to_f

      wombat_obj.wont_be_nil
      wombat_obj['adjustments']
        .select { |adj| adj['name'] == 'Refunded' }
        .first['value']
        .must_equal refund * -1
    end

    it 'return fulfilled status' do
      payload = parse_fixture('shopify_order_fulfilled.json')
      wombat_obj = create_order_from(payload)
      wombat_obj.wont_be_nil
      wombat_obj['status'].must_equal 'fulfilled'
    end

    it 'return with tax_lines' do
      payload = parse_fixture('shopify_order_with_refund.json')
      wombat_obj = create_order_from(payload)
      wombat_obj.wont_be_nil
      wombat_obj['tax_lines'].count.must_equal 2
    end

    it 'return with tax_lines for shipping and line items' do
      payload = parse_fixture('shopify_order_with_shipment.json')
      wombat_obj = create_order_from(payload)
      wombat_obj.wont_be_nil
      wombat_obj['line_items'].first['tax_lines'].count.must_equal 2
      wombat_obj['shipping_lines'].first['tax_lines'].count.must_equal 2
    end

    it 'create fulfillments on fulfilled order' do
      payload = parse_fixture('shopify_order_fulfilled.json')
      wombat_obj = create_order_from(payload)
      wombat_obj.wont_be_nil
      wombat_obj['fulfillments'].wont_be_nil
    end
  end
end
