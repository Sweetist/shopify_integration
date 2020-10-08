module ShopifyIntegration
  class Variant
    # The keys here represent the weight units in Shopify
    WEIGHT_UNIT_MAPPER = {
      'g' => 'gm',
      'kg' => 'kg',
      'oz' => 'oz',
      'lb' => 'lb',
    }.freeze

    attr_reader :shopify_id, :shopify_parent_id, :quantity, :images,
                :sku, :price, :options, :shipping_category, :name,
                :inventory_management, :option_types, :is_master

    # memoize attributes from the shopify variant
    def add_shopify_obj shopify_variant, shopify_options
      @shopify_id = shopify_variant['id']
      @shopify_parent_id = shopify_variant['product_id']
      @name = shopify_variant['title']
      @sku = shopify_variant['sku']
      @weight = shopify_variant['weight']
      @weight_unit = shopify_variant['weight_unit']
      @inventory_management = shopify_variant['inventory_management']
      @price = shopify_variant['price'].to_f
      @shipping_category = shopify_variant['requires_shipping'] ?
                            'Shipping Required' : 'Shipping Not Required'
      @quantity = shopify_variant['inventory_quantity'].to_i

      @images = Array.new
      unless shopify_variant['images'].nil?
        shopify_variant['images'].each do |shopify_image|
          image = Image.new
          image.add_shopify_obj shopify_image
          @images << image
        end
      end

      @options = Hash.new
      shopify_variant.keys.grep(/option\d*/).each do |option_name|
        if !shopify_variant[option_name].nil?
          option_position = option_name.scan(/\d+$/).first.to_i
          real_option_name = shopify_options.select {|option| option['position'] == option_position }.first['name']
          @options[real_option_name] = shopify_variant[option_name]
        end
      end

      self
    end

    # memoize the attributes coming from wombat (aka from Sweet)
    def add_wombat_obj wombat_variant
      @shopify_id = wombat_variant['shopify_id'] || wombat_variant['sync_id']
      @price = wombat_variant['price'].to_f
      @sku = wombat_variant['sku']
      @quantity = wombat_variant['quantity'].to_i
      @weight = wombat_variant['weight']
      @is_master = wombat_variant['is_master']
      @weight_unit = wombat_variant['weight_unit']
      @inventory_management = wombat_variant['inventory_management']
      option_types_all = wombat_variant['option_types']
      @option_types = option_types_all[0..2] if option_types_all
      @options = {}

      unless wombat_variant['options'].nil?
        @option_types.each_with_index do |value, index|
          val = wombat_variant['options'][value] || 'none'
          @options['option' + (index + 1).to_s] = val
        end
      end

      @images = []
      unless wombat_variant['images'].nil?
        wombat_variant['images'].each do |wombat_image|
          image = Image.new
          image.add_wombat_obj wombat_image
          @images << image
        end
      end

      self
    end

    def inventory_hash
      return {'inventory_management' => nil} unless inventory_management
      { 'inventory_management' => 'shopify',
        'inventory_quantity' => quantity }
    end

    # hashed object to send to Shopify (to create/update object in Shopify)
    def shopify_obj
      {
        'variant' => {
          'price' => @price,
          'sku' => @sku,
          'weight' => @weight,
          'weight_unit' => normalized_weight_units(@weight_unit, :to_shopify),
        }.merge(@options)
          .merge(inventory_hash)
      }
    end

    # hashed object to send to wombat (to create/update object in Sweet)
    def wombat_obj
      {
        'sku' => @sku,
        'shopify_id' => @shopify_id.to_s,
        'shopify_parent_id' => @shopify_parent_id.to_s,
        'shipping_category' => @shipping_category,
        'price' => @price,
        'weight' => @weight,
        'weight_units' => normalized_weight_units(@weight_unit, :to_wombat),
        'quantity' => @quantity,
        'options' => @options,
        'inventory_management' => @inventory_management
      }
    end

    def normalized_weight_units(unit, where_to)
      if where_to == :to_wombat
        WEIGHT_UNIT_MAPPER[unit]
      else
        WEIGHT_UNIT_MAPPER.key(unit)
      end
    end
  end
end
