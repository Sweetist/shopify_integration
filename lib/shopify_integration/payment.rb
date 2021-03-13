module ShopifyIntegration
  class Payment
    # memoize payment details from Shopify
    def add_shopify_obj(shopify_transaction)
      @id = shopify_transaction.shopify_id
      @status = shopify_transaction.status
      @amount = shopify_transaction.amount
      @payment_method = shopify_transaction.gateway
      @kind = shopify_transaction.kind
      self
    end

    # hashed payemnt details to send to wombat (and finally to Sweet)
    def wombat_obj
      {
        'id' => @id,
        'kind' => @kind,
        'status' => @status,
        'amount' => @amount.to_f,
        'payment_method' => @payment_method
      }
    end
  end
end
