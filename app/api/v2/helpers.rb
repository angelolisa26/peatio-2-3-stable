# frozen_string_literal: true

module API
  module V2
    module Helpers
      extend Memoist

      def authorize!(*args)
        Abilities.new(current_user).authorize!(*args)
      rescue StandardError
        error!({ errors: ['admin.ability.not_permitted'] }, 403)
      end

      def authenticate!
        current_user || raise(Peatio::Auth::Error)
      end

      def set_ets_context!
        return unless defined?(Raven)

        if current_user
          Raven.user_context(
            email: current_user.email,
            uid: current_user.uid,
            role: current_user.role
          )
        end
        Raven.tags_context(
          peatio_version: Peatio::Application::VERSION
        )
      end

      def deposits_must_be_permitted!
        if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_DEPOSIT').to_i
          error!({ errors: ['account.deposit.not_permitted'] }, 403)
        end
      end

      def withdraws_must_be_permitted!
        if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_WITHDRAW').to_i
          error!({ errors: ['account.withdraw.not_permitted'] }, 403)
        end
      end

      def trading_must_be_permitted!
        if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_TRADING').to_i
          error!({ errors: ['market.trade.not_permitted'] }, 403)
        end
      end

      def withdraw_api_must_be_enabled!
        if ENV.false?('ENABLE_ACCOUNT_WITHDRAWAL_API')
          error!({ errors: ['account.withdraw.disabled_api'] }, 422)
        end
      end

      def current_user
        # JWT authentication provides member email.
        if env.key?('api_v2.authentic_member_email')
          # TODO: UID should be used for member identify.
          Member.find_by_email(env['api_v2.authentic_member_email'])
        end
      end
      memoize :current_user

      def current_market
        ::Market.enabled.find_by_id(params[:market])
      end
      memoize :current_market

      def format_ticker(ticker)
        permitted_keys = %i[buy sell low high open last volume
                            avg_price price_change_percent]

        # Add vol for compatibility with old API.
        formatted_ticker = ticker.slice(*permitted_keys)
                                 .merge(vol: ticker[:volume])
        { at: ticker[:at],
          ticker: formatted_ticker }
      end

      def paginate(collection, include_total = true)
        per_page = params[:limit] || Kaminari.config.default_per_page
        per_page = [per_page.to_i, Kaminari.config.max_per_page].compact.min

        result = if collection.is_a?(::ActiveRecord::Relation)
                   collection.page(params[:page].to_i).per(per_page)
                 elsif collection.is_a?(Array)
                   Kaminari.paginate_array(collection).page(params[:page].to_i).per(per_page)
                 end
        result.tap do |data|
          header 'Total',       data.total_count.to_s if include_total
          header 'Per-Page',    data.limit_value.to_s
          header 'Page',        data.current_page.to_s
        end
      end
    end
  end
end
