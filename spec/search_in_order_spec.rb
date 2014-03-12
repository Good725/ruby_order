require 'spec_helper'

class Issue < ActiveRecord::Base
  DISPLAY_ORDER = [
      [:priority, %w(high medium low)],
      [:valid_votes_count, :desc, sql: '(votes - suspicious_votes)'],
      [:updated_at, :desc],
      [:id, :desc]
  ]

  def valid_votes_count
    votes - suspicious_votes
  end

  include SearchInOrder
  search_in_order :display_order, DISPLAY_ORDER
end

describe 'SearchInOrder.search_in_order' do

  t        = Time.now
  datasets = [
      [
          ['high', 5, 0, t],
          ['high', 5, 1, t],
          ['high', 5, 1, t - 1.day],
          ['medium', 10, 0, t],
          ['medium', 10, 5, t],
          ['low', 30, 0, t + 1.day]
      ],
      [
          ['high', 5, 0, t],
          ['high', 5, 1, t],
          ['high', 5, 1, t - 1.day],
          ['low', 30, 0, t + 1.day]
      ],
      [
          ['high', 5, 1, t - 1.day],
          ['low', 30, 0, t + 1.day]
      ],
      [
          ['medium', 5, 1, t - 1.day]
      ],

  ]

  datasets.each_with_index do |ds, i|
    it "is ordered correctly (test data #{i})" do
      issues = ds.map do |attr|
        Issue.new(priority: attr[0], votes: attr[1], suspicious_votes: attr[2], updated_at: attr[3])
      end
      issues.reverse_each(&:save!)
      expect(Issue.display_order.scope.to_a).to eq(issues)
      issues.each_slice(2) do |prev, cur|
        cur ||= issues.first
        expect(prev.display_order.next_item).to eq(cur)
        expect(cur.display_order.prev_item).to eq(prev)
        expect(cur.display_order.scope.count).to eq(Issue.count)
        expect(cur.display_order.items_before.count + 1 + cur.display_order.items_after.count).to eq(cur.display_order.count)
      end
    end
  end

  before do
    Issue.delete_all
  end

  before :all do
    ActiveRecord::Schema.define do
      self.verbose = false

      create_table :issues do |t|
        t.column :priority, :string
        t.column :votes, :integer
        t.column :suspicious_votes, :integer
        t.column :announced_at, :datetime
        t.column :updated_at, :datetime
      end
    end

    Issue.reset_column_information
  end
end
