# coding: utf-8
module OrderQuery
  module SQL
    # Build where clause for searching around a record in an order space
    class Where
      attr_reader :point

      # @param [OrderQuery::Point] point
      def initialize(point)
        @point      = point
        @conditions = point.space.conditions
      end

      # Join condition pairs with OR, and nest within each other with AND
      # @param [:before or :after] side
      # @return [query, parameters] WHERE conditions matching records strictly before / after this one
      #   sales < 5 OR
      #   sales = 5 AND (
      #     invoice < 3 OR
      #     invoices = 3 AND (
      #       ... ))
      def build(side)
        # generate pairs of terms such as sales < 5, sales = 5
        parts = @conditions.map { |cond|
          [where_side(cond, side, true), where_tie(cond)].reject { |x| x == WHERE_IDENTITY }
        }
        # group pairwise with OR, and nest with AND
        query = foldr_terms parts.map { |terms| join_terms 'OR'.freeze, *terms }, 'AND'.freeze
        if ::OrderQuery.wrap_top_level_or
          # wrap in a redundant AND clause for performance
          query = wrap_top_level_or query, parts, side
        end
        query
      end

      protected

      # @param [String] sql_operator SQL operator
      # @return [query, params] terms right-folded with sql_operator
      #   [A, B, C, ...] -> A AND (B AND (C AND ...))
      def foldr_terms(terms, sql_operator)
        foldr_i WHERE_IDENTITY, terms do |a, b, i|
          join_terms sql_operator, a, (i > 1 ? wrap_term_with_parens(b) : b)
        end
      end

      # joins terms with an operator
      # @return [query, parameters]
      def join_terms(op, *terms)
        [terms.map(&:first).reject(&:empty?).join(" #{op} "), terms.map(&:second).reduce([], :+)]
      end

      def wrap_term_with_parens(t)
        ["(#{t[0]})", t[1]]
      end

      # Wrap top level OR clause to help DB with using the index
      # Before:
      #   (sales < 5 OR
      #     (sales = 5 AND ...))
      # After:
      #   (sales <= 5 AND
      #    (sales < 5 OR
      #       (sales = 5 AND ...)))
      # Read more at https://github.com/glebm/order_query/issues/3
      def wrap_top_level_or(query, pairs, side)
        top_pair_idx = pairs.index(&:present?)
        if top_pair_idx &&
            (top_pair = pairs[top_pair_idx]).length == 2 &&
            top_pair.first != (redundant_cond = where_side(@conditions[top_pair_idx], side, false))
          join_terms 'AND'.freeze, redundant_cond, wrap_term_with_parens(query)
        else
          query
        end
      end

      # @return [query, params] tie-breaker unless condition is unique
      def where_tie(cond)
        if cond.unique?
          WHERE_IDENTITY
        else
          where_eq(cond)
        end
      end

      # @param [:before or :after] side
      # @return [query, params] return query conditions for attribute values before / after the current one
      def where_side(cond, side, strict = true, value = point.value(cond))
        if cond.order_enum
          values = cond.enum_side(value, side, strict)
          if cond.complete? && values.length == cond.order_enum.length
            WHERE_IDENTITY
          else
            where_in cond, values
          end
        else
          where_ray cond, value, side, strict
        end
      end

      def where_in(cond, values)
        case values.length
          when 0
            WHERE_IDENTITY
          when 1
            where_eq cond, values[0]
          else
            ["#{cond.column_name} IN (?)".freeze, [values]]
        end
      end

      def where_eq(cond, value = point.value(cond))
        [%Q(#{cond.column_name} = ?).freeze, [value]]
      end

      def where_ray(cond, from, mode, strict = true)
        ops = %w(< >)
        ops = ops.reverse if mode == :after
        op  = {asc: ops[0], desc: ops[1]}[cond.order || :asc]
        ["#{cond.column_name} #{op}#{'=' unless strict} ?".freeze, [from]]
      end

      WHERE_IDENTITY = [''.freeze, [].freeze].freeze

      private

      # Inject with index from right to left, turning [a, b, c] into a + (b + c)
      # Passes an index to the block, counting from the right
      # Read more about folds:
      # * http://www.haskell.org/haskellwiki/Fold
      # * http://en.wikipedia.org/wiki/Fold_(higher-order_function)
      def foldr_i(z, xs, &f)
        xs.reverse_each.each_with_index.inject(z) { |b, (a, i)| f.call a, b, i }
      end
    end
  end
end
