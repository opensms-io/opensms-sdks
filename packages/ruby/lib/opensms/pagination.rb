# frozen_string_literal: true

module Opensms
  # Auto-pagination over cursor lists. Mixed into {Opensms::Client}.
  module Pagination
    # Lazily walk every page of a cursor list, feeding +next_cursor+ back as
    # +cursor+ until it is nil.
    #
    # @example
    #   client.paginate(:messages, :list, limit: 50).each { |m| puts m[:id] }
    #   client.paginate(:batches, :list_items, batch_id, limit: 100).first(10)
    #   client.paginate(client.contacts.method(:list), limit: 200).to_a
    #
    # @overload paginate(resource, method, *args, **params)
    #   @param resource [Symbol] a client resource name (:messages, ...)
    #   @param method [Symbol] a list method returning {Opensms::Page}
    # @overload paginate(callable, *args, **params)
    #   @param callable [#call] returns {Opensms::Page}
    # @return [Enumerator<Hash>]
    def paginate(target, *args, **params)
      fn = target.respond_to?(:call) ? target : public_send(target).method(args.shift)
      Enumerator.new do |yielder|
        query = params.dup
        loop do
          page = fn.call(*args, **query)
          page.items.each { |item| yielder << item }
          break if page.next_cursor.nil? || page.next_cursor.to_s.empty?

          query = query.merge(cursor: page.next_cursor)
        end
      end.lazy
    end
  end
end
