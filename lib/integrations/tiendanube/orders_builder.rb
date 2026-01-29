class Integrations::Tiendanube::OrdersBuilder
  MAX_ORDERS = 20
  CACHE_TTL = 3.minutes

  def initialize(hook:, contact:)
    @hook = hook
    @contact = contact
  end

  def fetch_orders
    return [] unless searchable?

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      orders = fetch_recent_orders
      matched = match_orders(orders)

      matched.first(MAX_ORDERS).map { |order| normalize_order(order) }
    end
  end

  private

  attr_reader :hook, :contact

  def cache_key
    [
      'tiendanube',
      'orders',
      hook.reference_id,
      contact.id,
      contact.email.presence || contact.phone_number
    ].join(':')
  end

  def searchable?
    contact.email.present? || contact.phone_number.present?
  end

  def match_orders(orders)
    if contact.email.present?
      orders.select { |o| email_match?(o) }
    elsif contact.phone_number.present?
      orders.select { |o| phone_match?(o) }
    else
      []
    end
  end

  def email_match?(order)
    order['contact_email'].to_s.casecmp?(contact.email.to_s)
  end

  def phone_match?(order)
    normalize_phone(order.dig('shipping_address', 'phone')) ==
      normalize_phone(contact.phone_number)
  end

  def fetch_recent_orders
    response = connection.get('orders') do |req|
      req.params['limit'] = MAX_ORDERS
      req.params['fields'] =
        'id,number,status,payment_status,created_at,contact_email,shipping_address,total,currency'
    end

    if response.status == 200
      response.body || []
    else
      Rails.logger.error("Response status error: #{response.status}")
      []
    end
  rescue Faraday::TimeoutError
    raise Integrations::Tiendanube::ApiError, 'Timeout'
  rescue Faraday::ConnectionFailed => e
    raise Integrations::Tiendanube::ApiError, e.message
  end

  def connection
    @connection ||= Faraday.new(
      url: "https://api.tiendanube.com/v1/#{store_id}"
    ) do |f|
      f.request :json
      f.response :json
    end.tap do |conn|
      conn.headers['Authentication'] = "bearer #{hook.access_token}"
      conn.headers['User-Agent'] = 'Chatwoot (integrations@chatwoot.com)'
      conn.headers['Content-Type'] = 'application/json'
    end
  end

  def store_id
    hook.reference_id
  end

  def normalize_order(order)
    {
      id: order['number'] || order['id'],
      external_id: order['id'],
      financial_status: map_financial_status(order),
      fulfillment_status: map_fulfillment_status(order),
      total_price: order['total'],
      currency: order['currency'],
      created_at: order['created_at'],
      admin_url: admin_order_url(order['id'])
    }
  end

  def admin_order_url(order_id)
    "https://tiendatest176.mitiendanube.com/admin/orders/#{order_id}"
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def map_financial_status(order)
    case order['payment_status']
    when 'paid'
      'paid'
    when 'pending'
      'pending'
    when 'cancelled', 'refunded'
      'refunded'
    else
      'unknown'
    end
  end

  def map_fulfillment_status(order)
  fulfillments = order['fulfillments'] || []

  return 'unfulfilled' if fulfillments.empty?

  statuses = fulfillments.map { |f| f['status'] }

  if statuses.include?('DISPATCHED')
    'fulfilled'
  else
    'partial'
  end
end
end
