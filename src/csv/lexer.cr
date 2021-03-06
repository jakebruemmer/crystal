# A CSV lexer lets you consume a CSV token by token. You can use this to efficiently
# parse a CSV without the need to allocate intermediate arrays.
#
# ```
# lexer = CSV::Lexer.new "one,two\nthree"
# lexer.next_token # => CSV::Token(@kind=Cell, @value="one")
# lexer.next_token # => CSV::Token(@kind=Cell, @value="two")
# lexer.next_token # => CSV::Token(@kind=Newline, @value="two")
# lexer.next_token # => CSV::Token(@kind=Cell, @value="three")
# lexer.next_token # => CSV::Token(@kind=Eof, @value="three")
# ```
abstract class CSV::Lexer
  # Creates a CSV lexer from a string.
  def self.new(string : String)
    StringBased.new(string)
  end

  # Creates a CSV lexer from an IO.
  def self.new(io : IO)
    IOBased.new(io)
  end

  # Returns the current `Token`.
  getter token

  # :nodoc:
  def initialize
    @token = Token.new
    @buffer = MemoryIO.new
    @column_number = 1
    @line_number = 1
    @last_empty_column = false
  end

  private abstract def consume_unquoted_cell
  private abstract def next_char_no_column_increment
  private abstract def current_char

  # Rewinds this lexer to its beginning.
  abstract def rewind

  # Returns the next `Token` in this CSV.
  def next_token
    if @last_empty_column
      @last_empty_column = false
      @token.kind = Token::Kind::Cell
      @token.value = ""
      return @token
    end

    case current_char
    when '\0'
      @token.kind = Token::Kind::Eof
    when ','
      @token.kind = Token::Kind::Cell
      @token.value = ""
      check_last_empty_column
    when '\r'
      @token.kind =
        case next_char
        when '\0'
          :eof
        when '\n'
          case next_char
          when '\0'
            Token::Kind::Eof
          else
            Token::Kind::Newline
          end
        else
          Token::Kind::Newline
        end
    when '\n'
      @token.kind = next_char == '\0' ? Token::Kind::Eof : Token::Kind::Newline
    when '"'
      @token.kind = Token::Kind::Cell
      @token.value = consume_quoted_cell
    else
      @token.kind = Token::Kind::Cell
      @token.value = consume_unquoted_cell
    end
    @token
  end

  private def consume_quoted_cell
    @buffer.clear
    while true
      case char = next_char
      when '\0'
        raise "unclosed quote"
        break
      when '"'
        case next_char
        when ','
          check_last_empty_column
          break
        when '\r', '\n', '\0'
          break
        when '"'
          @buffer << '"'
        else
          raise "expecting comma, newline or end, not #{current_char.inspect}"
        end
      else
        @buffer << char
      end
    end
    @buffer.to_s
  end

  private def check_last_empty_column
    case next_char
    when '\r', '\n', '\0'
      @last_empty_column = true
    end
  end

  private def next_char
    @column_number += 1
    char = next_char_no_column_increment
    if char == '\n' || char == '\r'
      @column_number = 0
      @line_number += 1
    end
    char
  end

  private def raise(msg)
    ::raise CSV::MalformedCSVError.new(msg, @line_number, @column_number)
  end
end
