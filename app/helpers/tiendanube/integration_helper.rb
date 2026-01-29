module Tiendanube::IntegrationHelper
  def create_hook!(account:, code:)
    token_response = exchange_tiendanube_code_for_token(code)

    account.hooks.create!(
      app_id: 'tiendanube',
      access_token: token_response['access_token'],
      reference_id: token_response['user_id'],
      status: 'enabled'
    )
  end

  private

  def exchange_tiendanube_code_for_token(code)
    response = HTTParty.post(
      'https://www.tiendanube.com/apps/authorize/token',
      headers: { 'Content-Type' => 'application/json' },
      body: {
        client_id: GlobalConfigService.load('TIENDANUBE_CLIENT_ID', nil),
        client_secret: GlobalConfigService.load('TIENDANUBE_CLIENT_SECRET', nil),
        grant_type: 'authorization_code',
        code: code
      }.to_json
    )

    parsed = JSON.parse(response.body)

    unless parsed['access_token'].present? && parsed['user_id'].present?
      raise StandardError, "Tiendanube OAuth failed: #{parsed}"
    end

    parsed
  rescue JSON::ParserError => e
    Rails.logger.error("Tiendanube token parse error: #{e.message}")
    raise StandardError, 'Invalid Tiendanube OAuth response'
  rescue HTTParty::Error, SocketError => e
    Rails.logger.error("Tiendanube OAuth request error: #{e.message}")
    raise StandardError, 'Tiendanube OAuth request failed'
  end
end
