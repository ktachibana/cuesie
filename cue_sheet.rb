require 'csv'
require 'bigdecimal'
require 'open-uri'
require 'uri'

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

      def pc?
        @src&.match?(/^PC(\d+)/)
      end

      def to_s
        as_is || ("🚥#{"[#{@signal_name}]" if @signal_name }")
      end
    end


    extend ::Memoist

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

    def direction_ref(table)
      key = {
          '左折' => :l,
          '右折' => :r,
          '直進' => :s
      }[direction_src]
      table[key]
    end

    def road_src
      row['道']
    end

    def roads
      Road.parse_roads(road_src)
    end
    memoize :roads

    def other
      row['情報・その他']
    end

    def roads_to_here
      prev&.roads
    end

    def road_to
      roads[0]
    end

    def block_distance_to_here
      BigDecimal(block_distance_to_here_src || prev&.block_distance_to_here_src || '0')
    end

    def block_distance_to_here_src
      row['区間距離']
    end

    def total_distance_to_here
      BigDecimal(total_distance_to_here_src || prev&.total_distance_to_here_src || '0')
    end

    def total_distance_to_here_src
      row['積算距離']
    end

    def prev
      @sheet.cues.at(@index - 1) if 0 < @index
    end

    def next
      @sheet.cues.at(@index + 1)
    end

    def move
      result = [point, direction].join(' ')
      road_to.try! do |next_road|
        result += " #{next_road}に"
      end
      result
    end

    def progress
      total_distance_to_here / @sheet.goal_distance
    end

    def percent
      format('%.1f%%', progress * 100)
    end

    TIME_PATTERN = %r|(?:(?:(?<year>\d+)/)?(?<month>\d+)\/(?<day>\d+)[ 　]+)?(?<hour>\d+):(?<min>\d+)|

    def times
      current_time = prev.try! { |prev_cue| prev_cue.times.last } || Time.current.beginning_of_year

      all_time_parts.map do |time_parts|
        current_time = current_time.change(time_parts)
        current_time
      end.presence || [current_time]
    end
    memoize :times

    def all_time_parts
      all_match(TIME_PATTERN, other).map do |time_parts_str|
        time_parts_str.reject { |_k, v| v.blank? }.map { |k, v| [k.to_sym, v.to_i] }.to_h
      end
    end

    def all_match(regexp, string)
      Enumerator.new do |y|
        current = string.to_s
        while (match = regexp.match(current))
          y << match.named_captures
          current = match.post_match
        end
      end
    end

    def route
      "#{block_distance_to_here.to_f}km先(#{prev.roads.map { |r| "#{r}〜" }.join}) :#{percent}" if roads && !start?
    end

    def start?
      @index.zero?
    end

    def pc?
      point.pc?
    end

    def estimate_time
      (@sheet.start_time + (@sheet.time_duration * progress.to_f))
    end
  end

  def self.load(sheet_url)
    export_url = to_export_url(sheet_url)

    all_data = CSV.parse(open(export_url).read.force_encoding('UTF-8'))

    indices = {
        'No' => /^NO/i,
        '通過点' => /^通過点/,
        '進路' => /^進路/,
        '道' => /^ルート/,
        '区間距離' => /^区間/,
        '積算距離' => /^積算/,
        '情報・その他' => /^情報/
    }.map do |column, matcher|
      [column, search_in_head(all_data, matcher)[1]]
    end.to_h
    row_begin_index = indices.values[0][0] + 1
    col_indices = indices.map do |column, index|
      [column, index[1]]
    end.to_h

    data = all_data[row_begin_index..-1]
    data = data.take_while { |row| row[col_indices['No']].present? }
    data = data.map do |row|
      col_indices.map do |column, index|
        value = row[index]
        value = value.gsub(/[ 　]+/, ' ').strip if value
        [column, value]
      end.to_h
    end

    title, _ = search_in_head(all_data, /^\d+BRM/)
    new(data, title)
  end

  def self.to_export_url(sheet_url)
    url = URI(sheet_url)
    gid = url.fragment[/gid=(\d+)/, 1]
    query = "#{url.query}&format=csv&gid=#{gid}"
    url + "export?#{query}"
  end

  def self.search_in_head(all_data, matcher)
    all_data.first(10).each_with_index do |row, row_i|
      row.each_with_index do |value, col_i|
        return [value, [row_i, col_i]] if matcher === value
      end
    end
    nil
  end

  HEADERS = %w(No 通過点 進路 道 区間距離 積算距離 情報・その他)

  def initialize(data, title)
    @cues = data.map.with_index do |row, index|
      Cue.new(row, self, index)
    end
    @title = title
  end

  attr_reader :cues, :title

  def goal_distance
    cues.last.total_distance_to_here
  end

  def to_s
    cues.join("\n")
  end

  def start_time
    cues.first.times&.first
  end

  def end_time
    cues.last.times&.last
  end

  def time_duration
    end_time - start_time
  end
end
