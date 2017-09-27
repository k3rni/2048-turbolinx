require 'forwardable'
require 'base64'
require 'byebug'

class Board
  extend Forwardable
  attr_reader :rows

  class GameOver < RuntimeError; end

  def initialize(w=4, h=4)
    @width, @height = w, h
    @rows = (1..@height).map { Array.new(@width, 0) }
  end

  def to_s
    rows.map do |row|
      row.map { |el| "%5d" % el }.join(' ')
    end.join("\n")
  end

  def_delegators :@rows, :[], :[]=

  def occupied?(row, col)
    self[row][col] != 0
  end
  
  def get_row(row)
    self[row].dup
  end

  def get_col(col)
    (0..@height-1).map { |row| self[row][col] }
  end

  def replace_row(row, values)
    self[row] = values
  end

  def replace_col(col, values)
    (0..@height-1).each { |row| self[row][col] = values[row] }
  end

  def each_col
    (0..@width-1).each { |col| yield col }
  end

  def each_row
    (0..@height-1).each { |row| yield row }
  end

  def each_col_reverse
    (@width-1).downto(0).each { |col| yield col }
  end

  def each_row_reverse
    (@height-1).downto(0).each { |row| yield row }
  end

  # Destructively merge vector SRC into DEST
  # Both are of length `size`
  def sum!(src, dest)
    (0..src.size-1).each do |i|
      if src[i] == dest[i]
        src[i] = 0
        dest[i] *= 2
      end
    end
    [src, dest]
  end

  def clear_blanks(vec, pad_end=true)
    squashed = vec.reject(&:zero?)
    padding = Array.new(vec.size - squashed.size, 0)
    pad_end ? (squashed + padding) : (padding + squashed)
  end

  def spawn_tile(*choices)
    raise GameOver if rows.flatten.select(&:zero?).empty?

    begin
      col, row = rand(@width), rand(@height)
    end while occupied?(row, col)
    self[row][col] = choices.sample
    self
  end

  def move_up
    each_col { |col| replace_col(col, clear_blanks(get_col(col))) }
    each_row do |row|
      next if row == @height - 1
      top, bottom = get_row(row), get_row(row + 1)
      bottom, top = sum!(bottom, top)
      replace_row(row, top)
      replace_row(row + 1, bottom)
    end
    each_col { |col| replace_col(col, clear_blanks(get_col(col))) }
    self
  end

  def move_down
    each_col { |col| replace_col(col, clear_blanks(get_col(col), false)) }
    each_row_reverse do |row|
      next if row == 0
      top, bottom = get_row(row - 1), get_row(row)
      top, bottom = sum!(top, bottom)
      replace_row(row - 1, top)
      replace_row(row, bottom)
    end
    each_col { |col| replace_col(col, clear_blanks(get_col(col), false)) }
    self
  end

  def move_left
    each_row { |row| replace_row(row, clear_blanks(get_row(row))) }
    each_col do |col|
      next if col == @width - 1
      left, right = get_col(col), get_col(col + 1)
      right,  left = sum!(right, left)
      replace_col(col, left)
      replace_col(col + 1, right)
    end
    each_row { |row| replace_row(row, clear_blanks(get_row(row))) }
    self
  end

  def move_right
    each_row { |row| replace_row(row, clear_blanks(get_row(row), false)) }
    each_col_reverse do |col|
      next if col == 0
      left, right = get_col(col - 1), get_col(col)
      left, right = sum!(left, right)
      replace_col(col - 1, left)
      replace_col(col, right)
    end
    each_row { |row| replace_row(row, clear_blanks(get_row(row), false)) }
    self
  end

  def serialize
    str = [@width, @height, *rows.flatten].pack("CC" + ('S' * (@width * @height))).sub(/\0+$/, '')
    Base64.strict_encode64 str
  end

  def self.deserialize(str)
    raw = Base64.decode64(str)
    w, h = raw.unpack('CC')
    raw[0..1] = ''
    raw += ("\0" * (w * h * 2 - raw.size))
    new(w, h).tap do |board|
      (0..h - 1).each do |rownum|
        row_data = raw[0..2*w-1].unpack('S' * w)
        raw[0..2*w-1] = ''
        board.replace_row(rownum, row_data)
      end
    end
  end

  def self.bare_board_code(w, h)
    Base64.strict_encode64 [w, h].pack('CC')
  end

  def clone
    Board.deserialize(serialize)
  end
end

require 'sinatra'

style = %{
<style type='text/css'>
td {
  border: 4px solid #eee;
  font-size: 24px;
  height: 32px; width: 32px;
  text-align: center;
}
</style>
}

turbolinks = %{<script type='text/javascript' src='turbolinks.js'></script>}
def html(board)
  ['<table>', *(board.rows.map do |row|
     ['<tr>', row.map { |v| "<td class='#{v}'>#{v}</td>" }, '</tr>']
   end), '</table>'].join('')
end

def links(board)
  ["<a href='/#{board.clone.move_left.serialize}'>left</a>",
   "<a href='/#{board.clone.move_up.serialize}'>up</a>",
   "<a href='/#{board.clone.move_down.serialize}'>down</a>",
   "<a href='/#{board.clone.move_right.serialize}'>right</a>",
  ].join(' | ')
end

get '/' do
  redirect "/#{Board.new(4, 4).serialize}"
end

get '/*code' do |code|
  headers "Cache-Control" => "no-cache"
  board = Board.deserialize(code).spawn_tile(2, 4)
  turbolinks + style + html(board) + links(board)
end

