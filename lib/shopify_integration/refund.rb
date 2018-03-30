module ShopifyIntegration
  class Refund
    attr_reader :data

    def add_shopify_obj(shopify_object, _shopify_api)
      @data = shopify_object
      self
    end

    def wombat_obj
      data
    end
  end
end
