require 'test_helper'

describe ShopifyIntegration::Variant do
  # make_my_diffs_pretty!

  describe '#shopify_obj' do
    it 'return with inventory' do
      payload = parse_fixture('product_payload_from_sweet.json')
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload['product']['variants'].first
      variant.shopify_obj['variant']['inventory_management'].wont_be_nil
      variant.shopify_obj['variant']['quantity'].wont_be_nil
    end
    it 'return without inventory if not inventory' do
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']['variants']
        .first
      payload['inventory_management'] = false
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload
      variant.shopify_obj['variant']['inventory_management'].must_be_nil
      variant.shopify_obj['variant']['quantity'].must_be_nil
    end

    it 'should be with options' do
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']['variants']
        .first
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload
      option1 = variant.option_types.first
      option2 = variant.option_types.second
      variant.options['option1'].must_equal 'none'
      variant.options['option2'].must_equal payload['options'][option2]
    end
  end
end
