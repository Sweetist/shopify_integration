module ShopifyIntegration
  class Inventory

    attr_reader :shopify_id, :sku, :quantity

    def add_obj variant
      @sku = variant.sku
      @shopify_id = variant.shopify_id
      @shopify_parent_id = variant.shopify_parent_id
      @quantity = variant.quantity
      @inventory_management = variant.inventory_management
      self
    end

    def add_wombat_obj wombat_inventory
      @sku = wombat_inventory['product_id']
      @quantity = wombat_inventory['quantity']
      unless wombat_inventory['shopify_id'].nil?
        @shopify_id = wombat_inventory['shopify_id']
      end

      self
    end

    def wombat_obj
      {
        'id' => @sku,
        'product_id' => @sku,
        'shopify_id' => @shopify_id,
        'shopify_parent_id' => @shopify_parent_id.to_s,
        'quantity' => @quantity,
        'inventory_management' => @inventory_management
      }
    end

    def shopify_obj
      {}
    end
  end
end
