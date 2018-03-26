module ShopifyIntegration
  class Payment
    def add_shopify_obj(shopify_transaction)
      @id = shopify_transaction.shopify_id
      @status = shopify_transaction.status
      @amount = shopify_transaction.amount
      @payment_method = shopify_transaction.gateway

      self
    end

    def wombat_obj
      {
        'id' => @id,
        'status' => @status,
        'amount' => @amount.to_f,
        'payment_method' => @payment_method
      }
    end
  end
end
