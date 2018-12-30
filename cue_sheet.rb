require 'csv'
require 'bigdecimal'

class CueSheet
  class Cue
    class Road
      TYPES = {K: '県道', R: '国道'}

      def self.parse_roads(col_value)
        return [] unless col_value

        (col_value.remove(/\s+/).split(/\s*[,、，・･]\s*/) || []).map do |road_src|
          parse(road_src)
        end
      end

      def self.parse(road_src)
        /([KR])(\d+)/.match(road_src).try! do |m|
          new(road_src, m[1], m[2])
        end || new(road_src)
      end

      def initialize(src, type = nil, number = nil)
        @type = type
        @number = number
        @src = src
      end

      def named?
        @type
      end

      def as_is
        @src unless named?
      end

      def to_s
        @src
        # as_is || "#{TYPES[@type.to_sym]}#{@number}号"
      end
    end


    class Point
      def self.parse(point_src)
        point_src.match(/^S(「(.+)」)?/).try! do |m|
          new(point_src, true, m[2])
        end || new(point_src, false)
      end

      def initialize(src, signal = nil, signal_name = nil)
        @src = src
        @signal = signal
        @signal_name = signal_name
      end

      attr_reader :signal, :signal_name

      def as_is
        @src if !@signal
      end

      def to_s
        as_is || ("🚥#{"[#{@signal_name}]" if @signal_name }")
      end
    end


    def initialize(row, sheet, index)
      @row = row
      @sheet = sheet
      @index = index
    end

    attr_reader :row

    def no
      row['No'].to_i
    end

    def point_src
      row['通過点']
    end

    def point
      Point.parse(point_src)
    end

    def direction_src
      row['進路']
    end

    def direction
      direction_symbol || direction_src
    end

    def direction_symbol
      {
          '左折' => '↰',
          '右折' => '↱'
      }[direction_src]
    end

    def road_src
      row['道']
    end

    def roads
      Road.parse_roads(road_src)
    end

    def other
      row['情報・その他']
    end

    def road_to
      roads[0]
    end

    def block_distance_to_here
      BigDecimal(block_distance_to_here_src) if block_distance_to_here_src
    end

    def block_distance_to_here_src
      row['区間距離']
    end

    def total_distance_to_here
      BigDecimal(total_distance_to_here_src) if total_distance_to_here_src
    end

    def total_distance_to_here_src
      row['積算距離']
    end

    def prev
      @sheet.cues[@index - 1]
    end

    def next
      @sheet.cues[@index + 1]
    end

    def move
      result = [point, direction].join(' ')
      road_to.try! do |next_road|
        result += " #{next_road}に"
      end
      result
    end

    def percent
      format('%.1f%%', (total_distance_to_here / @sheet.goal_distance) * 100)
    end

    def route
      "#{block_distance_to_here.to_f}km先(#{prev.roads.map { |r| "#{r}〜" }.join}) :#{percent}" if roads && !start?
    end

    def start?
      @index.zero?
    end

    def to_s
      [
          route,
          "#{no}: #{move}",
          ("(#{other})" if other),
          '',
      ].compact.join("\n")
    end
  end

  def initialize
    @cues = CSV.read('src.tsv', col_sep: "\t", headers: :first_row).map.with_index do |row, index|
      row = row.each_with_object({}) do |(key, value), hash|
        hash[key] = (value.gsub(/[ 　]+/, ' ').strip if value)
      end
      Cue.new(row, self, index)
    end
  end

  def cues
    @cues
  end

  def goal_distance
    cues.last.total_distance_to_here
  end

  def to_s
    cues.join("\n")
  end
end
