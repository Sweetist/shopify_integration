require 'test_helper'

describe ShopifyIntegration::Variant do
  # make_my_diffs_pretty!

  def create_variant_from(payload, options)
    # config = { 'shopify_host' => 'shopify.com',
    #            'status' => 200 }
    # api = ShopifyIntegration::ShopifyAPI.new(payload, config)
    variant = ShopifyIntegration::Variant.new
    variant.add_shopify_obj payload, options
    variant.wombat_obj
  end
  describe '#wombat_obj' do
    it 'return right options' do
      payload = parse_fixture('shopify_product_with_options.json')
      variant = payload['variants'].first
      options = payload['options']
      wombat_obj = create_variant_from(variant, options)
      options = { 'Size' => '21', 'Color' => 'white', 'Material' => 'cotton' }
      wombat_obj['options'].must_equal options
    end
  end

  describe '#shopify_obj' do
    it 'return is_master' do
      payload = parse_fixture('product_payload_from_sweet.json')
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload['product']['variants'].first
      variant.is_master
             .must_equal true
    end
    it 'return with inventory' do
      payload = parse_fixture('product_payload_from_sweet.json')
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload['product']['variants'].first
      variant.shopify_obj['variant']['inventory_management'].wont_be_nil
      variant.shopify_obj['variant']['inventory_quantity'].wont_be_nil
    end
    it 'return without inventory if not inventory' do
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']['variants']
        .first
      payload['inventory_management'] = false
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload
      variant.shopify_obj['variant']['inventory_management'].must_be_nil
      variant.shopify_obj['variant']['inventory_quantity'].must_be_nil
    end

    it 'should be with options' do
      payload =
        parse_fixture('product_payload_from_sweet.json')['product']['variants']
        .first
      variant = ShopifyIntegration::Variant.new
      variant.add_wombat_obj payload
      option2 = variant.option_types.second
      variant.options['option1'].must_equal 'none'
      variant.options['option2'].must_equal payload['options'][option2]
    end
  end
end
